local M = {}

local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")
local Generator = require("make.modules.generator")
local Links = require("make.modules.links")
local Helpers = require("make.modules.helpers")
local Targets = require("make.modules.targets")
local uv = vim.uv or vim.loop

local function strip_ansi(text)
	if not text or text == "" then
		return text or ""
	end
	-- Strip ANSI escape sequences (colors, cursor controls)
	return text:gsub("\27%[[%d;]*[%a]", "")
end

local function set_quickfix_from_output(output, title)
	if not output or output == "" then
		return false
	end
	local raw_lines = vim.split(output, "\n", { plain = true, trimempty = true })
	local lines = {}
	for _, line in ipairs(raw_lines) do
		local cleaned = strip_ansi(line):gsub("\r$", "")
		if cleaned ~= "" then
			table.insert(lines, cleaned)
		end
	end
	if #lines == 0 then
		return false
	end
	vim.fn.setqflist({}, " ", { title = title or "Make Build", lines = lines })
	return true
end

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
	local exe_target = Targets.GetExecutableTarget(Entry)
	if not Entry or not exe_target then
		Utils.Notify("No matching target found", vim.log.levels.WARN)
		return false
	end
	local BinName = vim.fn.fnamemodify(exe_target.name, ":t")

	local dir = vim.fn.fnamemodify(MakefilePath, ":h")
	local MakefileVars = Parser.ParseVariables(Content)
	local target_name = exe_target.name
	local resolved = Utils.ResolveTargetName(target_name, MakefileVars)
	if not resolved or resolved == "" then
		Utils.Notify("Resolved target name is empty", vim.log.levels.WARN)
		return false
	end
	resolved = resolved:gsub("^%./", "")

	vim.system({ "make", resolved }, { text = true, cwd = dir }, function(obj)
		vim.defer_fn(function()
			vim.schedule(function()
				if obj.code == 0 then
					Utils.Notify("Build succeeded: " .. BinName, vim.log.levels.INFO, {
						title = "Make Build",
					})
					return
				end

				local err_output = obj.stderr or ""
				if err_output == "" then
					err_output = obj.stdout or ""
				end

				local err_path = string.format("/tmp/%s.err", BinName)
				if Utils.WriteFile(err_path, err_output, false) then
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

				if set_quickfix_from_output(err_output, "Make Build: " .. BinName) then
					Utils.Notify("Quickfix list updated. Run :copen to view.", vim.log.levels.INFO, {
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
	local RunTargetName = nil
	if Entry.analysis and Entry.analysis.targets then
		for _, target in ipairs(Entry.analysis.targets) do
			if target.name and Parser.TargetKind(target.name, Entry.targetKey, { allow_run_prefix = true }) == "run" then
				RunTargetName = target.name
				break
			end
		end
	end
	if not RunTargetName then
		local suffix = Entry.targetKey or Entry.baseName or ""
		RunTargetName = "run_" .. suffix
	end

	local MakefileDir = vim.fn.fnamemodify(MakefilePath, ":h")
	local stdout_lines = {}
	local stderr_lines = {}

	local function collect_lines(bucket, data)
		if not data then
			return
		end
		for _, line in ipairs(data) do
			if line ~= "" then
				table.insert(bucket, line)
			end
		end
	end

	term.SingleShotJob({ "make", RunTargetName }, {
		cwd = MakefileDir,
		on_stdout = function(_, data)
			collect_lines(stdout_lines, data)
		end,
		on_stderr = function(_, data)
			collect_lines(stderr_lines, data)
		end,
		on_exit = function(_, code)
			if code == 0 then
				return
			end
			local err_output = ""
			if #stderr_lines > 0 then
				err_output = table.concat(stderr_lines, "\n")
			elseif #stdout_lines > 0 then
				err_output = table.concat(stdout_lines, "\n")
			end
			if set_quickfix_from_output(err_output, "Make Run: " .. RunTargetName) then
				Utils.Notify("Quickfix list updated. Run :copen to view.", vim.log.levels.INFO, {
					title = "Make Run",
				})
			end
		end,
	})

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

	local vars = Parser.ParseVariables(makefile_content or "")

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
				local resolved_name = Utils.ResolveTargetName(target_name, vars)
				if resolved_name and resolved_name ~= "" then
					table.insert(selected_targets, resolved_name)
				end
			end
		end
		if #selected_targets == 0 then
			Utils.Notify("No valid targets selected", vim.log.levels.WARN)
			return
		end

		local makefile_dir = vim.fn.getcwd()
		local args = { "make" }
		vim.list_extend(args, selected_targets)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"Running: " .. table.concat(args, " "),
		})
		Utils.Notify("Running targets: " .. table.concat(selected_targets, ", "), vim.log.levels.INFO)
		vim.system(args, { text = true, cwd = makefile_dir }, function(obj)
			vim.schedule(function()
				local lines = {}
				local stdout = obj.stdout or ""
				local stderr = obj.stderr or ""
				if stdout ~= "" then
					vim.list_extend(lines, vim.split(stdout, "\n", { plain = true }))
				end
				if stderr ~= "" then
					if #lines > 0 then
						table.insert(lines, "")
					end
					vim.list_extend(lines, vim.split(stderr, "\n", { plain = true }))
				end
				if #lines == 0 then
					lines = { "(no output)" }
				end
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			end)
		end)
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
	if uv.fs_stat(makefile_path) then
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

	local ok = Links.SelectLinks({}, makefile_content, function(selected_links)
		local lines = Generator.ExecutableTarget(
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
