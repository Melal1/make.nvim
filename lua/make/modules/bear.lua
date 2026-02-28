local Parser = require("make.modules.parser")
local Utils = require("make.shared.utils")

---@class Bear
local M = {}
local function is_object_target_name(name)
	return name and name:match("^%$%(BUILD_OUT%).+%.o$")
end
---@param args string[] commands to run
---@param cwd string|nil
---@param success_msg? string text to show when success
---@param Callback function|nil
local function run_bear_async(args, cwd, success_msg, Callback)
	vim.system(args, { text = true, cwd = cwd }, function(obj)
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
	local resolved = Utils.ResolveTargetName(target, vars)
	if not resolved then
		return resolved
	end
	return vim.trim(resolved)
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
				if is_object_target_name(Target.name) then
					local ModifiedName = resolve_target_name(Target.name, Vars)
					local args = { "bear", "--append", "--", "make", "-B", ModifiedName }
					run_bear_async(args, Rootdir, "Bear finished", Callback)

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
		if targetName and is_object_target_name(targetName) then
			local ModifiedName = targetName
				:gsub("%$%(BUILD_OUT%)", BuildDir)
				:match("^%s*(.-)%s*$")
			local args = { "bear", "--append", "--", "make", "-B", ModifiedName }
			run_bear_async(args, Rootdir, "Bear finished")

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
				if is_object_target_name(Target.name) then
					table.insert(BearTargets, resolve_target_name(Target.name, Vars))
					break
				end
			end
		end

		local args = { "bear", "--append", "--", "make", "-B" }
		vim.list_extend(args, BearTargets)
		run_bear_async(args, Rootdir, "Bear finished")
	end, { prompt_title = "Select targets for Bear", previewer = Picker.text_per_entry_previewer("make") })
	return true
end

return M
