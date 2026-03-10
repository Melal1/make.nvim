local M = {} -- module table

---@param flags string[]|nil
---@return string[]
function M.normalize_link_flags(flags) -- normalize and dedupe link flags
	local result = {} -- output list
	local seen = {} -- dedupe map
	for _, flag in ipairs(flags or {}) do -- iterate incoming flags
		if flag and flag ~= "" and not seen[flag] then -- keep non-empty uniques
			seen[flag] = true -- mark seen
			table.insert(result, flag) -- append to result
		end
	end
	return result -- return normalized list
end

---@param groups table[]|nil
---@param individuals string[]|nil
---@return string[]
function M.collect_all_link_flags(groups, individuals) -- collect all flags from groups + individuals
	local all = {} -- combined list
	for _, group in ipairs(groups or {}) do -- iterate groups
		vim.list_extend(all, group.flags or {}) -- append group flags
	end
	vim.list_extend(all, individuals or {}) -- append individual flags
	return M.normalize_link_flags(all) -- normalize and dedupe
end

---@param existing string[]|nil
---@param incoming string[]|nil
---@param action? string
---@return string[]
function M.merge_link_flags(existing, incoming, action) -- merge or remove link flags
	local current = M.normalize_link_flags(existing) -- normalize existing
	local updates = M.normalize_link_flags(incoming) -- normalize incoming

	if action == "remove" then -- remove mode
		local remove_map = {} -- flags to remove
		for _, flag in ipairs(updates) do -- build remove set
			remove_map[flag] = true
		end
		local result = {} -- filtered result
		for _, flag in ipairs(current) do -- keep flags not removed
			if not remove_map[flag] then
				table.insert(result, flag)
			end
		end
		return result -- return filtered list
	end

	local seen = {} -- dedupe map
	for _, flag in ipairs(current) do -- mark existing flags
		seen[flag] = true
	end
	for _, flag in ipairs(updates) do -- append new flags
		if not seen[flag] then
			table.insert(current, flag)
			seen[flag] = true
		end
	end
	return current -- return merged list
end

---@param content string|nil
---@return table[] groups, string[] individuals
function M.parse_links_block(content) -- parse #links_start/#links_end block
	local groups = {} -- list of groups
	local group_map = {} -- group lookup by name
	local individuals = {} -- list of individual flags
	local individual_map = {} -- dedupe map for individuals

	if not content or content == "" then -- empty content
		return groups, individuals
	end

	local in_block = false -- within links block
	for _, line in ipairs(vim.split(content, "\n", { plain = true })) do -- iterate lines
		if line:match("^%s*#%s*links_start") then -- start marker
			in_block = true -- enter block
			goto continue
		end
		if line:match("^%s*#%s*links_end") then -- end marker
			break -- stop parsing
		end
		if not in_block then -- ignore lines outside block
			goto continue
		end

		local group_name, rest = line:match("^%s*#%s*group:%s*(%S+)%s*(.*)$") -- parse group line
		if group_name then -- group line matched
			local flags = {} -- flags for this group line
			for flag in (rest or ""):gmatch("%S+") do -- split flags
				table.insert(flags, flag)
			end
			if #flags > 0 then -- only process non-empty group
				local group = group_map[group_name] -- lookup group
				if not group then -- create group if missing
					group = { name = group_name, flags = {} }
					group_map[group_name] = group
					table.insert(groups, group)
				end
				for _, flag in ipairs(flags) do -- append unique flags
					local seen = false
					for _, existing in ipairs(group.flags) do
						if existing == flag then
							seen = true
							break
						end
					end
					if not seen then
						table.insert(group.flags, flag)
					end
				end
			end
			goto continue
		end

		local link_rest = line:match("^%s*#%s*link:%s*(.*)$") -- parse individual link line
		if link_rest then
			for flag in link_rest:gmatch("%S+") do -- split flags
				if not individual_map[flag] then -- dedupe
					individual_map[flag] = true
					table.insert(individuals, flag)
				end
			end
		end

		::continue:: -- loop continue label
	end

	local group_flag_map = {} -- flags used by groups
	for _, group in ipairs(groups) do -- collect group flags
		for _, flag in ipairs(group.flags) do
			group_flag_map[flag] = true
		end
	end

	local filtered_individuals = {} -- individuals not in any group
	for _, flag in ipairs(individuals) do
		if not group_flag_map[flag] then
			table.insert(filtered_individuals, flag)
		end
	end

	return groups, filtered_individuals -- return parsed groups/individuals
end

return M -- export module
