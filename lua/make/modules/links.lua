local M = {} -- module table

local Utils = require("make.shared.utils") -- shared utilities
local Parser = require("make.modules.parser") -- parser API
local Parse = require("make.modules.links.parse") -- links parsing helpers
local Storage = require("make.modules.links.storage") -- persistence helpers
local Ui = require("make.modules.links.ui") -- UI helpers

function M.ParseLinksBlock(content) -- parse links block in Makefile content
	return Parser.ParseLinkOptions(content) -- delegate to parser cache-aware method
end

function M.HasLinkOptions(content) -- check if any link options exist
	local groups, individuals = Parser.ParseLinkOptions(content or "") -- parse groups/individuals
	return #groups > 0 or #individuals > 0 -- true if any exist
end

function M.LoadLinkOptions(makefile_path, fallback_content) -- load links from file or fallback content
	return Storage.load_link_options(makefile_path, fallback_content) -- delegate to storage layer
end

function M.SaveLinkOptions(makefile_path, content, groups, individuals) -- persist links to file
	return Storage.save_link_options(makefile_path, content, groups, individuals) -- delegate to storage layer
end

function M.SelectLinks(existing_flags, makefile_content, callback, opts) -- open UI to select links
	return Ui.select_links(existing_flags, makefile_content, callback, opts) -- delegate to UI layer
end

function M.GetExistingLinks(content, relative_path, base_name) -- read existing link flags for a target
	local cached = Parser.GetCachedTargetLinks(content, relative_path) -- try cache first
	if cached then -- cache hit
		return cached -- return cached flags
	end
	local section_content = Parser.ReadContentBetweenMarkers(content, relative_path) -- extract target section
	if type(section_content) == "table" then -- normalize table to string
		section_content = table.concat(section_content, "\n")
	end
	if not section_content or section_content == "" then -- no content
		return {}
	end

	local marker_info = Parser.FindMarker(content, relative_path, true, false) -- find marker info
	local target_key = (marker_info and marker_info.name) or Utils.FlattenRelativePath(relative_path) -- resolve target key
	local target_name = Parser.FindExecutableTargetName(section_content, base_name, target_key) -- find exe target
	if not target_name then -- no executable target
		return {}
	end

	return Parser.GetLinksForTarget(section_content, target_name) -- parse links line
end

function M.UpdateLinksForEntry(content, relative_path, base_name, new_links) -- update links inside a section
	local marker_info = Parser.FindMarker(content, relative_path, true, true) -- locate marker bounds
	if not marker_info.M_start or not marker_info.M_end then -- markers missing
		Utils.Notify("Markers not found for: " .. relative_path, vim.log.levels.ERROR) -- warn user
		return nil
	end

	local lines = vim.split(content, "\n", { plain = true }) -- split file into lines
	local section_lines = {} -- collect section lines
	for i = marker_info.M_start + 1, marker_info.M_end - 1 do -- slice between markers
		table.insert(section_lines, lines[i]) -- append line
	end

	local section_content = table.concat(section_lines, "\n") -- join section lines
	local target_key = marker_info.name or Utils.FlattenRelativePath(relative_path) -- resolve target key
	local target_name = Parser.FindExecutableTargetName(section_content, base_name, target_key) -- find exe target
	if not target_name then -- no target found
		Utils.Notify("Executable target not found for: " .. relative_path, vim.log.levels.ERROR) -- warn user
		return nil
	end

	local updated_section_lines = Storage.update_section_links(section_lines, target_name, Parse.normalize_link_flags(new_links)) -- update links line
	local new_lines = {} -- new file lines
	for i = 1, marker_info.M_start do -- copy pre-section
		table.insert(new_lines, lines[i])
	end
	vim.list_extend(new_lines, updated_section_lines) -- insert updated section
	for i = marker_info.M_end, #lines do -- copy post-section
		table.insert(new_lines, lines[i])
	end

	return table.concat(new_lines, "\n") -- return updated file content
end

function M.ManageInteractive(makefile_path, makefile_content) -- entrypoint for interactive link management
	local picker = Ui.get_picker_or_warn("Picker is required for link management") -- get picker
	if not picker then -- no picker available
		return false
	end

	local menu_items = { -- menu choices
		{ value = "add", display = "Add" },
		{ value = "remove", display = "Remove" },
		{ value = "edit", display = "Edit" },
		{ value = "list", display = "List/View" },
		{ value = "exit", display = "Exit" },
	}

	picker.pick_menu(menu_items, function(selection) -- show menu
		if selection == "add" then -- add links
			Ui.manage_link_options_add(picker, makefile_path, makefile_content)
		elseif selection == "remove" then -- remove links
			Ui.manage_link_options_remove(picker, makefile_path, makefile_content)
		elseif selection == "edit" then -- edit links
			Ui.manage_link_options_edit(picker, makefile_path, makefile_content)
		elseif selection == "list" then -- list links
			Ui.manage_link_options_list(makefile_path, makefile_content)
		end
	end, { prompt_title = "Links: Menu" }) -- picker options

	return true -- menu opened
end

return M -- export module
