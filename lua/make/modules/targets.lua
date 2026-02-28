local M = {}

local Parser = require("make.modules.parser")
local Helpers = require("make.modules.helpers")

---@param Content string
---@return table[]
function M.GetObjectTargetsForPicker(Content)
	local sections = Helpers.GetSectionsByTypes(Content, { obj = true })
	---@type table[]
	local names = {}

	for _, entry in ipairs(sections) do
		for _, target in ipairs(entry.analysis.targets) do
			table.insert(names, {
				value = target.name,
				display = entry.baseName .. ".o",
			})
		end
	end
	return names
end

---@param Content string
---@return table[]
function M.GetExeTables(Content)
	return Helpers.GetSectionsByTypes(Content, { full = true, executable = true })
end

---@param Content string
---@return table[]
function M.GetAllTargetsForDisplay(Content)
	local allSections = Parser.AnalyzeAllSections(Content)
	---@type table[]
	local targets = {}

	for _, section in ipairs(allSections) do
		for _, target in ipairs(section.analysis.targets) do
			local targetType = Helpers.TargetTypeLabel(target.name)

			table.insert(targets, {
				name = target.name,
				display = target.name .. " " .. targetType,
				type = targetType,
			})
		end
	end

	return targets
end

return M
