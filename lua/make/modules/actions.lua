local M = {}

local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")
local Generator = require("make.modules.generator")
local Links = require("make.modules.links")
local Helpers = require("make.modules.helpers")
local Targets = require("make.modules.targets")

---@param MakefilePath string
---@param FilePath string
---@param RootPath string
---@param Content string
---@param BypassCheck boolean|nil
---@param Config table|nil
---@return boolean
function M.AddToMakefile(MakefilePath, FilePath, RootPath, Content, BypassCheck, Config)
	Config = Config or {}
	BypassCheck = BypassCheck or false
	if not BypassCheck then
		if not Utils.IsValidSourceFile(FilePath, Config.SourceExtensions) then
			Utils.Notify("File is not a valid source file: " .. vim.fn.fnamemodify(FilePath, ":e"), vim.log.levels.WARN)
			return false
		end
	end

	local Vars = Parser.ParseVariables(Content)
	local BuildDir = Utils.GetBuildOutputDir(Vars)

	local RelativePath = Helpers.GetRelativeOrWarn(FilePath, RootPath)
	if not RelativePath then
		return false
	end

	local Basename = vim.fn.fnamemodify(FilePath, ":t:r")

	local TargetType = vim.fn.input("Target type - [o]bject file or [e]xecutable? [o/e]:\n")
	if TargetType ~= "o" and TargetType ~= "e" then
		Utils.Notify("\nInvalid choice. Must be 'o ( Object )' or 'e ( Executable )'.", vim.log.levels.WARN)
		return false
	end

	if TargetType == "o" then
		local ObjName = Basename .. ".o"
		if Parser.TargetExists(Content, RelativePath) then
			Utils.Notify("\nObject target '" .. ObjName .. "' already exists.", vim.log.levels.INFO)
			return false
		end

		local Lines = Generator.ObjectTarget(Basename, RelativePath, Config.MakefileVars)
		local AppendSuccess, WriteErr = Utils.AppendToFile(MakefilePath, Lines)
		if not AppendSuccess then
			Utils.Notify("\nFailed to write to Makefile: " .. WriteErr, vim.log.levels.ERROR)
			return false
		end

		Utils.Notify("\nAdded object target: " .. ObjName, vim.log.levels.INFO)
		local Bear = require("make.modules.bear")
		Bear.Target(Lines, RootPath, BuildDir)
		return true
	end

	if Parser.TargetExists(Content, RelativePath) then
		Utils.Notify("\nExecutable target '" .. Basename .. "' already exists.", vim.log.levels.INFO)
		return false
	end

	local ObjectFiles = Targets.GetObjectTargetsForPicker(Content)

	local function finalize_executable(selected_deps)
		local ok = Links.SelectLinks({}, Content, function(selected_links)
			local Lines, status = Generator.ExecutableTarget(
				Basename,
				RelativePath,
				selected_deps,
				Config.MakefileVars,
				RootPath,
				selected_links
			)
			if not status then
				Utils.Notify(
					"\nFailed to generate executable target. Missing include paths for: " .. table.concat(Lines, ", "),
					vim.log.levels.ERROR
				)
				return
			end
			local AppendSuccess, WriteErr = Utils.AppendToFile(MakefilePath, Lines)
			if not AppendSuccess then
				Utils.Notify("\nFailed to write to Makefile: " .. WriteErr, vim.log.levels.ERROR)
				return
			end
			Utils.Notify(
				"\nAdded executable target: " .. Basename .. " with " .. #selected_deps .. " dependencies",
				vim.log.levels.INFO
			)
		end, { prompt_title = "Select link flags" })
		return ok
	end

	if #ObjectFiles > 0 then
		local picker = Helpers.GetPickerOrWarn("Picker is required for selection.")
		if not picker then
			return false
		end
		picker.pick_checklist(ObjectFiles, function(Selected)
			finalize_executable(Selected or {})
		end, { prompt_title = "Select object file dependencies" })
	else
		if finalize_executable({}) == false then
			return false
		end
	end
	return true
end

---@param MakefilePath string
---@param FilePath string
---@param RootPath string
---@param Content string
---@param Entries table[]|nil
---@param callback fun(success:boolean)|nil
---@param Config table|nil
---@return boolean
function M.EditTarget(MakefilePath, FilePath, RootPath, Content, Entries, callback, Config)
	Config = Config or {}
	local Basename = vim.fn.fnamemodify(FilePath, ":t:r")

	local RelativePath = Helpers.GetRelativeOrWarn(FilePath, RootPath)
	if not RelativePath then
		if callback then
			callback(false)
		end
		return false
	end

	if not Entries or #Entries == 0 then
		Entries = Targets.GetExeTables(Content)
		if not Entries or #Entries == 0 then
			Utils.Notify("No executable targets found in Makefile", vim.log.levels.WARN)
			if callback then
				callback(false)
			end
			return false
		end
	end

	local existing_deps = {}
	local entry = Helpers.FindSectionByPath(Entries, RelativePath)
	if entry and entry.analysis.targets[2] then
		existing_deps = { unpack(entry.analysis.targets[2].dependencies, 2) }
	end
	local existing_links = Links.GetExistingLinks(Content, RelativePath, (entry and entry.baseName) or Basename)

	local ObjectFiles = Targets.GetObjectTargetsForPicker(Content)
	if not ObjectFiles or #ObjectFiles == 0 then
		if not Links.HasLinkOptions(Content) then
			Utils.Notify("No object files available for dependency selection", vim.log.levels.WARN)
			if callback then
				callback(false)
			end
			return false
		end

		local ok = Links.SelectLinks(existing_links, Content, function(selected_links)
			local updated_content =
				Links.UpdateLinksForEntry(Content, RelativePath, (entry and entry.baseName) or Basename, selected_links)
			if not updated_content then
				if callback then
					callback(false)
				end
				return
			end

			local Success, WriteErr = Utils.WriteFile(MakefilePath, updated_content)
			if not Success then
				Utils.Notify("Failed to write Makefile: " .. WriteErr, vim.log.levels.ERROR)
				if callback then
					callback(false)
				end
				return
			end

			Utils.Notify("Updated links for: " .. Basename, vim.log.levels.INFO)
		end, { prompt_title = "Select link flags", preselect = true })

		if ok == false and callback then
			callback(false)
		end
		return true
	end

	local picker = Helpers.GetPickerOrWarn("Picker is required for editing targets")
	if not picker then
		if callback then
			callback(false)
		end
		return false
	end

	picker.pick_checklist(ObjectFiles, function(selected)
		local selected_deps = selected or {}
		local ok = Links.SelectLinks(existing_links, Content, function(selected_links)
			local markerInfo = Parser.FindMarker(Content, RelativePath, true, true)

			if markerInfo.M_start == -1 then
				Utils.Notify("Marker start not found for: " .. RelativePath, vim.log.levels.ERROR)
				if callback then
					callback(false)
				end
				return
			end

			if markerInfo.M_end == -1 then
				Utils.Notify("Marker end not found for: " .. RelativePath, vim.log.levels.ERROR)
				if callback then
					callback(false)
				end
				return
			end

			local Lines = vim.split(Content, "\n", { plain = true })
			local NewLines = {}
			for i = 1, markerInfo.M_start - 1 do
				table.insert(NewLines, Lines[i])
			end
			for i = markerInfo.M_end + 1, #Lines do
				table.insert(NewLines, Lines[i])
			end

			Content = table.concat(NewLines, "\n")

			local GenLines, status = Generator.ExecutableTarget(
				Basename,
				RelativePath,
				selected_deps,
				Config.MakefileVars,
				RootPath,
				selected_links
			)
			if not status then
				Utils.Notify(
					"Failed to regenerate target. Missing include paths for: " .. table.concat(GenLines, ", "),
					vim.log.levels.ERROR
				)
				if callback then
					callback(false)
				end
				return
			end

			Content = Content .. table.concat(GenLines, "\n")
			local Success, WriteErr = Utils.WriteFile(MakefilePath, Content)
			if not Success then
				Utils.Notify("Failed to write Makefile: " .. WriteErr, vim.log.levels.ERROR)
				if callback then
					callback(false)
				end
				return
			end
			Utils.Notify(
				"Edited target: " .. Basename .. " with " .. #selected_deps .. " dependencies",
				vim.log.levels.INFO
			)
		end, { prompt_title = "Select link flags", preselect = true })

		if ok == false and callback then
			callback(false)
		end
	end, { prompt_title = "Select new dependencies for " .. Basename, preselected_items = existing_deps })
	return true
end

---@param MakefilePath string
---@param RootPath string
---@param Content string
---@param Config table|nil
---@return boolean
function M.EditAllTargets(MakefilePath, RootPath, Content, Config)
	local Entries = Targets.GetExeTables(Content)
	if not Entries or #Entries == 0 then
		Utils.Notify("No executable targets found in Makefile", vim.log.levels.WARN)
		return false
	end

	local picker = Helpers.GetPickerOrWarn("Picker is required for editing targets")
	if not picker then
		return false
	end

	local pick_entries = {}
	local entry_map = {}
	for _, ent in ipairs(Entries) do
		table.insert(pick_entries, { value = ent.baseName, display = ent.baseName })
		entry_map[ent.baseName] = ent
	end

	picker.pick_single(pick_entries, function(selected)
		if #selected == 0 then
			Utils.Notify("Nothing selected.", vim.log.levels.WARN)
			return
		end

		M.EditTarget(MakefilePath, entry_map[selected].path, RootPath, Content, entry_map[selected], nil, Config)
	end, { prompt_title = "Select target to edit" })
	return true
end

---@param MakefilePath string
---@param Content string
---@return boolean
function M.Remove(MakefilePath, Content)
	local Entries = Parser.AnalyzeAllSections(Content)

	local map = {}
	local PickerEntries = {}
	local lines = vim.split(Content or "", "\n", { plain = true, trimempty = false })

	local picker = Helpers.GetPickerOrWarn("Picker is required for editing targets")
	if not picker then
		return false
	end

	for _, Entry in ipairs(Entries) do
		table.insert(PickerEntries, {
			value = Entry.startLine,
			display = Entry.baseName .. " ( " .. Entry.analysis.type .. " )",
			preview_text = Parser.ReadContentBetweenLines(lines, Entry.startLine, Entry.endLine, true),
		})
		map[Entry.startLine] = Entry
	end

	picker.pick_multi_with_preview(PickerEntries, function(selected)
		if #selected == 0 then
			Utils.Notify("Nothing selected.", vim.log.levels.WARN)
			return
		end

		local Lines = {}
		for text, nl in Content:gmatch("([^\n]*)(\n?)") do
			if text ~= "" then
				if nl ~= "" then
					text = text .. nl
				end
				table.insert(Lines, text)
			else
				if nl ~= "" then
					table.insert(Lines, nl)
				end
			end
		end

		local delete_map = {}
		for _, line_num in ipairs(selected) do
			local entry = map[line_num]
			if entry then
				if Lines[line_num - 1] == "\n" then
					delete_map[line_num - 1] = true
				end
				for i = line_num, entry.endLine do
					delete_map[i] = true
				end
			end
		end

		local NewLines = {}
		for i = 1, #Lines do
			if not delete_map[i] then
				table.insert(NewLines, Lines[i])
			end
		end
		Lines = NewLines

		Content = table.concat(Lines)

		local Success, WriteErr = Utils.WriteFile(MakefilePath, Content)
		if not Success then
			Utils.Notify("Failed to write Makefile: " .. WriteErr, vim.log.levels.ERROR)
			return
		end
	end, { prompt_title = "Select target(s) to remove", previewer = picker.text_per_entry_previewer("make") })
	return true
end

---@param RootPath string where it will search for sources
---@return boolean
function M.PickAndAdd(RootPath, Content)
	local picker = Helpers.GetPickerOrWarn("Picker is required for selection.")
	if not picker then
		return false
	end
	local results = vim.fs.find(function(name)
		return name:match("%.cpp$") ~= nil -- change extension here
	end, { path = RootPath, type = "file", limit = math.huge })

	if #results == 0 then
		Utils.Notify("No source files found in project", vim.log.levels.WARN)
		return false
	end

	picker.pick_checklist(results, function(selected) end)
	return true
end

return M
