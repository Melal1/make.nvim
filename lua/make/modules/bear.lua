local Parser = require("make.modules.parser")
local Utils = require("make.shared.utils")

---@class Bear
local M = {}
---@param cmd string commands to run
---@param success_msg? string text to show when success
---@param Callback function|nil
local function run_bear_async(cmd, success_msg, Callback)
	vim.system({ "sh", "-c", cmd }, { text = true }, function(obj)
		vim.defer_fn(function()
			vim.schedule(function()
				if obj.code == 0 then
					Utils.Notify(success_msg or "Bear finished successfully", vim.log.levels.INFO, {
						title = "Make + Bear",
					})
					if Callback then
						Callback()
					end
					return
				end

				local err_path = "/tmp/Bearerr"
				if Utils.WriteFile(err_path, obj.stderr, false) then
					Utils.Notify(
						"Bear failed. Error saved to: " .. err_path,
						vim.log.levels.HINT,
						{ title = "Make + Bear" }
					)
				else
					Utils.Notify(
						"Bear failed, but could not save /tmp/Bearerr",
						vim.log.levels.HINT,
						{ title = "Make + Bear" }
					)
				end
			end)
		end, 100)
	end)
end

local function resolve_target_name(target, vars)
	local base_dir = vars.BUILD_DIR or "build"
	local build_mode = vars.BUILD_MODE or "debug"
	local build_out = Utils.GetBuildOutputDir(vars)
	local resolved = target
	if resolved:find("%$%(BUILD_MODE%)") then
		resolved = resolved:gsub("%$%(BUILD_DIR%)/%$%(BUILD_MODE%)", build_out)
		resolved = resolved:gsub("%$%(BUILD_MODE%)", build_mode)
		resolved = resolved:gsub("%$%(BUILD_DIR%)", base_dir)
	else
		resolved = resolved:gsub("%$%(BUILD_DIR%)", base_dir)
	end
	return resolved:match("^%s*(.-)%s*$")
end

---Run bear for the current file
---@param Content string Makefile content
---@param Rootdir string Root directory of the project
---@param RelativePath string|nil
---@param Callback function|nil
---@return boolean success True if cmd sent ( Regarding cmd errors)
function M.CurrentFile(Content, Rootdir, RelativePath, Callback)
	local Vars = Parser.ParseVariables(Content)
	RelativePath = RelativePath or Utils.GetRelativePath(vim.fn.expand("%"), Rootdir)

	if not RelativePath then
		return false
	end

	local Targets = Parser.AnalyzeAllSections(Content)

	for _, Ent in ipairs(Targets) do
		if (Ent.analysis.type == "full" or Ent.analysis.type == "obj") and Ent.path == RelativePath then
			for _, Target in ipairs(Ent.analysis.targets) do
				if Target.name:match("^%$%(BUILD_DIR%).+%.o$") then
					local ModifiedName = resolve_target_name(Target.name, Vars)
					local cmd = string.format(
						"cd %s && bear --append -- make -B %s",
						vim.fn.shellescape(Rootdir),
						vim.fn.shellescape(ModifiedName)
					)

					run_bear_async(cmd, "Bear finished", Callback)

					return true
				end
			end
		end
	end

	return false
end

---Run bear for specific target lines
---@param Lines string[] Target lines
---@param Rootdir string Root directory of the project
---@param BuildDir string Build output directory
---@return boolean success True if cmd sent ( Regarding cmd errors)
function M.Target(Lines, Rootdir, BuildDir)
	for _, Line in ipairs(Lines) do
		-- Match object file targets
		local targetName = Line:match("^([^:]+):")
		if targetName and targetName:match("^%$%(BUILD_DIR%).+%.o$") then
			local ModifiedName = targetName
				:gsub("%$%(BUILD_DIR%)/%$%(BUILD_MODE%)", BuildDir)
				:gsub("%$%(BUILD_DIR%)", BuildDir)
				:match("^%s*(.-)%s*$")
			local cmd = string.format(
				"cd %s && bear --append -- make -B %s",
				vim.fn.shellescape(Rootdir),
				vim.fn.shellescape(ModifiedName)
			)

			run_bear_async(cmd, "Bear finished")

			return true
		end
	end

	return false
end

---@param Content string Makefile content
---@param Rootdir string Root directory of the project
---@return boolean success True if cmd sent ( Regarding cmd errors)
function M.SelectTarget(Content, Rootdir)
	local Picker = require("make.pick")
	if not Picker.available then
		Utils.Notify("Picker is unavailable.", vim.log.levels.WARN)
		return false
	end

	local Vars = Parser.ParseVariables(Content)
	local TableOfAllTargets = Parser.AnalyzeAllSections(Content)
	local map = {}
	local PickerEnts = {}
	for _, Ent in ipairs(TableOfAllTargets) do
		if Ent.analysis.type == "full" or Ent.analysis.type == "obj" then
			table.insert(PickerEnts, {
				value = Ent.startLine,
				display = string.format("%s ( %s )", Ent.baseName, Ent.analysis.type),
				preview_text = Parser.ReadContentBetweenLines(Content, Ent.startLine, Ent.endLine, true),
			})
			map[Ent.startLine] = Ent
		end
	end

	Picker.pick_multi_with_preview(PickerEnts, function(selected)
		local BearTargets = {}
		for _, LineNum in ipairs(selected) do
			for _, Target in ipairs(map[LineNum].analysis.targets) do
				if Target.name:match("^%$%(BUILD_DIR%).+%.o$") then
					table.insert(BearTargets, resolve_target_name(Target.name, Vars))
					break
				end
			end
		end

		local cmd = string.format(
			"cd %s && bear --append -- make -B %s",
			vim.fn.shellescape(Rootdir),
			table.concat(BearTargets, " ")
		)
		run_bear_async(cmd, "Bear finished")
	end, { prompt_title = "Select targets for Bear", previewer = Picker.text_per_entry_previewer("make") })
	return true
end

return M
