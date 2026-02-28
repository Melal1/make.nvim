local M = {}

local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")
local Parse = require("make.modules.links.parse")
local Storage = require("make.modules.links.storage")
local Ui = require("make.modules.links.ui")

function M.ParseLinksBlock(content)
	return Parser.ParseLinkOptions(content)
end

function M.HasLinkOptions(content)
	local groups, individuals = Parser.ParseLinkOptions(content or "")
	return #groups > 0 or #individuals > 0
end

function M.LoadLinkOptions(makefile_path, fallback_content)
	return Storage.load_link_options(makefile_path, fallback_content)
end

function M.SaveLinkOptions(makefile_path, content, groups, individuals)
	return Storage.save_link_options(makefile_path, content, groups, individuals)
end

function M.SelectLinks(existing_flags, makefile_content, callback, opts)
	return Ui.select_links(existing_flags, makefile_content, callback, opts)
end

function M.GetExistingLinks(content, relative_path, base_name)
	local cached = Parser.GetCachedTargetLinks(content, relative_path)
	if cached then
		return cached
	end
	local section_content = Parser.ReadContentBetweenMarkers(content, relative_path)
	if type(section_content) == "table" then
		section_content = table.concat(section_content, "\n")
	end
	if not section_content or section_content == "" then
		return {}
	end

	local marker_info = Parser.FindMarker(content, relative_path, true, false)
	local target_key = (marker_info and marker_info.name) or Utils.FlattenRelativePath(relative_path)
	local target_name = Parser.FindExecutableTargetName(section_content, base_name, target_key)
	if not target_name then
		return {}
	end

	return Parser.GetLinksForTarget(section_content, target_name)
end

function M.UpdateLinksForEntry(content, relative_path, base_name, new_links)
	local marker_info = Parser.FindMarker(content, relative_path, true, true)
	if not marker_info.M_start or not marker_info.M_end then
		Utils.Notify("Markers not found for: " .. relative_path, vim.log.levels.ERROR)
		return nil
	end

	local lines = vim.split(content, "\n", { plain = true })
	local section_lines = {}
	for i = marker_info.M_start + 1, marker_info.M_end - 1 do
		table.insert(section_lines, lines[i])
	end

	local section_content = table.concat(section_lines, "\n")
	local target_key = marker_info.name or Utils.FlattenRelativePath(relative_path)
	local target_name = Parser.FindExecutableTargetName(section_content, base_name, target_key)
	if not target_name then
		Utils.Notify("Executable target not found for: " .. relative_path, vim.log.levels.ERROR)
		return nil
	end

	local updated_section_lines = Storage.update_section_links(section_lines, target_name, Parse.normalize_link_flags(new_links))
	local new_lines = {}
	for i = 1, marker_info.M_start do
		table.insert(new_lines, lines[i])
	end
	vim.list_extend(new_lines, updated_section_lines)
	for i = marker_info.M_end, #lines do
		table.insert(new_lines, lines[i])
	end

	return table.concat(new_lines, "\n")
end

function M.ManageInteractive(makefile_path, makefile_content)
	local picker = Ui.get_picker_or_warn("Picker is required for link management")
	if not picker then
		return false
	end

	local menu_items = {
		{ value = "add", display = "Add" },
		{ value = "remove", display = "Remove" },
		{ value = "edit", display = "Edit" },
		{ value = "list", display = "List/View" },
		{ value = "exit", display = "Exit" },
	}

	picker.pick_menu(menu_items, function(selection)
		if selection == "add" then
			Ui.manage_link_options_add(picker, makefile_path, makefile_content)
		elseif selection == "remove" then
			Ui.manage_link_options_remove(picker, makefile_path, makefile_content)
		elseif selection == "edit" then
			Ui.manage_link_options_edit(picker, makefile_path, makefile_content)
		elseif selection == "list" then
			Ui.manage_link_options_list(makefile_path, makefile_content)
		end
	end, { prompt_title = "Links: Menu" })

	return true
end

return M
