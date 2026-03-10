local Utils = require("make.shared.utils") -- shared helpers

local M = {} -- module table

---@param deps table
---@return table
function M.build(deps) -- build report helpers with dependencies
	local Analysis = deps.analysis -- analysis module
	local Markers = deps.markers -- marker module

	local function PrintAnalysisSummary(Content) -- print a summary of analysis
		local allSections = Analysis.AnalyzeAllSections(Content) -- analyze all sections
		local lines = Markers.normalize_lines(Content) -- normalize content lines

		vim.notify("Makefile Section Analysis:") -- header line
		vim.notify("=" .. string.rep("=", 50)) -- underline separator

		for _, section in ipairs(allSections) do -- iterate sections
			local analysis = section.analysis -- section analysis payload
			local sectionContent = Markers.slice_lines(lines, section.startLine, section.endLine, false) -- extract section text
			local exeTargetName = Analysis.FindExecutableTargetName(sectionContent, section.baseName, section.targetKey) -- find exe target
			local exeLinks = {} -- default links list
			if exeTargetName then -- collect links if target found
				exeLinks = Analysis.GetLinksForTarget(sectionContent, exeTargetName)
			end

			vim.notify(string.format("Path: %s", section.path)) -- print file path
			vim.notify(string.format("Base Name: %s", section.baseName or "N/A")) -- print base name
			vim.notify(string.format("Type: %s", analysis.type)) -- print inferred type
			if analysis.hasExecutable or analysis.type == "full" or analysis.type == "executable" then -- show exe info when relevant
				local default_key = Utils.FlattenRelativePath(section.path) -- compute default key
				local target_key = section.targetKey or default_key -- resolve target key
				local label = target_key -- start label text
				if target_key ~= "" then -- annotate label if non-empty
					if default_key ~= "" and target_key ~= default_key then
						label = label .. " (override)" -- indicate override
					elseif default_key ~= "" then
						label = label .. " (default)" -- indicate default
					end
				end
				vim.notify(string.format("Executable Name: %s", label ~= "" and label or "N/A")) -- print exe name
			end

			if analysis.annotatedType then -- show annotation if present
				vim.notify(string.format("Annotated Type: %s", analysis.annotatedType))
			end

			vim.notify(string.format("Has Object: %s", analysis.hasObj and "Yes" or "No")) -- object flag
			vim.notify(string.format("Has Executable: %s", analysis.hasExecutable and "Yes" or "No")) -- exe flag
			vim.notify(string.format("Has Run: %s", analysis.hasRun and "Yes" or "No")) -- run flag

			if #analysis.targets > 0 then -- print targets list
				vim.notify("Targets:") -- targets header
				for _, target in ipairs(analysis.targets) do -- iterate targets
					local kind = target.kind -- target kind
					if not kind or kind == "other" then -- infer kind if missing
						kind = Analysis.TargetKind(
							target.name,
							section.targetKey,
							{ allow_run_prefix = true, allow_run_prefix_any = true, allow_fallback_exe = true }
						)
					end
					vim.notify(string.format("  - %s (%s)", target.name, kind)) -- print target line
					if #target.dependencies > 0 then -- print dependencies if any
						vim.notify(string.format("    Dependencies: %s", table.concat(target.dependencies, ", ")))
					end
					if #target.recipe > 0 then -- print recipe lines if any
						vim.notify("    Recipe:")
						for _, recipeLine in ipairs(target.recipe) do -- iterate recipe lines
							vim.notify(string.format("      %s", recipeLine))
						end
					end
					if exeTargetName and target.name == exeTargetName then -- show link flags for exe
						if #exeLinks > 0 then
							vim.notify(string.format("    Links: %s", table.concat(exeLinks, " ")))
						else
							vim.notify("    Links: (none)")
						end
					end
				end
			end
			vim.notify(string.rep("-", 50)) -- section separator
		end
	end

	return { -- exported report API
		PrintAnalysisSummary = PrintAnalysisSummary,
	}
end

return M -- export module
