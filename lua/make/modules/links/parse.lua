local M = {}

---@param flags string[]|nil
---@return string[]
function M.normalize_link_flags(flags)
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

---@param groups table[]|nil
---@param individuals string[]|nil
---@return string[]
function M.collect_all_link_flags(groups, individuals)
	local all = {}
	for _, group in ipairs(groups or {}) do
		vim.list_extend(all, group.flags or {})
	end
	vim.list_extend(all, individuals or {})
	return M.normalize_link_flags(all)
end

---@param existing string[]|nil
---@param incoming string[]|nil
---@param action? string
---@return string[]
function M.merge_link_flags(existing, incoming, action)
	local current = M.normalize_link_flags(existing)
	local updates = M.normalize_link_flags(incoming)

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

---@param content string|nil
---@return table[] groups, string[] individuals
function M.parse_links_block(content)
	local groups = {}
	local group_map = {}
	local individuals = {}
	local individual_map = {}

	if not content or content == "" then
		return groups, individuals
	end

	local in_block = false
	for _, line in ipairs(vim.split(content, "\n", { plain = true })) do
		if line:match("^%s*#%s*links_start") then
			in_block = true
			goto continue
		end
		if line:match("^%s*#%s*links_end") then
			break
		end
		if not in_block then
			goto continue
		end

		local group_name, rest = line:match("^%s*#%s*group:%s*(%S+)%s*(.*)$")
		if group_name then
			local flags = {}
			for flag in (rest or ""):gmatch("%S+") do
				table.insert(flags, flag)
			end
			if #flags > 0 then
				local group = group_map[group_name]
				if not group then
					group = { name = group_name, flags = {} }
					group_map[group_name] = group
					table.insert(groups, group)
				end
				for _, flag in ipairs(flags) do
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

		local link_rest = line:match("^%s*#%s*link:%s*(.*)$")
		if link_rest then
			for flag in link_rest:gmatch("%S+") do
				if not individual_map[flag] then
					individual_map[flag] = true
					table.insert(individuals, flag)
				end
			end
		end

		::continue::
	end

	local group_flag_map = {}
	for _, group in ipairs(groups) do
		for _, flag in ipairs(group.flags) do
			group_flag_map[flag] = true
		end
	end

	local filtered_individuals = {}
	for _, flag in ipairs(individuals) do
		if not group_flag_map[flag] then
			table.insert(filtered_individuals, flag)
		end
	end

	return groups, filtered_individuals
end

return M
