------------------
-- DEPENDENCIES --
------------------

-- IUP
local iup = require("iuplua")

-- Tag database (wrapper around LuaSQLite)
local tagdb = require("tagdb")

-- Config dialog (wrapped IUP dialog)
local GetConfig = require("prompt.config")
local GetTaginfo = require("prompt.tag")
local OpenQuery = require("prompt.query")

-- curl
assert(os.execute("where curl >nul"), "curl not found")



--------------
-- COMMANDS --
--------------

local TEMPFILE = "C:\\curl-vlc-status.json"
local PARAM_RUN_VLC = [[--extraintf=http --http-password="%s" %s]]
local CMD_CURL_VLC = [[curl "localhost:8080%s" --silent --connect-timeout 0.01 --user ":%s" --output ]] .. TEMPFILE
local CMD_DIR = [[dir "%s" /s /b]]
local CMD_DIR_SINGLE = [[dir "%s%s" /-c]]



-------------
-- GLOBALS -- 
-------------

local DEFAULT_DB_PATH = "c:\\clips.tags.sqlite3"
local DEFAULT_VLC_PATH = "c:\\Program Files\\VideoLan\\VLC\\vlc.exe"
local DEFAULT_VLC_PASSWORD = "please1change6me1"
local CONFIG_DB_PATH, CONFIG_VLC_PATH, CONFIG_VLC_PASSWORD
local dbMethods
local currentFileID, currentFileName, currentFilePath
local currentTagOrder	-- Used as a lookup for items in "list_tags"



-------------
-- IUP GUI --
-------------

-- File dialogs
local dialog_choose_videos = iup.filedlg({
	title = "Choose video files",
	dialogtype = "FILE",
	multiplefiles = "Yes"
})

local dialog_choose_folder = iup.filedlg({
	title = "Choose folder",
	dialogtype = "DIR"
})


-- About dialog
local dialog_help = iup.dialog({
	title = "About Tag Manager",
	iup.vbox({
		alignment = "ACENTER",
		gap = "10",
		margin = "10x10",
		iup.label({
			title = "Tag Manager",
			fontsize = 24
		}),
		iup.label({title = "by Qivex 2024 (c) MIT License"}),
		iup.label({
			title = string.format("%s  |  IUP %s  |  SQLite %s  |  LuaSQLite %s", _VERSION, iup.GetGlobal("VERSION"), tagdb.version, tagdb.lversion)
		}),
		iup.label({
			title = "Create tags to label and better sort your files!\n- All tags are stored in an SQLite database (.tags.sqlite extension)\n- Create your own tags depending on the files your tagging.\n- Tags can be arranged in a hierarchy.\n- Filter files by selecting tags (or writing an SQL query).\n- The result can be viewed directly in VLC as a playlist."
		})
	})
})


-- Tag tree context menu
local item_rename_tag = iup.item({title = "Rename\tF2"})
local item_edit_desc  = iup.item({title = "Edit description"})
local item_add_child  = iup.item({title = "Add child"})
local item_delete_tag = iup.item({title = "Delete"})

local menu_context_tag = iup.menu({
	item_rename_tag,
	item_edit_desc,
	item_add_child,
	item_delete_tag
})


-- Main Menu
local item_choose_videos = iup.item({title = "...from files\tCtrl+O"})
local item_choose_folder = iup.item({title = "...from folder\tCtrl+F"})
local item_choose_query  = iup.item({title = "...from query\tCtrl+Q"})
local item_about =         iup.item({title = "About\tF1"})

local submenu_choose = iup.submenu({
	title = "Choose",
	iup.menu({
		item_choose_videos,
		item_choose_folder,
		item_choose_query
	})
})

local submenu_about = iup.submenu({
	title = "About",
	iup.menu({
		item_about
	})
})

local menu_main = iup.menu({
	submenu_choose,
	submenu_about
})


-- File Frame
local label_filemeta = iup.label({expand = "YES", minsize = "x50"})

local button_scan_metadata = iup.button({title = "Scan Metadata", expand = "VERTICAL", padding = "20x"})

local list_tags = iup.list({expand = "HORIZONTAL", visiblelines = 10})

local frame_player = iup.frame({
	title = "No file selected",
	expand = "HORIZONTAL",
	iup.vbox({
		iup.hbox({
			margin = 0,
			button_scan_metadata,
			label_filemeta
		}),
		list_tags
	})
})


-- Main dialog
local button_playlist = iup.button({size = "40x", title = "Playlist"})
local button_clear    = iup.button({size = "40x", title = "Clear"})
local button_next     = iup.button({size = "40x", title = "Next"})

local list_files = iup.list({expand = "HORIZONTAL", visiblelines = 6})

local label_tagid   = iup.label({size = "30x"})
local label_tagdesc = iup.label({expand = "HORIZONTAL"})

local tree_tags = iup.tree({addroot = "YES", showrename = "YES", scrollvisible = "VERTICAL"})

local dialog_main = iup.dialog({
	title = "Tag Manager by Qivex",
	size = "300x",
	menu = menu_main,
	iup.vbox({
		margin = "10x10",
		gap = 10,
		iup.hbox({
			margin = 0,
			button_playlist,
			button_clear,
			button_next
		}),
		list_files,
		frame_player,
		iup.hbox({
			margin = 0,
			label_tagid,
			label_tagdesc
		}),
		tree_tags
	})
})



-------------
-- Methods --
-------------

-- VLC wrapper
function startVLC(path)
	return iup.Execute(CONFIG_VLC_PATH, PARAM_RUN_VLC:format(CONFIG_VLC_PASSWORD, path))
end

function curlVLC(path)
	return os.execute(CMD_CURL_VLC:format(path, CONFIG_VLC_PASSWORD))
end

function char2hex(c)
	return string.format("%%%02X", string.byte(c))
end

function urlEncode(path)
	local uri = "file:///" .. path:gsub("\\", "/")	
	return uri:gsub("([^%w ])", char2hex):gsub(" ", "+")
end


-- Tags
function showTagDetails(tagID)
	if tagID == nil then
		label_tagid.title = "No ID"
		label_tagdesc.title = "Abstract root containing all tags"
	else
		local _, description = dbMethods.getTagInfo(tagID)
		label_tagid.title = "ID " .. tagID
		label_tagdesc.title = description
	end
end

function getTagPath(tagID)
	local chain = {}
	local currentTag = tagID
	repeat
		local name, _, parent = dbMethods.getTagInfo(currentTag)
		table.insert(chain, 1, name)
		currentTag = parent	-- Repeat with parent (until root reached)
	until currentTag == nil
	return table.concat(chain, " > ")
end

function loadFileTagsIntoUI()
	list_tags.removeitem = "ALL"
	currentTagOrder = {}
	if currentFileID then
		for tagID in dbMethods.getTagsOfFile(currentFileID) do
			list_tags.appenditem = getTagPath(tagID)
			table.insert(currentTagOrder, tagID)
		end
	end
end


-- Metadata
function formatTime(seconds)
	local hours = math.floor(seconds / 3600)
	seconds = seconds - 3600 * hours
	local minutes = math.floor(seconds / 60)
	seconds = seconds - 60 * minutes
	return string.format("%02i:%02i:%02i", hours, minutes, seconds)
end

function loadFileMetaIntoUI()
	if currentFileID then
		local length, width, height, size = dbMethods.getFileMeta(currentFileID)
		if length then
			label_filemeta.title = string.format("%s\n%i x %i\n%i bytes", formatTime(length), width, height, size)
		else
			label_filemeta.title = "Metadata not scanned"
		end
	end
end

function updateFileMeta()
	if currentFileID then
		-- Request status from VLC API
		curlVLC("/requests/status.json")
		-- Read from tempfile
		local f = io.open(TEMPFILE, "r")
		local status = f:read("a")
		f:close()
		-- Parse JSON for length, width & height
		local length = status:match([["length":(%d+),]])
		local width, height = status:match([["Video_resolution":"(%d+)x(%d+)",]])
		-- Find file size from "dir" command
		local dir = io.popen(CMD_DIR_SINGLE:format(currentFilePath, currentFileName))
		local dirResult = dir:read("a")
		dir:close()
		local start = dirResult:find(currentFileName, 100, true)	-- Skip some of the dir-header, search plain
		local size = dirResult:match("%s+(%d+)%s", start - 19)
		-- Update DB
		dbMethods.setFileMeta(currentFileID, tonumber(length), tonumber(width), tonumber(height), tonumber(size))
		-- Update UI
		loadFileMetaIntoUI()
	end
end


-- Tagging
function getFileID(filename, path)
	local id = dbMethods.getFileIDFromPath(filename, path)
	if not id then
		dbMethods.createFile(filename, path)
		id = dbMethods.getFileIDFromPath(filename, path)
	end
	return id
end

function startTagging(file)
	-- Play in or open VLC
	if curlVLC("/requests/status.json?command=pl_empty") then
		curlVLC("/requests/status.json?command=in_play&input=" .. urlEncode(file)) -- Add new video
	else
		startVLC(file)
	end
	-- Update frame
	local path, title = file:match("(.-)([^\\]+)$")
	frame_player.title = title
	-- Update globals
	currentFileName = title
	currentFilePath = path
	currentFileID = getFileID(title, path)
	currentTagOrder = {}
	-- Update metainfo-labels
	loadFileMetaIntoUI()
	-- Load previous tags & video information
	loadFileTagsIntoUI()
end

function loadChildTags(tree, treeIndex)
	local newNodes = {}
	local parentID = tree:GetUserId(treeIndex)
	for tagID, tagName, isParent in dbMethods.getChildTags(parentID) do
		-- Link node to tag
		local node = {userid = tagID}
		-- Node type depends on field
		if isParent == 1 then
			node.branchname = tagName
		else
			node.leafname = tagName
		end
		table.insert(newNodes, node)
	end
	tree:AddNodes(newNodes, treeIndex)
end


-- Menu interaction
function chooseFiles()
	local d = dialog_choose_videos
	d:popup()
	if d.status == "0" then
		local path = d.directory
		-- Value 0 is directory
		for i=1, d.multivaluecount - 1 do
			local file = d["multivalue" .. i]
			list_files.appenditem = path .. file
		end
	end
end

function chooseFolder()
	local d = dialog_choose_folder
	d:popup()
	if d.status == "0" then
		local dir = io.popen(CMD_DIR:format(d.value))
		for path in dir:lines() do
			list_files.appenditem = path
		end
		dir:close()
	end
end

function chooseQuery()
	print("Query builder")
	local files = OpenQuery(CONFIG_DB_PATH, dialog_main)
	if files then
		for _, f in pairs(files) do
			list_files.appenditem = f
		end
	end
end

function openHelp()
	dialog_help.parentdialog = dialog_main
	dialog_help:popup(iup.CENTERPARENT, iup.CENTERPARENT)
end


-- List shortcut
function removeCurrentListItem(list)
	-- Remove selected item
	local selected = list.value
	list.removeitem = selected
	-- Select another item
	list.value = selected
	-- Special case if removed item was last
	if list.value == "0" then
		list.value = list.count
	end
end



---------------
-- Callbacks --
---------------

-- Tag tree
function tree_tags:map_cb()
	-- Add only root level
	tree_tags:AddNodes({branchname = "All Tags"})
end

function tree_tags:selection_cb(nodeIndex, status)
	if status == 1 then
		local tagID = self:GetUserId(nodeIndex)
		showTagDetails(tagID)
	end
end

function tree_tags:rightclick_cb(id)
	tree_tags.value = id
	menu_context_tag:popup(iup.MOUSEPOS, iup.MOUSEPOS)
end

function tree_tags:executeleaf_cb(treeIndex)
	if currentFileID then
		local tagID = self:GetUserId(treeIndex)
		dbMethods.addTagging(currentFileID, tagID)
		-- Update UI
		list_tags.appenditem = getTagPath(tagID)
		table.insert(currentTagOrder, tagID)
	end
end

function tree_tags:executebranch_cb(treeIndex)
	-- First expand requires loading child tags from database
	if tree_tags["childcount" .. treeIndex] == "0" then
		loadChildTags(tree_tags, treeIndex)
		-- Dirty: Collapse first to force expand in implicit branchopen_cb() later
		tree_tags["state" .. treeIndex] = "COLLAPSED"
	end
end

function tree_tags:rename_cb(index, newName)
	local selectedTag = tree_tags:GetUserId(index)
	if newName == "" then
		iup.MessageError(tree_tags, "Tag name must not be empty!")
		return iup.IGNORE
	end
	dbMethods.renameTag(selectedTag, newName)
	return iup.DEFAULT
end


-- Tree context menu
function item_rename_tag:action()
	tree_tags.rename = ""	-- Must be string!
end

function item_edit_desc:action()
	local selectedNode = tree_tags.value
	local selectedTag = tree_tags:GetUserId(selectedNode)
	local _, currentDescription = dbMethods.getTagInfo(selectedTag)
	local newDescription = iup.GetText("Edit description", currentDescription or "")
	if newDescription then
		newDescription = newDescription:gsub("[\r\n]", "")
		dbMethods.editTagDescription(selectedTag, newDescription)
		label_tagdesc.title = newDescription
	end
end

function item_add_child:action()
	local selectedNode = tree_tags.value
	local selectedTag = tree_tags:GetUserId(selectedNode)
	-- Prompt for tag information
	local newName, newDescription = GetTaginfo(tree_tags)
	if newName == nil then
		return
	end
	-- Insert into database
	dbMethods.createTag(newName, newDescription, selectedTag)
	-- Replace leaf with identical branch
	if tree_tags["kind" .. selectedNode] == "LEAF" then
		tree_tags["addbranch" .. selectedNode] = tree_tags["title" .. selectedNode]
		tree_tags["delnode" .. selectedNode] = "SELECTED"
		tree_tags:SetUserId(selectedNode, selectedTag)
	end
	-- Reload all child nodes (includes at least newly created one)
	tree_tags["delnode" .. selectedNode] = "CHILDREN"
	loadChildTags(tree_tags, selectedNode)
end

function item_delete_tag:action()
	local selectedNode = tree_tags.value
	local selectedTag = tree_tags:GetUserId(selectedNode)
	-- Make sure no files use this tag
	if dbMethods.isTagUsed(selectedTag) then
		iup.MessageError(tree_tags, "Tag is still applied to some files!")
		return
	end
	-- Make sure the tag has no childtags referring to it
	if tree_tags["kind" .. selectedNode] == "BRANCH" then
		iup.MessageError(tree_tags, "Tag has childtags!")
		return
	end
	-- Remove from database
	dbMethods.removeTag(selectedTag)
	-- Remove from tree
	local parentNode = tree_tags["parent" .. selectedNode]
	tree_tags["delnode" .. selectedNode] = "SELECTED"
	-- Replace parent branch with identical leaf
	if tree_tags["childcount" .. parentNode] == "0" then
		local parentTag = tree_tags:GetUserId(parentNode)
		tree_tags["insertleaf" .. parentNode] = tree_tags["title" .. parentNode]
		tree_tags["delnode" .. parentNode] = "SELECTED"
		tree_tags:SetUserId(parentNode, parentTag)
	end
end


-- Frame
function button_scan_metadata:action()
	updateFileMeta()
end


-- File list
function list_files:k_any(keycode)
	if keycode == iup.K_BS or keycode == iup.K_DEL then
		removeCurrentListItem(list_files)
	end
	return iup.CONTINUE
end

function list_files:dblclick_cb(selected)
	startTagging(list_files[selected])
end


-- File list controls
function button_playlist:action()
	for index = 1, tonumber(list_files.count) do
		curlVLC("/requests/status.json?command=in_enqueue&input=" .. urlEncode(list_files[index]))
	end
	curlVLC("/requests/status.json?command=pl_play")
end

function button_clear:action()
	curlVLC("/requests/status.json?command=pl_empty")
	list_files.removeitem = "ALL"
end

function button_next:action()
	removeCurrentListItem(list_files)
	if tonumber(list_files.count) > 0 then
		startTagging(list_files[list_files.value])
	end
end


-- Tag list
function list_tags:k_any(keycode)
	if keycode == iup.K_BS or keycode == iup.K_DEL then
		-- Find tagID
		local index = tonumber(list_tags.value)
		local tagID = currentTagOrder[index]
		dbMethods.removeTagging(currentFileID, tagID)
		-- Update UI
		table.remove(currentTagOrder, index)
		removeCurrentListItem(list_tags)
	end
	return iup.CONTINUE
end


-- Main menu
function item_choose_videos:action()
	chooseFiles()
end

function item_choose_folder:action()
	chooseFolder()
end

function item_choose_query:action()
	chooseQuery()
end

function item_about:action()
	openHelp()
end


-- Main dialog
function dialog_main:map_cb()
	-- Provide database methods globally
	dbMethods = tagdb.prepareDB(CONFIG_DB_PATH)
end

function dialog_main:k_any(keycode)
	local lookup = {
		[iup.K_cO] = chooseFiles,
		[iup.K_cF] = chooseFolder,
		[iup.K_cQ] = chooseQuery,
		[iup.K_F1] = openHelp
	}
	local action = lookup[keycode]
	if action then
		action()
	end
	return iup.CONTINUE
end

function dialog_main:destroy_cb()
	-- Close DB properly before quitting
	if dbMethods then
		dbMethods.closeDatabase()
	end
end



--------------
-- IUP Main --
--------------

if (iup.MainLoopLevel()==0) then
	-- Prompt for config
	CONFIG_DB_PATH,
	CONFIG_VLC_PATH,
	CONFIG_VLC_PASSWORD = GetConfig(DEFAULT_DB_PATH, DEFAULT_VLC_PATH, DEFAULT_VLC_PASSWORD)
	-- Show main dialog
	dialog_main:showxy(0, 0)
	iup.MainLoop()
	iup.Close()
	-- os.execute("taskkill /im vlc.exe")
end