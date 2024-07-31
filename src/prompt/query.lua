------------------
-- DEPENDENCIES --
------------------

-- IUP
local iup = require("iuplua")

-- Tag database
local sqlite3 = require("lsqlite3complete")



-------------
-- GLOBALS --
-------------

-- Handle to & path of readonly database
local db, dbPath

-- Relation used for positioning
local parentDialog

-- Result values returned after destroy
local columnNames, resultColumns



-------------
-- IUP GUI --
-------------

-- Query dialog
local text_query = iup.multiline({expand = "HORIZONTAL", visiblelines = 8, wordwrap = "YES"})

local checkbox_skip = iup.toggle({title = "Skip result table"})

local button_execute = iup.button({title = "Execute"})

local dialog_query = iup.dialog({
	title = "Execute custom query",
	minsize = "350x",
	iup.vbox({
		text_query,
		iup.hbox({
			alignment = "ACENTER",
			gap = 10,
			margin = "10x10",
			button_execute,
			checkbox_skip
		})
	})
})



---------------
-- CALLBACKS --
---------------

-- Query dialog
function dialog_query:map_cb()
	-- Open database in readonly-mode!
	db = sqlite3.open(dbPath, sqlite3.OPEN_READONLY)
end

function dialog_query:close_cb()
	iup.ExitLoop()
end

function dialog_query:destroy_cb()
	if db then
		db:close()
	end
end


-- Execute query
function button_execute:action()
	-- Prepare statement
	local query = db:prepare(text_query.value)
	-- Check if statement is valid
	if not(query and query.isopen and query:isopen()) then
		iup.MessageError(dialog_query, "Query is invalid")
		return
	end
	-- Check for unbound params
	if query:bind_parameter_count() > 0 then
		iup.MessageError(dialog_query, "Query includes unbound parameters!")
		return
	end
	-- Get result columns from statement (before executing)
	columnNames = query:get_names()
	local columnCount = #columnNames
	-- Prepare result containment
	resultColumns = {}
	for col = 1, columnCount do
		table.insert(resultColumns, {})
	end
	-- Execute query
	for row in query:rows() do
		for col = 1, columnCount do
			table.insert(resultColumns[col], row[col] or "NULL")
		end
	end
	-- Skip result table
	if checkbox_skip.value == "ON" then
		return
	end
	-- Insert result rows into separate lists (for each column)
	local columnLists = {}
	for col, name in pairs(columnNames) do
		local list = iup.list({scrollbar = "NO"})
		list.map_cb = function(self)
			self.appenditem = name
			for row, value in pairs(resultColumns[col]) do
				if value == nil then
					self.appenditem = "NULL"
				else
					self.appenditem = value
				end
			end
		end
		table.insert(columnLists, list)
	end
	-- Initialize result dialog
	local dialog_result = iup.dialog({
		title = "Result",
		iup.scrollbox({
			maxsize = "400x600",
			iup.hbox(columnLists)
		})
	})
	function dialog_result:close_cb()
		dialog_result:destroy()
		iup.ExitLoop()
	end
	-- Transition
	dialog_query:hide()
	dialog_result.parentdialog = parentDialog
	dialog_result:showxy(iup.CENTERPARENT, iup.CENTERPARENT)
end



------------
-- EXPORT --
------------

 -- Inspired by GetFile() GetText() etc.
 function OpenQuery(path, parent)
	dbPath = path
	parentDialog = parent
	-- Show dialog
	dialog_query.parentdialog = parentDialog
	dialog_query:popup(iup.CENTERPARENT, iup.CENTERPARENT)
	iup.MainLoop()
	-- Cancelled before result
	if columnNames == nil then
		return nil
	end
	-- Find columns "path" and "name"
	local pathColumn, nameColumn
	for index, columnName in pairs(columnNames) do
		if columnName == "path" then
			pathColumn = index
		elseif columnName == "name" then
			nameColumn = index
		end
	end
	if pathColumn == nil or nameColumn == nil then
		return nil
	end
	-- Combine into location
	local result = {}
	for row, path in pairs(resultColumns[pathColumn]) do
		table.insert(result, path .. resultColumns[nameColumn][row])
	end
	return result
end


return OpenQuery