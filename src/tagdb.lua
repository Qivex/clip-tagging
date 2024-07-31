------------------
-- DEPENDENCIES --
------------------

-- LuaSQLite
local sqlite3 = require("lsqlite3complete")



---------
-- SQL --
---------

local SCHEMA = [[
CREATE TABLE file (
	id INTEGER PRIMARY KEY,
	name TEXT NOT NULL,
	path TEXT NOT NULL,
	length INTEGER,
	width INTEGER,
	height INTEGER,
	size INTEGER
);
CREATE TABLE tag (
	id INTEGER PRIMARY KEY,
	name TEXT NOT NULL,
	description TEXT,
	parent INTEGER REFERENCES tag(id)
);
CREATE TABLE tagging (
	fileid INTEGER NOT NULL REFERENCES file(id),
	tagid INTEGER NOT NULL REFERENCES tag(id),
	PRIMARY KEY (fileid, tagid)
);
]]

local SUBQUERY_HAS_TAGGING = "EXISTS(SELECT 1 FROM tagging WHERE fileid = :fileid AND tagid = :tagid)"



-------------
-- METHODS --
-------------

-- Helper
local function log(...)
	print("Database: " .. string.format(...))
end

local function fileExists(path)
	local exists = io.open(path, "r")
	if exists then
		exists:close()
		return true
	end
	return false
end


-- Assertions
local function checkCode(db, return_code, expected_code)
	if return_code ~= expected_code then
		error(string.format("Database action failed with code %i: %s", db:errcode(), db:errmsg()), 2)
	end
end

local function checkOK(db, return_code)
	checkCode(db, return_code, sqlite3.OK)
end

local function checkStep(db, return_code)
	checkCode(db, return_code, sqlite3.DONE)
end


-- Parse and wrap queries
local function prepareQueryCall(db, query)
	local preparedStatement = db:prepare(query)
	assert(
		preparedStatement
		and preparedStatement.isopen
		and preparedStatement:isopen(),
		"Statement could not be prepared! " .. db:errcode() .. db:errmsg()
	)
	if preparedStatement:columns() > 0 then
		-- Call returns iterator
		return function(...)
			preparedStatement:reset()
			preparedStatement:bind_values(...)
			return preparedStatement:urows()
		end
	else
		-- Call returns result code (expect sqlite3.DONE)
		return function(...)
			preparedStatement:reset()
			preparedStatement:bind_values(...)
			return preparedStatement:step()
		end
	end
end


-- Wrap query calls as methods
local function getAvailableMethods(db)
	local SUBQUERY_IS_PARENT = "EXISTS(SELECT 1 FROM tag AS childtag WHERE childtag.parent = tag.id)"
	local SUBQUERY_SELECT_TAGS = string.format("SELECT id, name, %s FROM tag", SUBQUERY_IS_PARENT)
	-- Prepare all queries
	local queries = {
		insertTag = prepareQueryCall(db, "INSERT INTO tag VALUES (NULL, :name, :description, :parent)"),
		selectTag = prepareQueryCall(db, "SELECT name, description, parent FROM tag WHERE id = :id"),
		selectChildTags = prepareQueryCall(db, SUBQUERY_SELECT_TAGS .. " WHERE tag.parent = :parent ORDER BY name"),
		selectRootTags = prepareQueryCall(db, SUBQUERY_SELECT_TAGS .. " WHERE tag.parent IS NULL ORDER BY name"),
		updateTagName = prepareQueryCall(db, "UPDATE tag SET name = :name WHERE id = :id"),
		updateTagDescription = prepareQueryCall(db, "UPDATE tag SET description = :desc WHERE id = :id"),
		deleteTag = prepareQueryCall(db, "DELETE FROM tag WHERE id = :id"),
		insertTagging = prepareQueryCall(db, "INSERT INTO tagging VALUES (:fileid, :tagid)"),
		selectTagging = prepareQueryCall(db, "SELECT tagid FROM tagging WHERE fileid = :fileid"),
		deleteTagging = prepareQueryCall(db, "DELETE FROM tagging WHERE fileid = :fileid AND tagid = :tagid"),
		existsTagging = prepareQueryCall(db, "SELECT 1 FROM tagging WHERE tagid = :tagid LIMIT 1"),
		insertFile = prepareQueryCall(db, "INSERT INTO file (name, path) VALUES (:name, :path)"),
		selectFile = prepareQueryCall(db, "SELECT * FROM file WHERE name = :name AND path = :path"),
		selectFileMeta = prepareQueryCall(db, "SELECT length, width, height, size FROM file WHERE id = :id"),
		updateFileMeta = prepareQueryCall(db, "UPDATE file SET length = :length, width = :width, height = :height, size = :size WHERE id = :id")
	}
	-- Wrap query calls as methods
	return {
		createTag = function(name, description, parent)
			log("Creating new tag %s as child of %s", name, parent)
			checkStep(db, queries.insertTag(name, description, parent))
		end,
		getTagInfo = function(tagID)
			for name, description, parent in queries.selectTag(tagID) do
				log("Tag %i has name %s, description %s and parent %s", tagID, name, description, parent)
				return name, description, parent
			end
			log("No data available for tag %i", tagID)
			return nil
		end,
		getChildTags = function(parentID)
			if parentID == nil then
				return queries.selectRootTags()
			else 
				return queries.selectChildTags(parentID)
			end
		end,
		renameTag = function(tagID, newName)
			log("Renaming tag %i to %s", tagID, newName)
			checkStep(db, queries.updateTagName(newName, tagID))
		end,
		editTagDescription = function(tagID, newDescription)
			log("Setting tag description of %i to %s", tagID, newDescription)
			checkStep(db, queries.updateTagDescription(newDescription, tagID))
		end,
		removeTag = function(tagID)
			log("Removing tag %i", tagID)
			checkStep(db, queries.deleteTag(tagID))
		end,
		addTagging = function(fileID, tagID)
			log("Adding tag %i to file %i", tagID, fileID)
			checkStep(db, queries.insertTagging(fileID, tagID))
		end,
		getTagsOfFile = queries.selectTagging,
		removeTagging = function(fileID, tagID)
			log("Removing tag %i from file %i", tagID, fileID)
			checkStep(db, queries.deleteTagging(fileID, tagID))
		end,
		isTagUsed = function(tagID)
			for _ in queries.existsTagging(tagID) do
				return true
			end
			return false
		end,
		createFile = function(filename, path)
			log("Creating file %s%s", path, filename)
			checkStep(db, queries.insertFile(filename, path))
		end,
		getFileIDFromPath = function(filename, path)
			for fileID in queries.selectFile(filename, path) do
				log("File %s%s has id %i", path, filename, fileID)
				return fileID
			end
			log("File %s%s not found", path, filename)
			return nil
		end,
		getFileMeta = function(fileID)
			for length, width, height, size in queries.selectFileMeta(fileID) do
				log("File %i has length %i, width %i, height %i and contains %i bytes", fileID, length, width, height, size)
				return length, width, height, size
			end
			log("No metadata available for file %i", fileID)
			return nil
		end,
		setFileMeta = function(fileID, length, width, height, size)
			checkStep(db, queries.updateFileMeta(length, width, height, size, fileID))
		end,
		closeDatabase = function()
			if db:close() == sqlite3.OK then	-- :close_vm()
				log("Closed successfully")
			else
				log("Open database could not be closed.\nCode: %i\nMessage: %s", db:errcode(), db:errmsg())
			end
		end
	}
end


-- Open database
local function prepareDB(path)
	-- Get handle
	local isNewDatabase = not fileExists(path)
	local handle = sqlite3.open(path)
	-- Apply schema to new database
	if isNewDatabase then
		checkOK(handle, handle:exec(SCHEMA))
	end
	-- Provide wrapped calls to interact with database
	return getAvailableMethods(handle)
end



------------
-- EXPORT --
------------

return {
	prepareDB = prepareDB,
	version = sqlite3.version(),
	lversion = sqlite3.lversion()
}