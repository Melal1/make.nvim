local Utils = require("make.shared.utils") -- shared utilities
local Parser = require("make.modules.parser") -- parser API
local Parse = require("make.modules.links.parse") -- links parsing helpers
local Storage = require("make.modules.links.storage") -- links storage helpers

local M = {} -- module table

local function get_picker_or_warn(message) -- return picker or warn
	local picker = require("make.pick") -- load picker module
	if not picker.available then -- picker not available
		Utils.Notify(message or "Picker is required for selection.", vim.log.levels.ERROR) -- warn user
		return nil
	end
	return picker -- return picker
end

local function build_link_entries(makefile_content) -- build selectable entries from links block
	local groups, individuals = Parser.ParseLinkOptions(makefile_content) -- parse link options
	local entries = {} -- picker entries
	local flags_by_value = {} -- map entry value -> flags
	local all_flags = {} -- flattened flags list

	for _, group in ipairs(groups) do -- add group entries
		local value = "group:" .. group.name -- entry value
		table.insert(entries, { value = value, display = "Group: " .. group.name }) -- add entry
		flags_by_value[value] = group.flags -- map flags
		vim.list_extend(all_flags, group.flags) -- accumulate flags
	end

	for _, flag in ipairs(individuals) do -- add individual entries
		local value = "link:" .. flag -- entry value
		table.insert(entries, { value = value, display = flag }) -- add entry
		flags_by_value[value] = { flag } -- map single flag
		table.insert(all_flags, flag) -- accumulate flag
	end

	if #entries > 0 then -- add all entry if any
		table.insert(entries, 1, { value = "__ALL__", display = "All" }) -- insert at top
		flags_by_value["__ALL__"] = all_flags -- map all flags
	end

	return entries, flags_by_value, Parse.normalize_link_flags(all_flags) -- return entries + flags
end

local function confirm_action(message) -- confirmation helper
	return vim.fn.confirm(message, "&Yes\n&No", 2) == 1 -- true on Yes
end

local function normalize_link_input(flag) -- normalize a single link flag
	flag = vim.trim(flag or "") -- trim input
	if flag == "" then -- empty input
		return nil
	end
	if flag:sub(1, 1) ~= "-" then -- ensure leading dash
		return "-" .. flag
	end
	return flag -- return normalized
end

local function parse_links_input(prompt) -- parse space-separated link flags
	local input = vim.fn.input(prompt) -- prompt user
	if not input or input:match("^%s*$") then -- empty input
		return {}
	end
	local flags = {} -- collected flags
	for flag in input:gmatch("%S+") do -- split on whitespace
		local normalized = normalize_link_input(flag) -- normalize flag
		if normalized then
			table.insert(flags, normalized) -- add flag
		end
	end
	return Parse.normalize_link_flags(flags) -- return normalized list
end

local function format_link_options(groups, individuals) -- format links for display
	local lines = {} -- output lines
	if #groups == 0 and #individuals == 0 then -- no links
		return { "No link options defined." }
	end

	if #groups > 0 then -- add group section
		table.insert(lines, "Groups:")
		for _, group in ipairs(groups) do -- list groups
			table.insert(lines, "- " .. group.name .. ": " .. table.concat(group.flags, " "))
		end
	end

	if #individuals > 0 then -- add individual section
		table.insert(lines, "Individuals:")
		for _, flag in ipairs(individuals) do -- list individuals
			table.insert(lines, "- " .. flag)
		end
	end

	return lines -- return formatted lines
end

local function build_preselected_link_values(entries, flags_by_value, existing_flags) -- determine preselected entries
	local existing_map = {} -- map of existing flags
	for _, flag in ipairs(Parse.normalize_link_flags(existing_flags)) do -- normalize existing
		existing_map[flag] = true -- mark as present
	end

	local preselected = {} -- list of preselected values
	for _, entry in ipairs(entries) do -- iterate entries
		if entry.value == "__ALL__" then -- handle all entry
			local all_present = true -- assume all present
			for _, flag in ipairs(flags_by_value["__ALL__"] or {}) do -- check all flags
				if not existing_map[flag] then
					all_present = false
					break
				end
			end
			if all_present then
				table.insert(preselected, entry.value) -- select ALL
			end
		else
			local flags = flags_by_value[entry.value] or {} -- flags for entry
			local all_present = #flags > 0 -- only true if any flags
			for _, flag in ipairs(flags) do -- ensure all flags present
				if not existing_map[flag] then
					all_present = false
					break
				end
			end
			if all_present then
				table.insert(preselected, entry.value) -- select entry
			end
		end
	end

	return preselected -- return preselected values
end

function M.select_links(existing_flags, makefile_content, callback, opts) -- select link flags with UI
	opts = opts or {} -- normalize options
	local entries, flags_by_value, all_flags = build_link_entries(makefile_content or "") -- build picker data
	if #entries == 0 then -- nothing to pick
		callback(existing_flags or {}) -- return existing
		return true
	end

	local picker = get_picker_or_warn("Picker is required for link selection") -- get picker
	if not picker then
		return false
	end

	local preselected_items = {} -- preselected entries
	if opts.preselect ~= false then -- default to preselect
		preselected_items = build_preselected_link_values(entries, flags_by_value, existing_flags or {})
	end

	picker.pick_checklist(entries, function(selected_values) -- open checklist
		selected_values = selected_values or {} -- normalize selection
		local use_all = false -- track all selection
		for _, value in ipairs(selected_values) do -- scan selection
			if value == "__ALL__" then
				use_all = true
				break
			end
		end

		local flags = {} -- final flags
		if use_all then
			flags = all_flags -- use all flags
		else
			for _, value in ipairs(selected_values) do -- collect flags per entry
				for _, flag in ipairs(flags_by_value[value] or {}) do
					table.insert(flags, flag)
				end
			end
		end

		callback(Parse.normalize_link_flags(flags)) -- return normalized selection
	end, { prompt_title = opts.prompt_title or "Select link flags", preselected_items = preselected_items }) -- picker opts
	return true -- success
end

function M.manage_link_options_add(picker, makefile_path, makefile_content) -- add group/individual links
	local menu_items = { -- add menu items
		{ value = "group", display = "Link Group" },
		{ value = "individual", display = "Individual Link(s)" },
	}

	picker.pick_menu(menu_items, function(selection) -- open menu
		if not selection or selection == "" then -- no selection
			return
		end

		local content, groups, individuals = Storage.load_link_options(makefile_path, makefile_content) -- load current links
		if selection == "group" then -- add group
			local group_name = vim.trim(vim.fn.input("Group name: ")) -- prompt group name
			if group_name == "" then
				Utils.Notify("Group name cannot be empty", vim.log.levels.WARN)
				return
			end
			for _, group in ipairs(groups) do -- check duplicates
				if group.name == group_name then
					Utils.Notify("Group already exists: " .. group_name, vim.log.levels.WARN)
					return
				end
			end

			local flags = parse_links_input("Enter links for group (space-separated): ") -- prompt flags
			if #flags == 0 then
				Utils.Notify("No links provided", vim.log.levels.WARN)
				return
			end

			if not confirm_action("Save group '" .. group_name .. "' with " .. #flags .. " link(s)?") then -- confirm
				return
			end

			table.insert(groups, { name = group_name, flags = flags }) -- add group
			local ok, err = Storage.save_link_options(makefile_path, content, groups, individuals) -- persist
			if not ok then
				Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
				return
			end
			Utils.Notify("Added group: " .. group_name, vim.log.levels.INFO) -- success
			return
		end

		local group_flags = {} -- map group flags
		for _, group in ipairs(groups) do -- collect grouped flags
			for _, flag in ipairs(group.flags) do
				group_flags[flag] = true
			end
		end

		local flags = parse_links_input("Enter individual links (space-separated): ") -- prompt individual flags
		if #flags == 0 then
			Utils.Notify("No links provided", vim.log.levels.WARN)
			return
		end

		local filtered = {} -- filtered flags
		for _, flag in ipairs(flags) do -- filter grouped flags
			if group_flags[flag] then
				Utils.Notify("Skipping grouped link: " .. flag, vim.log.levels.WARN)
			else
				table.insert(filtered, flag)
			end
		end
		filtered = Parse.normalize_link_flags(filtered) -- normalize filtered
		if #filtered == 0 then
			Utils.Notify("No new individual links to add", vim.log.levels.WARN)
			return
		end

		if not confirm_action("Save " .. #filtered .. " individual link(s)?") then -- confirm
			return
		end

		for _, flag in ipairs(filtered) do -- add flags
			table.insert(individuals, flag)
		end
		local ok, err = Storage.save_link_options(makefile_path, content, groups, individuals) -- persist
		if not ok then
			Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return
		end
		Utils.Notify("Added individual link(s)", vim.log.levels.INFO) -- success
	end, { prompt_title = "Links: Add" }) -- menu options
end

function M.manage_link_options_list(makefile_path, makefile_content) -- list link options
	local _, groups, individuals = Storage.load_link_options(makefile_path, makefile_content) -- load data
	local lines = format_link_options(groups, individuals) -- format for display
	Utils.Notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Links" }) -- show output
end

function M.manage_link_options_remove(picker, makefile_path, makefile_content) -- remove group or individual links
	local menu_items = { -- remove menu items
		{ value = "group", display = "Remove Group" },
		{ value = "individual", display = "Remove Individual Link(s)" },
	}

	picker.pick_menu(menu_items, function(selection) -- open menu
		if not selection or selection == "" then -- no selection
			return
		end

		local content, groups, individuals = Storage.load_link_options(makefile_path, makefile_content) -- load data
		if selection == "group" then -- remove group branch
			if #groups == 0 then
				Utils.Notify("No groups to remove", vim.log.levels.WARN)
				return
			end

			local group_entries = {} -- picker entries
			local group_map = {} -- name -> group
			for _, group in ipairs(groups) do -- build entries
				table.insert(group_entries, { value = group.name, display = group.name })
				group_map[group.name] = group
			end

			picker.pick_single(group_entries, function(selected_group) -- select group
				if not selected_group or selected_group == "" then
					return
				end

				local group = group_map[selected_group] -- lookup group
				if not group then
					return
				end

				local choice = vim.fn.confirm( -- choose remove mode
					"Remove entire group '" .. group.name .. "' or specific links?",
					"&Group\n&Links\n&Cancel",
					3
				)
				if choice == 1 then -- remove entire group
					if not confirm_action("Confirm removal of group '" .. group.name .. "'?") then
						return
					end
					local updated = {} -- remaining groups
					for _, entry in ipairs(groups) do
						if entry.name ~= group.name then
							table.insert(updated, entry)
						end
					end
					local ok, err = Storage.save_links_and_prune_targets( -- save and prune targets
						makefile_path,
						content,
						updated,
						individuals,
						group.flags
					)
					if not ok then
						Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
						return
					end
					Utils.Notify("Removed group: " .. group.name, vim.log.levels.INFO)
					return
				elseif choice ~= 2 then -- cancel
					return
				end

				if #group.flags == 0 then -- no links to remove
					Utils.Notify("Group has no links to remove", vim.log.levels.WARN)
					return
				end

				picker.pick_checklist(group.flags, function(selected_flags) -- select links to remove
					selected_flags = Parse.normalize_link_flags(selected_flags or {}) -- normalize selection
					if #selected_flags == 0 then
						return
					end
					if not confirm_action("Remove " .. #selected_flags .. " link(s) from '" .. group.name .. "'?") then
						return
					end

					local remaining = {} -- remaining flags
					local remove_map = {} -- removal lookup
					for _, flag in ipairs(selected_flags) do
						remove_map[flag] = true
					end
					for _, flag in ipairs(group.flags) do
						if not remove_map[flag] then
							table.insert(remaining, flag)
						end
					end
					group.flags = remaining -- update group flags

					local updated = {} -- rebuild groups list
					for _, entry in ipairs(groups) do
						if entry.name ~= group.name and #entry.flags > 0 then
							table.insert(updated, entry)
						elseif entry.name == group.name and #group.flags > 0 then
							table.insert(updated, group)
						end
					end
					if #group.flags == 0 then
						Utils.Notify("Group is now empty and will be removed", vim.log.levels.WARN)
					end
					local ok, err = Storage.save_links_and_prune_targets( -- save and prune
						makefile_path,
						content,
						updated,
						individuals,
						selected_flags
					)
					if not ok then
						Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
						return
					end
					Utils.Notify("Updated group: " .. group.name, vim.log.levels.INFO)
				end, { prompt_title = "Remove links from " .. group.name })
			end, { prompt_title = "Select group" })
			return
		end

		if #individuals == 0 then -- no individuals to remove
			Utils.Notify("No individual links to remove", vim.log.levels.WARN)
			return
		end

		picker.pick_checklist(individuals, function(selected_flags) -- select individual flags
			selected_flags = Parse.normalize_link_flags(selected_flags or {}) -- normalize selection
			if #selected_flags == 0 then
				return
			end
			if not confirm_action("Remove " .. #selected_flags .. " individual link(s)?") then
				return
			end

			local remove_map = {} -- removal lookup
			for _, flag in ipairs(selected_flags) do
				remove_map[flag] = true
			end
			local remaining = {} -- remaining individuals
			for _, flag in ipairs(individuals) do
				if not remove_map[flag] then
					table.insert(remaining, flag)
				end
			end
			local ok, err = Storage.save_links_and_prune_targets( -- save and prune
				makefile_path,
				content,
				groups,
				remaining,
				selected_flags
			)
			if not ok then
				Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
				return
			end
			Utils.Notify("Removed selected individual links", vim.log.levels.INFO)
		end, { prompt_title = "Remove individual links" })
	end, { prompt_title = "Links: Remove" })
end

function M.manage_link_options_edit(picker, makefile_path, makefile_content) -- edit group links
	local content, groups, individuals = Storage.load_link_options(makefile_path, makefile_content) -- load data
	if #groups == 0 then -- no groups to edit
		Utils.Notify("No groups to edit", vim.log.levels.WARN)
		return
	end

	local group_entries = {} -- picker entries
	local group_map = {} -- name -> group
	for _, group in ipairs(groups) do -- build entries
		table.insert(group_entries, { value = group.name, display = group.name })
		group_map[group.name] = group
	end

	picker.pick_single(group_entries, function(selected_group) -- select group to edit
		if not selected_group or selected_group == "" then
			return
		end

		local group = group_map[selected_group] -- lookup group
		if not group then
			return
		end

		local edit_actions = { -- edit menu
			{ value = "rename", display = "Rename group" },
			{ value = "add", display = "Add links to group" },
			{ value = "remove", display = "Remove links from group" },
			{ value = "replace", display = "Replace all links in group" },
		}

		picker.pick_menu(edit_actions, function(action) -- choose edit action
			if not action or action == "" then
				return
			end

			if action == "rename" then -- rename group
				local new_name = vim.trim(vim.fn.input("New group name: ")) -- prompt name
				if new_name == "" then
					Utils.Notify("Group name cannot be empty", vim.log.levels.WARN)
					return
				end
				for _, entry in ipairs(groups) do -- check duplicates
					if entry.name == new_name then
						Utils.Notify("Group already exists: " .. new_name, vim.log.levels.WARN)
						return
					end
				end
				if not confirm_action("Rename group '" .. group.name .. "' to '" .. new_name .. "'?") then
					return
				end
				group.name = new_name -- update name
				local ok, err = Storage.save_link_options(makefile_path, content, groups, individuals) -- persist
				if not ok then
					Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
					return
				end
				Utils.Notify("Renamed group to: " .. new_name, vim.log.levels.INFO) -- success
				return
			end

			if action == "add" then -- add links
				local flags = parse_links_input("Enter links to add (space-separated): ") -- prompt flags
				if #flags == 0 then
					Utils.Notify("No links provided", vim.log.levels.WARN)
					return
				end
				group.flags = Parse.merge_link_flags(group.flags, flags, "add") -- merge flags
				if not confirm_action("Add " .. #flags .. " link(s) to '" .. group.name .. "'?") then
					return
				end
				local ok, err = Storage.save_link_options(makefile_path, content, groups, individuals) -- persist
				if not ok then
					Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
					return
				end
				Utils.Notify("Updated group: " .. group.name, vim.log.levels.INFO) -- success
				return
			end

			if action == "remove" then -- remove links
				if #group.flags == 0 then
					Utils.Notify("Group has no links to remove", vim.log.levels.WARN)
					return
				end
				picker.pick_checklist(group.flags, function(selected_flags) -- select flags to remove
					selected_flags = Parse.normalize_link_flags(selected_flags or {}) -- normalize selection
					if #selected_flags == 0 then
						return
					end
					if not confirm_action("Remove " .. #selected_flags .. " link(s) from '" .. group.name .. "'?") then
						return
					end
					group.flags = Parse.merge_link_flags(group.flags, selected_flags, "remove") -- remove flags
					if #group.flags == 0 then -- group empty
						Utils.Notify("Group is now empty and will be removed", vim.log.levels.WARN)
						local updated = {} -- rebuild groups list
						for _, entry in ipairs(groups) do
							if entry.name ~= group.name then
								table.insert(updated, entry)
							end
						end
						local ok, err = Storage.save_links_and_prune_targets( -- save and prune
							makefile_path,
							content,
							updated,
							individuals,
							selected_flags
						)
						if not ok then
							Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
							return
						end
						return
					end
					local ok, err = Storage.save_links_and_prune_targets( -- save and prune
						makefile_path,
						content,
						groups,
						individuals,
						selected_flags
					)
					if not ok then
						Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
						return
					end
					Utils.Notify("Updated group: " .. group.name, vim.log.levels.INFO)
				end, { prompt_title = "Remove links from " .. group.name })
				return
			end

			if action == "replace" then -- replace all links
				local old_flags = vim.list_extend({}, group.flags or {}) -- snapshot old flags
				local flags = parse_links_input("Enter replacement links (space-separated): ") -- prompt new flags
				if #flags == 0 then
					Utils.Notify("No links provided", vim.log.levels.WARN)
					return
				end
				if not confirm_action("Replace all links in '" .. group.name .. "'?") then
					return
				end
				group.flags = Parse.normalize_link_flags(flags) -- set new flags
				local remove_map = {} -- map for new flags
				for _, flag in ipairs(group.flags) do
					remove_map[flag] = true
				end
				local removed_flags = {} -- flags removed by replace
				for _, flag in ipairs(old_flags) do
					if not remove_map[flag] then
						table.insert(removed_flags, flag)
					end
				end
				local ok, err = Storage.save_links_and_prune_targets( -- save and prune
					makefile_path,
					content,
					groups,
					individuals,
					removed_flags
				)
				if not ok then
					Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
					return
				end
				Utils.Notify("Replaced links in group: " .. group.name, vim.log.levels.INFO)
			end
		end, { prompt_title = "Edit group: " .. group.name }) -- menu options
	end, { prompt_title = "Select group to edit" }) -- picker options
end

function M.get_picker_or_warn(message) -- expose picker helper
	return get_picker_or_warn(message) -- delegate to local helper
end

return M -- export module
