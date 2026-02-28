local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")
local Parse = require("make.modules.links.parse")
local uv = vim.uv or vim.loop

local M = {}

local function filter_removed_flags(removed_flags, groups, individuals)
	local remaining = {}
	for _, flag in ipairs(Parse.collect_all_link_flags(groups, individuals)) do
		remaining[flag] = true
	end

	local out = {}
	for _, flag in ipairs(Parse.normalize_link_flags(removed_flags)) do
		if not remaining[flag] then
			table.insert(out, flag)
		end
	end
	return out
end

local function remove_link_flags_from_targets(content, removed_flags)
	local remove_map = {}
	for _, flag in ipairs(Parse.normalize_link_flags(removed_flags)) do
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

local function build_links_block(groups, individuals)
	local lines = { "# links_start" }

	for _, group in ipairs(groups or {}) do
		local name = group.name and vim.trim(group.name) or ""
		local flags = Parse.normalize_link_flags(group.flags or {})
		if name ~= "" and #flags > 0 then
			table.insert(lines, "# group: " .. name .. " " .. table.concat(flags, " "))
		end
	end

	for _, flag in ipairs(Parse.normalize_link_flags(individuals or {})) do
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

function M.save_links_and_prune_targets(makefile_path, content, groups, individuals, removed_flags)
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

function M.update_section_links(section_lines, target_name, links)
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

function M.load_link_options(makefile_path, fallback_content)
	local content = fallback_content
	if makefile_path and uv.fs_stat(makefile_path) then
		content, _ = Utils.ReadFile(makefile_path)
	end
	content = content or ""
	local groups, individuals = Parser.ParseLinkOptions(content)
	return content, groups, individuals
end

function M.save_link_options(makefile_path, content, groups, individuals)
	local new_content = apply_links_block(content or "", groups or {}, individuals or {})
	local ok, err = Utils.WriteFile(makefile_path, new_content)
	if not ok then
		return false, err
	end
	return true, new_content
end

return M
