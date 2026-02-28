local M = {}

local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")

local function get_picker_or_warn(message)
	local picker = require("make.pick")
	if not picker.available then
		Utils.Notify(message or "Picker is required for selection.", vim.log.levels.ERROR)
		return nil
	end
	return picker
end

local function normalize_link_flags(flags)
	local result = {}
	local seen = {}
	for _, flag in ipairs(flags or {}) do
		if flag and flag ~= "" and not seen[flag] then
			seen[flag] = true
			table.insert(result, flag)
		end
	end
	return result
end

local function collect_all_link_flags(groups, individuals)
	local all = {}
	for _, group in ipairs(groups or {}) do
		vim.list_extend(all, group.flags or {})
	end
	vim.list_extend(all, individuals or {})
	return normalize_link_flags(all)
end

local function filter_removed_flags(removed_flags, groups, individuals)
	local remaining = {}
	for _, flag in ipairs(collect_all_link_flags(groups, individuals)) do
		remaining[flag] = true
	end

	local out = {}
	for _, flag in ipairs(normalize_link_flags(removed_flags)) do
		if not remaining[flag] then
			table.insert(out, flag)
		end
	end
	return out
end

local function remove_link_flags_from_targets(content, removed_flags)
	local remove_map = {}
	for _, flag in ipairs(normalize_link_flags(removed_flags)) do
		remove_map[flag] = true
	end
	if not next(remove_map) then
		return content or "", 0
	end

	local pattern = "^(%s*[^:]+%s*:%s*LINKS%s*[%+:%?]?=)%s*(.*)$"
	local lines = vim.split(content or "", "\n", { plain = true })
	local new_lines = {}
	local changed = 0

	for _, line in ipairs(lines) do
		local prefix, flags = line:match(pattern)
		if not prefix then
			table.insert(new_lines, line)
		else
			local kept = {}
			local removed = false
			for flag in (flags or ""):gmatch("%S+") do
				if remove_map[flag] then
					removed = true
				else
					table.insert(kept, flag)
				end
			end
			if not removed then
				table.insert(new_lines, line)
			elseif #kept == 0 then
				changed = changed + 1
			else
				local new_line = prefix .. " " .. table.concat(kept, " ")
				if new_line ~= line then
					changed = changed + 1
				end
				table.insert(new_lines, new_line)
			end
		end
	end

	return table.concat(new_lines, "\n"), changed
end

local function merge_link_flags(existing, incoming, action)
	local current = normalize_link_flags(existing)
	local updates = normalize_link_flags(incoming)

	if action == "remove" then
		local remove_map = {}
		for _, flag in ipairs(updates) do
			remove_map[flag] = true
		end
		local result = {}
		for _, flag in ipairs(current) do
			if not remove_map[flag] then
				table.insert(result, flag)
			end
		end
		return result
	end

	local seen = {}
	for _, flag in ipairs(current) do
		seen[flag] = true
	end
	for _, flag in ipairs(updates) do
		if not seen[flag] then
			table.insert(current, flag)
			seen[flag] = true
		end
	end
	return current
end

local function build_links_block(groups, individuals)
	local lines = { "# links_start" }

	for _, group in ipairs(groups or {}) do
		local name = group.name and vim.trim(group.name) or ""
		local flags = normalize_link_flags(group.flags or {})
		if name ~= "" and #flags > 0 then
			table.insert(lines, "# group: " .. name .. " " .. table.concat(flags, " "))
		end
	end

	for _, flag in ipairs(normalize_link_flags(individuals or {})) do
		table.insert(lines, "# link: " .. flag)
	end

	table.insert(lines, "# links_end")
	return lines
end

local function apply_links_block(content, groups, individuals)
	local lines = vim.split(content or "", "\n", { plain = true })
	local start_idx, end_idx = nil, nil

	for i, line in ipairs(lines) do
		if not start_idx and line:match("^%s*#%s*links_start") then
			start_idx = i
		elseif start_idx and line:match("^%s*#%s*links_end") then
			end_idx = i
			break
		end
	end

	local has_links = #groups > 0 or #individuals > 0
	if not has_links then
		if not start_idx then
			return content or ""
		end
		local cleaned = {}
		for i = 1, start_idx - 1 do
			table.insert(cleaned, lines[i])
		end
		for i = (end_idx or start_idx) + 1, #lines do
			table.insert(cleaned, lines[i])
		end
		return table.concat(cleaned, "\n")
	end

	local block_lines = build_links_block(groups, individuals)
	local new_lines = {}
	if start_idx then
		for i = 1, start_idx - 1 do
			table.insert(new_lines, lines[i])
		end
		vim.list_extend(new_lines, block_lines)
		for i = (end_idx or start_idx) + 1, #lines do
			table.insert(new_lines, lines[i])
		end
	else
		vim.list_extend(new_lines, block_lines)
		if #lines > 0 then
			table.insert(new_lines, "")
			vim.list_extend(new_lines, lines)
		end
	end

	return table.concat(new_lines, "\n")
end

local function save_links_and_prune_targets(makefile_path, content, groups, individuals, removed_flags)
	local new_content = apply_links_block(content or "", groups or {}, individuals or {})
	local filtered_removed = filter_removed_flags(removed_flags or {}, groups or {}, individuals or {})
	if #filtered_removed > 0 then
		new_content = remove_link_flags_from_targets(new_content, filtered_removed)
	end
	local ok, err = Utils.WriteFile(makefile_path, new_content)
	if not ok then
		return false, err
	end
	return true, new_content
end

local function build_link_entries(makefile_content)
	local groups, individuals = Parser.ParseLinkOptions(makefile_content)
	local entries = {}
	local flags_by_value = {}
	local all_flags = {}

	for _, group in ipairs(groups) do
		local value = "group:" .. group.name
		table.insert(entries, { value = value, display = "Group: " .. group.name })
		flags_by_value[value] = group.flags
		vim.list_extend(all_flags, group.flags)
	end

	for _, flag in ipairs(individuals) do
		local value = "link:" .. flag
		table.insert(entries, { value = value, display = flag })
		flags_by_value[value] = { flag }
		table.insert(all_flags, flag)
	end

	if #entries > 0 then
		table.insert(entries, 1, { value = "__ALL__", display = "All" })
		flags_by_value["__ALL__"] = all_flags
	end

	return entries, flags_by_value, normalize_link_flags(all_flags)
end

local function confirm_action(message)
	return vim.fn.confirm(message, "&Yes\n&No", 2) == 1
end

local function normalize_link_input(flag)
	flag = vim.trim(flag or "")
	if flag == "" then
		return nil
	end
	if flag:sub(1, 1) ~= "-" then
		return "-" .. flag
	end
	return flag
end

local function parse_links_input(prompt)
	local input = vim.fn.input(prompt)
	if not input or input:match("^%s*$") then
		return {}
	end
	local flags = {}
	for flag in input:gmatch("%S+") do
		local normalized = normalize_link_input(flag)
		if normalized then
			table.insert(flags, normalized)
		end
	end
	return normalize_link_flags(flags)
end

local function format_link_options(groups, individuals)
	local lines = {}
	table.insert(lines, "Groups:")
	if #groups == 0 then
		table.insert(lines, "  (none)")
	else
		for _, group in ipairs(groups) do
			table.insert(lines, "  " .. group.name)
			for _, flag in ipairs(group.flags) do
				table.insert(lines, "    - " .. flag)
			end
		end
	end
	table.insert(lines, "")
	table.insert(lines, "Individuals:")
	if #individuals == 0 then
		table.insert(lines, "  (none)")
	else
		for _, flag in ipairs(individuals) do
			table.insert(lines, "  - " .. flag)
		end
	end
	return lines
end

local function build_preselected_link_values(entries, flags_by_value, existing_flags)
	local existing_map = {}
	for _, flag in ipairs(existing_flags or {}) do
		existing_map[flag] = true
	end

	local preselected = {}
	for _, entry in ipairs(entries) do
		if entry.value ~= "__ALL__" then
			local flags = flags_by_value[entry.value] or {}
			local all_present = #flags > 0
			for _, flag in ipairs(flags) do
				if not existing_map[flag] then
					all_present = false
					break
				end
			end
			if all_present then
				table.insert(preselected, entry.value)
			end
		end
	end

	return preselected
end

local function update_section_links(section_lines, target_name, links)
	local link_line_index = nil
	local target_line_index = nil
	local target_pattern = "^%s*" .. Utils.EscapePattern(target_name) .. "%s*:"
	local links_pattern = "^%s*" .. Utils.EscapePattern(target_name) .. "%s*:%s*LINKS%s*[%+:%?]?="

	for i, line in ipairs(section_lines) do
		local trimmed = line:match("^%s*(.-)%s*$")
		if not link_line_index and trimmed:match(links_pattern) then
			link_line_index = i
		elseif not target_line_index and trimmed:match(target_pattern) then
			target_line_index = i
		end
	end

	local new_lines = vim.list_extend({}, section_lines)
	if #links == 0 then
		if link_line_index then
			table.remove(new_lines, link_line_index)
		end
		return new_lines
	end

	local new_line = target_name .. ": LINKS += " .. table.concat(links, " ")
	if link_line_index then
		new_lines[link_line_index] = new_line
	else
		local insert_at = target_line_index or (#new_lines + 1)
		table.insert(new_lines, insert_at, new_line)
	end

	return new_lines
end

local function manage_link_options_add(picker, makefile_path, makefile_content)
	local menu_items = {
		{ value = "group", display = "Link Group" },
		{ value = "individual", display = "Individual Link(s)" },
	}

	picker.pick_menu(menu_items, function(selection)
		if not selection or selection == "" then
			return
		end

		local content, groups, individuals = M.LoadLinkOptions(makefile_path, makefile_content)
		if selection == "group" then
			local group_name = vim.trim(vim.fn.input("Group name: "))
			if group_name == "" then
				Utils.Notify("Group name cannot be empty", vim.log.levels.WARN)
				return
			end
			for _, group in ipairs(groups) do
				if group.name == group_name then
					Utils.Notify("Group already exists: " .. group_name, vim.log.levels.WARN)
					return
				end
			end

			local flags = parse_links_input("Enter links for group (space-separated): ")
			if #flags == 0 then
				Utils.Notify("No links provided", vim.log.levels.WARN)
				return
			end

			if not confirm_action("Save group '" .. group_name .. "' with " .. #flags .. " link(s)?") then
				return
			end

			table.insert(groups, { name = group_name, flags = flags })
			local ok, err = M.SaveLinkOptions(makefile_path, content, groups, individuals)
			if not ok then
				Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
				return
			end
			Utils.Notify("Added group: " .. group_name, vim.log.levels.INFO)
			return
		end

		local group_flags = {}
		for _, group in ipairs(groups) do
			for _, flag in ipairs(group.flags) do
				group_flags[flag] = true
			end
		end

		local flags = parse_links_input("Enter individual links (space-separated): ")
		if #flags == 0 then
			Utils.Notify("No links provided", vim.log.levels.WARN)
			return
		end

		local filtered = {}
		for _, flag in ipairs(flags) do
			if group_flags[flag] then
				Utils.Notify("Skipping grouped link: " .. flag, vim.log.levels.WARN)
			else
				table.insert(filtered, flag)
			end
		end
		filtered = normalize_link_flags(filtered)
		if #filtered == 0 then
			Utils.Notify("No new individual links to add", vim.log.levels.WARN)
			return
		end

		if not confirm_action("Save " .. #filtered .. " individual link(s)?") then
			return
		end

		for _, flag in ipairs(filtered) do
			table.insert(individuals, flag)
		end
		local ok, err = M.SaveLinkOptions(makefile_path, content, groups, individuals)
		if not ok then
			Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return
		end
		Utils.Notify("Added individual link(s)", vim.log.levels.INFO)
	end, { prompt_title = "Links: Add" })
end

local function manage_link_options_list(makefile_path, makefile_content)
	local _, groups, individuals = M.LoadLinkOptions(makefile_path, makefile_content)
	local lines = format_link_options(groups, individuals)
	Utils.Notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Links" })
end

local function manage_link_options_remove(picker, makefile_path, makefile_content)
	local menu_items = {
		{ value = "group", display = "Remove Group" },
		{ value = "individual", display = "Remove Individual Link(s)" },
	}

	picker.pick_menu(menu_items, function(selection)
		if not selection or selection == "" then
			return
		end

		local content, groups, individuals = M.LoadLinkOptions(makefile_path, makefile_content)
		if selection == "group" then
			if #groups == 0 then
				Utils.Notify("No groups to remove", vim.log.levels.WARN)
				return
			end

			local group_entries = {}
			local group_map = {}
			for _, group in ipairs(groups) do
				table.insert(group_entries, { value = group.name, display = group.name })
				group_map[group.name] = group
			end

			picker.pick_single(group_entries, function(selected_group)
				if not selected_group or selected_group == "" then
					return
				end

				local group = group_map[selected_group]
				if not group then
					return
				end

				local choice = vim.fn.confirm(
					"Remove entire group '" .. group.name .. "' or specific links?",
					"&Group\n&Links\n&Cancel",
					3
				)
				if choice == 1 then
					if not confirm_action("Confirm removal of group '" .. group.name .. "'?") then
						return
					end
					local updated = {}
					for _, entry in ipairs(groups) do
						if entry.name ~= group.name then
							table.insert(updated, entry)
						end
					end
					local ok, err = save_links_and_prune_targets(makefile_path, content, updated, individuals, group.flags)
					if not ok then
						Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
						return
					end
					Utils.Notify("Removed group: " .. group.name, vim.log.levels.INFO)
					return
				elseif choice ~= 2 then
					return
				end

				if #group.flags == 0 then
					Utils.Notify("Group has no links to remove", vim.log.levels.WARN)
					return
				end

				picker.pick_checklist(group.flags, function(selected_flags)
					selected_flags = normalize_link_flags(selected_flags or {})
					if #selected_flags == 0 then
						return
					end
					if not confirm_action("Remove " .. #selected_flags .. " link(s) from '" .. group.name .. "'?") then
						return
					end

					local remaining = {}
					local remove_map = {}
					for _, flag in ipairs(selected_flags) do
						remove_map[flag] = true
					end
					for _, flag in ipairs(group.flags) do
						if not remove_map[flag] then
							table.insert(remaining, flag)
						end
					end
					group.flags = remaining

					local updated = {}
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
					local ok, err = save_links_and_prune_targets(makefile_path, content, updated, individuals, selected_flags)
					if not ok then
						Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
						return
					end
					Utils.Notify("Updated group: " .. group.name, vim.log.levels.INFO)
				end, { prompt_title = "Remove links from " .. group.name })
			end, { prompt_title = "Select group" })
			return
		end

		if #individuals == 0 then
			Utils.Notify("No individual links to remove", vim.log.levels.WARN)
			return
		end

		picker.pick_checklist(individuals, function(selected_flags)
			selected_flags = normalize_link_flags(selected_flags or {})
			if #selected_flags == 0 then
				return
			end
			if not confirm_action("Remove " .. #selected_flags .. " individual link(s)?") then
				return
			end

			local remove_map = {}
			for _, flag in ipairs(selected_flags) do
				remove_map[flag] = true
			end
			local remaining = {}
			for _, flag in ipairs(individuals) do
				if not remove_map[flag] then
					table.insert(remaining, flag)
				end
			end
			local ok, err = save_links_and_prune_targets(makefile_path, content, groups, remaining, selected_flags)
			if not ok then
				Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
				return
			end
			Utils.Notify("Removed selected individual links", vim.log.levels.INFO)
		end, { prompt_title = "Remove individual links" })
	end, { prompt_title = "Links: Remove" })
end

local function manage_link_options_edit(picker, makefile_path, makefile_content)
	local content, groups, individuals = M.LoadLinkOptions(makefile_path, makefile_content)
	if #groups == 0 then
		Utils.Notify("No groups to edit", vim.log.levels.WARN)
		return
	end

	local group_entries = {}
	local group_map = {}
	for _, group in ipairs(groups) do
		table.insert(group_entries, { value = group.name, display = group.name })
		group_map[group.name] = group
	end

	picker.pick_single(group_entries, function(selected_group)
		if not selected_group or selected_group == "" then
			return
		end

		local group = group_map[selected_group]
		if not group then
			return
		end

		local edit_actions = {
			{ value = "rename", display = "Rename group" },
			{ value = "add", display = "Add links to group" },
			{ value = "remove", display = "Remove links from group" },
			{ value = "replace", display = "Replace all links in group" },
		}

		picker.pick_menu(edit_actions, function(action)
			if not action or action == "" then
				return
			end

			if action == "rename" then
				local new_name = vim.trim(vim.fn.input("New group name: "))
				if new_name == "" then
					Utils.Notify("Group name cannot be empty", vim.log.levels.WARN)
					return
				end
				for _, entry in ipairs(groups) do
					if entry.name == new_name then
						Utils.Notify("Group already exists: " .. new_name, vim.log.levels.WARN)
						return
					end
				end
				if not confirm_action("Rename group '" .. group.name .. "' to '" .. new_name .. "'?") then
					return
				end
				group.name = new_name
				local ok, err = M.SaveLinkOptions(makefile_path, content, groups, individuals)
				if not ok then
					Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
					return
				end
				Utils.Notify("Renamed group to: " .. new_name, vim.log.levels.INFO)
				return
			end

			if action == "add" then
				local flags = parse_links_input("Enter links to add (space-separated): ")
				if #flags == 0 then
					Utils.Notify("No links provided", vim.log.levels.WARN)
					return
				end
				group.flags = merge_link_flags(group.flags, flags, "add")
				if not confirm_action("Add " .. #flags .. " link(s) to '" .. group.name .. "'?") then
					return
				end
				local ok, err = M.SaveLinkOptions(makefile_path, content, groups, individuals)
				if not ok then
					Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
					return
				end
				Utils.Notify("Updated group: " .. group.name, vim.log.levels.INFO)
				return
			end

			if action == "remove" then
				if #group.flags == 0 then
					Utils.Notify("Group has no links to remove", vim.log.levels.WARN)
					return
				end
				picker.pick_checklist(group.flags, function(selected_flags)
					selected_flags = normalize_link_flags(selected_flags or {})
					if #selected_flags == 0 then
						return
					end
					if not confirm_action("Remove " .. #selected_flags .. " link(s) from '" .. group.name .. "'?") then
						return
					end
					group.flags = merge_link_flags(group.flags, selected_flags, "remove")
					if #group.flags == 0 then
						Utils.Notify("Group is now empty and will be removed", vim.log.levels.WARN)
						local updated = {}
						for _, entry in ipairs(groups) do
							if entry.name ~= group.name then
								table.insert(updated, entry)
							end
						end
						local ok, err = save_links_and_prune_targets(
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
					local ok, err =
						save_links_and_prune_targets(makefile_path, content, groups, individuals, selected_flags)
					if not ok then
						Utils.Notify("Failed to save links: " .. (err or "unknown error"), vim.log.levels.ERROR)
						return
					end
					Utils.Notify("Updated group: " .. group.name, vim.log.levels.INFO)
				end, { prompt_title = "Remove links from " .. group.name })
				return
			end

			if action == "replace" then
				local old_flags = vim.list_extend({}, group.flags or {})
				local flags = parse_links_input("Enter replacement links (space-separated): ")
				if #flags == 0 then
					Utils.Notify("No links provided", vim.log.levels.WARN)
					return
				end
				if not confirm_action("Replace all links in '" .. group.name .. "'?") then
					return
				end
				group.flags = normalize_link_flags(flags)
				local remove_map = {}
				for _, flag in ipairs(group.flags) do
					remove_map[flag] = true
				end
				local removed_flags = {}
				for _, flag in ipairs(old_flags) do
					if not remove_map[flag] then
						table.insert(removed_flags, flag)
					end
				end
				local ok, err = save_links_and_prune_targets(
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
		end, { prompt_title = "Edit group: " .. group.name })
	end, { prompt_title = "Select group to edit" })
end

function M.ParseLinksBlock(content)
	return Parser.ParseLinkOptions(content)
end

function M.HasLinkOptions(content)
	local groups, individuals = Parser.ParseLinkOptions(content or "")
	return #groups > 0 or #individuals > 0
end

function M.LoadLinkOptions(makefile_path, fallback_content)
	local content = fallback_content
	if makefile_path and vim.loop.fs_stat(makefile_path) then
		content, _ = Utils.ReadFile(makefile_path)
	end
	content = content or ""
	local groups, individuals = Parser.ParseLinkOptions(content)
	return content, groups, individuals
end

function M.SaveLinkOptions(makefile_path, content, groups, individuals)
	local new_content = apply_links_block(content or "", groups or {}, individuals or {})
	local ok, err = Utils.WriteFile(makefile_path, new_content)
	if not ok then
		return false, err
	end
	return true, new_content
end

function M.SelectLinks(existing_flags, makefile_content, callback, opts)
	opts = opts or {}
	local entries, flags_by_value, all_flags = build_link_entries(makefile_content or "")
	if #entries == 0 then
		callback(existing_flags or {})
		return true
	end

	local picker = get_picker_or_warn("Picker is required for link selection")
	if not picker then
		return false
	end

	local preselected_items = {}
	if opts.preselect ~= false then
		preselected_items = build_preselected_link_values(entries, flags_by_value, existing_flags or {})
	end

	picker.pick_checklist(entries, function(selected_values)
		selected_values = selected_values or {}
		local use_all = false
		for _, value in ipairs(selected_values) do
			if value == "__ALL__" then
				use_all = true
				break
			end
		end

		local flags = {}
		if use_all then
			flags = all_flags
		else
			for _, value in ipairs(selected_values) do
				for _, flag in ipairs(flags_by_value[value] or {}) do
					table.insert(flags, flag)
				end
			end
		end

		callback(normalize_link_flags(flags))
	end, { prompt_title = opts.prompt_title or "Select link flags", preselected_items = preselected_items })
	return true
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

	local target_name = Parser.FindExecutableTargetName(section_content, base_name)
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
	local target_name = Parser.FindExecutableTargetName(section_content, base_name)
	if not target_name then
		Utils.Notify("Executable target not found for: " .. relative_path, vim.log.levels.ERROR)
		return nil
	end

	local updated_section_lines = update_section_links(section_lines, target_name, normalize_link_flags(new_links))
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
	local picker = get_picker_or_warn("Picker is required for link management")
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
			manage_link_options_add(picker, makefile_path, makefile_content)
		elseif selection == "remove" then
			manage_link_options_remove(picker, makefile_path, makefile_content)
		elseif selection == "edit" then
			manage_link_options_edit(picker, makefile_path, makefile_content)
		elseif selection == "list" then
			manage_link_options_list(makefile_path, makefile_content)
		end
	end, { prompt_title = "Links: Menu" })

	return true
end

return M
