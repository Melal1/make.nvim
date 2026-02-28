local M = {}

local Parser = require("make.modules.parser")
local Helpers = require("make.modules.helpers")
local Utils = require("make.shared.utils")

---@param Content string
---@return table[]
function M.GetObjectTargetsForPicker(Content)
	local sections = Helpers.GetSectionsByTypes(Content, { obj = true })
	---@type table[]
	local names = {}

	for _, entry in ipairs(sections) do
		local display_base = Utils.RelativePathNoExt(entry.path) .. ".o"
		for _, target in ipairs(entry.analysis.targets) do
			table.insert(names, {
				value = target.name,
				display = display_base,
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

---@param entry table|nil
---@return table|nil
function M.GetExecutableTarget(entry)
	if not entry then
		return nil
	end
	local targets = entry.analysis and entry.analysis.targets or entry.targets or entry
	if type(targets) ~= "table" then
		return nil
	end
	local target_key = entry.targetKey or (entry.path and Utils.FlattenRelativePath(entry.path)) or nil
	for _, target in ipairs(targets) do
		local kind = target.kind or Parser.TargetKind(target.name, target_key)
		if kind == "exe" then
			return target
		end
	end
	return nil
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
