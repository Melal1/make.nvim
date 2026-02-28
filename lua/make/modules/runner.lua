local M = {}

local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")
local Generator = require("make.modules.generator")
local Links = require("make.modules.links")
local Helpers = require("make.modules.helpers")
local Targets = require("make.modules.targets")

---@param MakefilePath string
---@param RelativePath string
---@param Content string
---@return boolean
function M.BuildTarget(MakefilePath, RelativePath, Content)
	local TargetsTable = Targets.GetExeTables(Content)
	if not TargetsTable or #TargetsTable == 0 then
		Utils.Notify("No executable targets found in Makefile", vim.log.levels.WARN)
		return false
	end

	local Entry = Helpers.FindSectionByPath(TargetsTable, RelativePath)
	if not Entry or not Entry.analysis.targets[2] then
		Utils.Notify("No matching target found", vim.log.levels.WARN)
		return false
	end
	local BinName = vim.fn.fnamemodify(Entry.analysis.targets[2].name, ":t")

	local dir = vim.fn.fnamemodify(MakefilePath, ":h")
	local MakefileVars = Parser.ParseVariables(Content)
	local base_dir = MakefileVars.BUILD_DIR or "build"
	local build_mode = MakefileVars.BUILD_MODE or "debug"
	local build_out = Utils.GetBuildOutputDir(MakefileVars)
	local target_name = Entry.analysis.targets[2].name
	local resolved = target_name
	if resolved:find("%$%(BUILD_MODE%)") then
		resolved = resolved:gsub("%$%(BUILD_DIR%)/%$%(BUILD_MODE%)", build_out)
		resolved = resolved:gsub("%$%(BUILD_MODE%)", build_mode)
		resolved = resolved:gsub("%$%(BUILD_DIR%)", base_dir)
	else
		resolved = resolved:gsub("%$%(BUILD_DIR%)", base_dir)
	end
	resolved = resolved:gsub("^%./", "")

	local cmd = string.format("cd %s && make %s", dir, resolved)

	vim.system({ "sh", "-c", cmd }, { text = true }, function(obj)
		vim.defer_fn(function()
			vim.schedule(function()
				if obj.code == 0 then
					Utils.Notify("Build succeeded: " .. BinName, vim.log.levels.INFO, {
						title = "Make Build",
					})
					return
				end

				local err_path = string.format("/tmp/%s.err", BinName)
				if Utils.WriteFile(err_path, obj.stderr, false) then
					Utils.Notify(
						string.format("Build failed. Error saved to: %s", err_path),
						vim.log.levels.HINT,
						{ title = "Make Build" }
					)
				else
					Utils.Notify("Build failed (could not write error file).", vim.log.levels.ERROR, {
						title = "Make Build",
					})
				end
			end)
		end, 100)
	end)

	return true
end

---@param MakefilePath string
---@param RelativePath string
---@param Content string
---@return boolean
function M.RunTargetInSpilt(MakefilePath, RelativePath, Content)
	local ok, term = pcall(require, "make.terminal")
	if not ok then
		Utils.Notify("Terminal helper is unavailable.", vim.log.levels.WARN)
		return false
	end

	local TargetsTable = Targets.GetExeTables(Content)
	if not TargetsTable or #TargetsTable == 0 then
		Utils.Notify("No executable targets found in Makefile", vim.log.levels.WARN)
		return false
	end

	local Entry = Helpers.FindSectionByPath(TargetsTable, RelativePath)
	if not Entry then
		Utils.Notify("No matching run target for " .. RelativePath, vim.log.levels.WARN)
		return false
	end
	local RunTargetName = "run" .. Entry.baseName

	local MakefileDir = vim.fn.fnamemodify(MakefilePath, ":h")
	local cmd = "cd " .. vim.fn.shellescape(MakefileDir) .. " && make " .. RunTargetName
	term.SingleShot(cmd)

	return true
end

---@param makefile_content string
---@return boolean
function M.PickAndRunTargets(makefile_content)
	local targets = Targets.GetAllTargetsForDisplay(makefile_content)
	if not targets or #targets == 0 then
		Utils.Notify("No targets found in Makefile", vim.log.levels.WARN)
		return false
	end

	local picker = Helpers.GetPickerOrWarn("Picker is required for selection.")
	if not picker then
		return false
	end

	table.sort(targets, function(a, b)
		return a.display < b.display
	end)

	local display_labels = {}
	local name_by_label = {}
	for _, target in ipairs(targets) do
		table.insert(display_labels, target.display)
		name_by_label[target.display] = target.name
	end

	picker.pick_checklist(display_labels, function(selected_labels)
		if not selected_labels or #selected_labels == 0 then
			Utils.Notify("No targets selected", vim.log.levels.WARN)
			return
		end

		local selected_targets = {}
		for _, label in ipairs(selected_labels) do
			local target_name = name_by_label[label]
			if target_name then
				table.insert(selected_targets, target_name)
			end
		end

		local makefile_dir = vim.fn.getcwd()
		local cmd = "cd " .. vim.fn.shellescape(makefile_dir) .. " && make " .. table.concat(selected_targets, " ")

		vim.cmd("terminal " .. cmd)
		Utils.Notify("Running targets: " .. table.concat(selected_targets, ", "), vim.log.levels.INFO)
	end, {
		prompt_title = "Select Makefile target(s)",
	})
	return true
end

---@param Config table|nil
---@param on_run fun()|nil
---@return boolean
function M.FastRun(Config, on_run)
	Config = Config or {}
	local makefile_path = vim.fn.expand("%:p:h") .. "/Makefile"
	local makefile_dir = vim.fn.fnamemodify(makefile_path, ":h")
	Parser.SetCacheRoot(makefile_dir, makefile_path)
	local file_path = vim.fn.expand("%:p")
	local relative_path = Helpers.GetRelativeOrWarn(file_path, makefile_dir)
	if not relative_path then
		return false
	end

	local makefile_content = nil
	if vim.loop.fs_stat(makefile_path) then
		makefile_content, _ = Utils.ReadFile(makefile_path)
		if makefile_content and makefile_content ~= "" and Parser.TargetExists(makefile_content, relative_path) then
			if on_run then
				on_run()
			end
			return true
		end
	end

	local ensured = Generator.EnsureMakefileVariables(makefile_path, makefile_content, Config.MakefileVars)
	if ensured == nil then
		return false
	end

	local basename = vim.fn.fnamemodify(file_path, ":t:r")
	local ok = Links.SelectLinks({}, makefile_content, function(selected_links)
		local lines = Generator.ExecutableTarget(
			basename,
			relative_path,
			{},
			Config.MakefileVars,
			makefile_dir,
			selected_links
		)
		local AppendSuccess, WriteErr = Utils.AppendToFile(makefile_path, lines)
		if not AppendSuccess then
			Utils.Notify("\nFailed to write to Makefile: " .. WriteErr, vim.log.levels.ERROR)
			return
		end
		if on_run then
			on_run()
		end
	end, { prompt_title = "Select link flags" })
	if ok == false then
		return false
	end
	return true
end

return M
