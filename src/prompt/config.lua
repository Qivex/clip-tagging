------------------
-- DEPENDENCIES --
------------------

-- IUP
local iup = require("iuplua")


-------------
-- GLOBALS --
-------------

-- Default values for auto-fill
local defaultDatabase, defaultVLC, defaultPassword

-- Entered values returned after destroy
local configDatabase, configVLC, configPassword



-------------
-- IUP GUI --
-------------

-- File dialogs
local dialog_new_db = iup.filedlg({
	title = "New Database",
	dialogtype = "SAVE",
	filter = "*.tags.sqlite3",
	filterinfo = "Tag Database (*.tags.sqlite3)",
	file = "new.tags.sqlite3"
})

local dialog_open_db = iup.filedlg({
	title = "Open Database",
	dialogtype = "FILE",
	filter = "*.tags.sqlite3",
	filterinfo = "Tag Database (*.tags.sqlite3)",
})

local dialog_open_vlc = iup.filedlg({
	title = "Open VLC Player",
	dialogtype = "FILE",
	directory = "c:\\Program Files\\VideoLAN\\VLC",
	filter = "vlc.exe",
	filterinfo = "VLC Player executable (vlc.exe)",
})


-- Config dialog
local button_fileselect_vlc = iup.button({title = "...", size = "20x"})
local button_fileselect_db  = iup.button({title = "...", size = "20x"})
local button_confirm        = iup.button({title = "Confirm"})
local button_autofill       = iup.button({title = "Autofill"})

local text_path_vlc = iup.text({expand = "HORIZONTAL"})
local text_path_db  = iup.text({expand = "HORIZONTAL"})
local text_password = iup.text({expand = "HORIZONTAL"})

local dialog_config = iup.dialog({
	title = "VLC Tag Manager - Config",
	minsize = "400x",
	iup.vbox({
		gap = 10,
		margin = "10x10",
		iup.label({title = "Database location (leave empty to create new)"}),
		iup.hbox({
			gap = 10,
			margin = 0,
			alignment = "ABOTTOM",
			text_path_db,
			button_fileselect_db
		}),
		iup.label({title = "VLC location"}),
		iup.hbox({
			gap = 10,
			margin = 0,
			alignment = "ABOTTOM",
			text_path_vlc,
			button_fileselect_vlc
		}),
		iup.label({title = "VLC password"}),
		text_password,
		iup.hbox({
			gap = 10,
			margin = 0,
			button_confirm,
			button_autofill
		})
	})
})



---------------
-- CALLBACKS --
---------------

-- File dialogs
function button_fileselect_db:action()
	dialog_open_db:popup()
	if dialog_open_db.status == "0" then
		text_path_db.value = dialog_open_db.value
	end
end

function button_fileselect_vlc:action()
	dialog_open_vlc:popup()
	if dialog_open_vlc.status == "0" then
		text_path_vlc.value = dialog_open_vlc.value
	end
end


-- Confirm
function button_confirm:action()
	if text_path_vlc.value == "" then
		iup.MessageError(dialog_config, "VLC Player is required!")
		return
	end
	if text_path_db.value == "" then
		dialog_new_db:popup()
		if dialog_new_db.status ~= "-1" then
			text_path_db.value = dialog_new_db.value
		end
		return
	end
	-- Store return values
	configDatabase = text_path_db.value
	configVLC      = text_path_vlc.value
	configPassword = text_password.value
	-- Break MainLoop
	dialog_config:destroy()
end


-- Autofill
function button_autofill:action()
	text_path_db.value  = defaultDatabase
	text_path_vlc.value = defaultVLC
	text_password.value = defaultPassword
end


-- Early cancel
function dialog_config:close_cb()
	iup.Close()
end



------------
-- EXPORT --
------------

 -- Inspired by GetFile() GetText() etc.
function GetConfig(db, vlc, pw)
	-- Store provided defaults
	defaultDatabase = db
	defaultVLC = vlc
	defaultPassword = pw
	-- Show dialog
	dialog_config:show()
	iup.MainLoop()
	-- Return entered values
	return configDatabase, configVLC, configPassword
end


return GetConfig