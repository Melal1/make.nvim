local Utils = require("make.shared.utils")

local M = {}

---@param deps table
---@return table
function M.build(deps)
	local Analysis = deps.analysis
	local Markers = deps.markers

	local function PrintAnalysisSummary(Content)
		local allSections = Analysis.AnalyzeAllSections(Content)
		local lines = Markers.normalize_lines(Content)

		vim.notify("Makefile Section Analysis:")
		vim.notify("=" .. string.rep("=", 50))

		for _, section in ipairs(allSections) do
			local analysis = section.analysis
			local sectionContent = Markers.slice_lines(lines, section.startLine, section.endLine, false)
			local exeTargetName = Analysis.FindExecutableTargetName(sectionContent, section.baseName, section.targetKey)
			local exeLinks = {}
			if exeTargetName then
				exeLinks = Analysis.GetLinksForTarget(sectionContent, exeTargetName)
			end

			vim.notify(string.format("Path: %s", section.path))
			vim.notify(string.format("Base Name: %s", section.baseName or "N/A"))
			vim.notify(string.format("Type: %s", analysis.type))
			if analysis.hasExecutable or analysis.type == "full" or analysis.type == "executable" then
				local default_key = Utils.FlattenRelativePath(section.path)
				local target_key = section.targetKey or default_key
				local label = target_key
				if target_key ~= "" then
					if default_key ~= "" and target_key ~= default_key then
						label = label .. " (override)"
					elseif default_key ~= "" then
						label = label .. " (default)"
					end
				end
				vim.notify(string.format("Executable Name: %s", label ~= "" and label or "N/A"))
			end

			if analysis.annotatedType then
				vim.notify(string.format("Annotated Type: %s", analysis.annotatedType))
			end

			vim.notify(string.format("Has Object: %s", analysis.hasObj and "Yes" or "No"))
			vim.notify(string.format("Has Executable: %s", analysis.hasExecutable and "Yes" or "No"))
			vim.notify(string.format("Has Run: %s", analysis.hasRun and "Yes" or "No"))

			if #analysis.targets > 0 then
				vim.notify("Targets:")
				for _, target in ipairs(analysis.targets) do
					local kind = target.kind
					if not kind or kind == "other" then
						kind = Analysis.TargetKind(
							target.name,
							section.targetKey,
							{ allow_run_prefix = true, allow_run_prefix_any = true, allow_fallback_exe = true }
						)
					end
					vim.notify(string.format("  - %s (%s)", target.name, kind))
					if #target.dependencies > 0 then
						vim.notify(string.format("    Dependencies: %s", table.concat(target.dependencies, ", ")))
					end
					if #target.recipe > 0 then
						vim.notify("    Recipe:")
						for _, recipeLine in ipairs(target.recipe) do
							vim.notify(string.format("      %s", recipeLine))
						end
					end
					if exeTargetName and target.name == exeTargetName then
						if #exeLinks > 0 then
							vim.notify(string.format("    Links: %s", table.concat(exeLinks, " ")))
						else
							vim.notify("    Links: (none)")
						end
					end
				end
			end
			vim.notify(string.rep("-", 50))
		end
	end

	return {
		PrintAnalysisSummary = PrintAnalysisSummary,
	}
end

return M
