local M = {}

local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")

function M.GetPickerOrWarn(message)
	local picker = require("make.pick")
	if not picker.available then
		Utils.Notify(message or "Picker is required for selection.", vim.log.levels.ERROR)
		return nil
	end
	return picker
end

function M.GetRelativeOrWarn(file_path, root_path)
	local relative_path, ok = Utils.GetRelativePath(file_path, root_path)
	if not ok then
		Utils.Notify(relative_path)
		return nil
	end
	return relative_path
end

function M.GetSectionsByTypes(content, types)
	local result = {}
	for _, section in ipairs(Parser.AnalyzeAllSections(content)) do
		if types[section.analysis.type] then
			table.insert(result, section)
		end
	end
	return result
end

function M.FindSectionByPath(sections, relative_path)
	for _, section in ipairs(sections) do
		if section.path == relative_path then
			return section
		end
	end
	return nil
end

function M.TargetTypeLabel(target_name)
	if target_name:match("%.o$") then
		return "(obj)"
	elseif target_name:match("^run") then
		return "(run)"
	end
	return "(exe)"
end

return M
