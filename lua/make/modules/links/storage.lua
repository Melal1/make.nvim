local Utils = require("make.shared.utils") -- shared helpers
local Parser = require("make.modules.parser") -- parser API
local Parse = require("make.modules.links.parse") -- link parsing helpers
local uv = vim.uv or vim.loop -- libuv for fs stat

local M = {} -- module table

local function filter_removed_flags(removed_flags, groups, individuals) -- filter out flags still in use
	local remaining = {} -- flags still present after updates
	for _, flag in ipairs(Parse.collect_all_link_flags(groups, individuals)) do -- collect current flags
		remaining[flag] = true -- mark as remaining
	end

	local out = {} -- filtered removed list
	for _, flag in ipairs(Parse.normalize_link_flags(removed_flags)) do -- normalize removed list
		if not remaining[flag] then -- keep only truly removed
			table.insert(out, flag)
		end
	end
	return out -- return filtered list
end

local function remove_link_flags_from_targets(content, removed_flags) -- remove flags from target LINKS lines
	local remove_map = {} -- lookup of flags to remove
	for _, flag in ipairs(Parse.normalize_link_flags(removed_flags)) do -- normalize removed list
		remove_map[flag] = true -- mark flag for removal
	end
	if not next(remove_map) then -- nothing to remove
		return content or "", 0
	end

	local pattern = "^(%s*[^:]+%s*:%s*LINKS%s*[%+:%?]?=)%s*(.*)$" -- match LINKS assignment
	local lines = vim.split(content or "", "\n", { plain = true }) -- split into lines
	local new_lines = {} -- output lines
	local changed = 0 -- count changes

	for _, line in ipairs(lines) do -- iterate lines
		local prefix, flags = line:match(pattern) -- parse LINKS line
		if not prefix then -- non-LINKS line
			table.insert(new_lines, line)
		else
			local kept = {} -- flags to keep
			local removed = false -- track removal
			for flag in (flags or ""):gmatch("%S+") do -- split flags
				if remove_map[flag] then -- remove flag
					removed = true
				else
					table.insert(kept, flag)
				end
			end
			if not removed then -- no removal on this line
				table.insert(new_lines, line)
			elseif #kept == 0 then -- remove entire line
				changed = changed + 1
			else -- update line with kept flags
				local new_line = prefix .. " " .. table.concat(kept, " ")
				if new_line ~= line then
					changed = changed + 1
				end
				table.insert(new_lines, new_line)
			end
		end
	end

	return table.concat(new_lines, "\n"), changed -- return updated content and change count
end

local function build_links_block(groups, individuals) -- build #links_start block text
	local lines = { "# links_start" } -- start marker

	for _, group in ipairs(groups or {}) do -- append groups
		local name = group.name and vim.trim(group.name) or "" -- normalized group name
		local flags = Parse.normalize_link_flags(group.flags or {}) -- normalize flags
		if name ~= "" and #flags > 0 then -- only add valid groups
			table.insert(lines, "# group: " .. name .. " " .. table.concat(flags, " "))
		end
	end

	for _, flag in ipairs(Parse.normalize_link_flags(individuals or {})) do -- append individual flags
		table.insert(lines, "# link: " .. flag)
	end

	table.insert(lines, "# links_end") -- end marker
	return lines -- return block lines
end

local function apply_links_block(content, groups, individuals) -- insert/replace links block in content
	local lines = vim.split(content or "", "\n", { plain = true }) -- split content
	local start_idx, end_idx = nil, nil -- marker indices

	for i, line in ipairs(lines) do -- scan for markers
		if not start_idx and line:match("^%s*#%s*links_start") then
			start_idx = i
		elseif start_idx and line:match("^%s*#%s*links_end") then
			end_idx = i
			break
		end
	end

	local has_links = #groups > 0 or #individuals > 0 -- determine if block needed
	if not has_links then -- remove block if empty
		if not start_idx then -- no block present
			return content or ""
		end
		local cleaned = {} -- content without block
		for i = 1, start_idx - 1 do -- keep before block
			table.insert(cleaned, lines[i])
		end
		for i = (end_idx or start_idx) + 1, #lines do -- keep after block
			table.insert(cleaned, lines[i])
		end
		return table.concat(cleaned, "\n")
	end

	local block_lines = build_links_block(groups, individuals) -- build new block
	local new_lines = {} -- output content
	if start_idx then -- replace existing block
		for i = 1, start_idx - 1 do -- keep before block
			table.insert(new_lines, lines[i])
		end
		vim.list_extend(new_lines, block_lines) -- insert new block
		for i = (end_idx or start_idx) + 1, #lines do -- keep after block
			table.insert(new_lines, lines[i])
		end
	else -- insert new block at top
		vim.list_extend(new_lines, block_lines)
		if #lines > 0 then -- keep original content after a blank line
			table.insert(new_lines, "")
			vim.list_extend(new_lines, lines)
		end
	end

	return table.concat(new_lines, "\n") -- return updated content
end

function M.save_links_and_prune_targets(makefile_path, content, groups, individuals, removed_flags) -- save block and remove unused flags
	local new_content = apply_links_block(content or "", groups or {}, individuals or {}) -- update block
	local filtered_removed = filter_removed_flags(removed_flags or {}, groups or {}, individuals or {}) -- filter removed list
	if #filtered_removed > 0 then -- remove flags from targets
		new_content = remove_link_flags_from_targets(new_content, filtered_removed)
	end
	local ok, err = Utils.WriteFile(makefile_path, new_content) -- write to disk
	if not ok then -- write failed
		return false, err
	end
	return true, new_content -- return updated content
end

function M.update_section_links(section_lines, target_name, links) -- update links line inside a section
	local link_line_index = nil -- existing LINKS line index
	local target_line_index = nil -- target rule line index
	local target_pattern = "^%s*" .. Utils.EscapePattern(target_name) .. "%s*:" -- match target rule
	local links_pattern = "^%s*" .. Utils.EscapePattern(target_name) .. "%s*:%s*LINKS%s*[%+:%?]?=" -- match LINKS line

	for i, line in ipairs(section_lines) do -- scan section lines
		local trimmed = line:match("^%s*(.-)%s*$") -- trim whitespace
		if not link_line_index and trimmed:match(links_pattern) then -- find LINKS line
			link_line_index = i
		elseif not target_line_index and trimmed:match(target_pattern) then -- find target rule
			target_line_index = i
		end
	end

	local new_lines = vim.list_extend({}, section_lines) -- copy section lines
	if #links == 0 then -- remove links line when empty
		if link_line_index then
			table.remove(new_lines, link_line_index)
		end
		return new_lines
	end

	local new_line = target_name .. ": LINKS += " .. table.concat(links, " ") -- build LINKS line
	if link_line_index then -- replace existing line
		new_lines[link_line_index] = new_line
	else -- insert after target rule
		local insert_at = target_line_index or (#new_lines + 1)
		table.insert(new_lines, insert_at, new_line)
	end

	return new_lines -- return updated section
end

function M.load_link_options(makefile_path, fallback_content) -- load links block from file or fallback
	local content = fallback_content -- start with fallback
	if makefile_path and uv.fs_stat(makefile_path) then -- prefer file if exists
		content, _ = Utils.ReadFile(makefile_path)
	end
	content = content or "" -- ensure string
	local groups, individuals = Parser.ParseLinkOptions(content) -- parse links
	return content, groups, individuals -- return parsed data
end

function M.save_link_options(makefile_path, content, groups, individuals) -- save links block to file
	local new_content = apply_links_block(content or "", groups or {}, individuals or {}) -- update block
	local ok, err = Utils.WriteFile(makefile_path, new_content) -- write to disk
	if not ok then -- write failed
		return false, err
	end
	return true, new_content -- return updated content
end

return M -- export module
