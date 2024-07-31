------------------
-- DEPENDENCIES --
------------------

-- IUP
local iup = require("iuplua")



-------------
-- GLOBALS --
-------------

-- Entered values returned after destroy
local tagname, description



-------------
-- IUP GUI --
-------------

-- Tag dialog
local text_tagname     = iup.text({expand = "HORIZONTAL"})
local text_description = iup.multiline({expand = "HORIZONTAL", visiblelines = 5, wordwrap = "YES", mask = "[^/n]*"})

local button_confirm = iup.button({title = "Confirm"})
local button_cancel  = iup.button({title = "Cancel"})

local dialog_taginfo = iup.dialog({
	title = "Enter tag information",
	minsize = "300x",
	iup.vbox({
		gap = 10,
		margin = "10x10",
		iup.label({title = "Tagname"}),
		text_tagname,
		iup.label({title = "Description"}),
		text_description,
		iup.hbox({
			gap = 10,
			margin = 0,
			expand = "HORIZONTAL",
			button_confirm,
			button_cancel
		})
	})
})



---------------
-- CALLBACKS --
---------------

-- Tag Dialog
function dialog_taginfo:show_cb(state)
	if state == iup.SHOW then
		text_tagname.value = ""
		text_description.value = ""
	elseif state == iup.HIDE then
		iup.ExitLoop()
	end
end


-- Confirm
function button_confirm:action()
	if text_tagname.value == "" then
		iup.MessageError(dialog_taginfo, "Tagname is required!")
		return
	end
	tagname = text_tagname.value
	description = text_description.value
	if description == "" then
		description = nil
	end
	dialog_taginfo:hide()
end


-- Cancel
function button_cancel:action()
	tagname = nil
	description = nil
	dialog_taginfo:hide()
end



------------
-- EXPORT --
------------

 -- Inspired by GetFile() GetText() etc.
 function GetTaginfo(parent)
	-- Show dialog
	dialog_taginfo.parentdialog = parent
	dialog_taginfo:showxy(iup.CENTERPARENT, iup.CENTERPARENT)
	iup.MainLoop()
	-- Return entered values
	return tagname, description
end


return GetTaginfo