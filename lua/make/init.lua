---@class MakeModule
---@field Config MakeConfig
local M = {}

local Config = require("make.modules.config")
local Utils = require("make.shared.utils")
local uv = vim.uv or vim.loop
local Parser = require("make.modules.parser")
local Generator = require("make.modules.generator")
local RootFinder = require("make.shared.finder")
local Links = require("make.modules.links")
local Actions = require("make.modules.actions")
local Runner = require("make.modules.runner")
local Build = require("make.modules.build")
local Debug = require("make.debug")

---@type MakeConfig
M.Config = Config.DefaultConfig
Utils.BackupEnabled = M.Config.EnableBackup
if M.Config.CacheUseHash ~= nil then
	Parser.CacheUseHash = M.Config.CacheUseHash
end
if M.Config.CacheFormat ~= nil then
	Parser.CacheFormat = M.Config.CacheFormat
end
if M.Config.CacheDir ~= nil then
	Parser.CacheDir = M.Config.CacheDir
end
if M.Config.CacheLog ~= nil then
	Parser.CacheLog = M.Config.CacheLog
end

---@param UserConfig make_options|nil
function M.setup(UserConfig)
	M.Config = vim.tbl_deep_extend("force", M.Config, UserConfig or {})
	if M.Config.CacheUseHash ~= nil then
		Parser.CacheUseHash = M.Config.CacheUseHash
	end
	if M.Config.CacheFormat ~= nil then
		Parser.CacheFormat = M.Config.CacheFormat
	end
	if M.Config.CacheDir ~= nil then
		Parser.CacheDir = M.Config.CacheDir
	end
	if M.Config.CacheLog ~= nil then
		Parser.CacheLog = M.Config.CacheLog
	end
	if M.Config.EnableBackup ~= nil then
		Utils.BackupEnabled = M.Config.EnableBackup
	end
end

function M.SetBuildMode(MakefilePath, Content, Mode)
	return Build.SetBuildMode(MakefilePath, Content, Mode)
end

function M.CleanBuild(MakefilePath, Content)
	return Build.CleanBuild(MakefilePath, Content)
end

function M.Debug(MakeBuildFirst)
	return Debug.Debug(MakeBuildFirst, M.Config)
end

function M.RunDebug(Filetype, ExecutablePath)
	return Debug.RunDebug(Filetype, ExecutablePath)
end

function M.ManageLinkOptionsInteractive(makefile_path, makefile_content)
	return Links.ManageInteractive(makefile_path, makefile_content)
end

function M.AddToMakefile(MakefilePath, FilePath, RootPath, Content, BypassCheck)
	return Actions.AddToMakefile(MakefilePath, FilePath, RootPath, Content, BypassCheck, M.Config)
end

function M.EditTarget(MakefilePath, FilePath, RootPath, Content, Entries, callback)
	return Actions.EditTarget(MakefilePath, FilePath, RootPath, Content, Entries, callback, M.Config)
end

function M.EditAllTargets(MakefilePath, RootPath, Content)
	return Actions.EditAllTargets(MakefilePath, RootPath, Content, M.Config)
end

function M.Remove(MakefilePath, Content)
	return Actions.Remove(MakefilePath, Content)
end

function M.PickAndAdd(RootPath, Content)
	return Actions.PickAndAdd(RootPath, Content, M.Config)
end

function M.BuildTarget(MakefilePath, RelativePath, Content)
	return Runner.BuildTarget(MakefilePath, RelativePath, Content)
end

function M.RunTargetInSpilt(MakefilePath, RelativePath, Content)
	return Runner.RunTargetInSpilt(MakefilePath, RelativePath, Content)
end

function M.PickAndRunTargets(makefile_content)
	return Runner.PickAndRunTargets(makefile_content)
end

function M.FastRun()
	return Runner.FastRun(M.Config, function()
		M.Make({ "run" })
	end)
end

---@param Fargs string[]
---@return boolean|nil
function M.Make(Fargs)
	local arg = (Fargs[1] or "run"):lower()
	if #Fargs > 2 and arg ~= "link" then
		Utils.Notify("Too many arguments. Use: add, edit, run, ...", vim.log.levels.WARN)
		return false
	end

	local Root, Err = RootFinder.FindRoot(nil, M.Config.MaxSearchLevels, M.Config.RootMarkers)

	if not Root then
		Utils.Notify("No project root found: " .. (Err or "unknown error"), vim.log.levels.WARN)
		return false
	end

	local MakefilePath = Root.Path .. "/Makefile"
	Parser.SetCacheRoot(Root.Path, MakefilePath)

	local Stat = uv.fs_stat(MakefilePath)
	if not Stat then
		-- This will only get triggered if there is another root marker other than Makefile and Makefile don't exist
		local ans = vim.fn.input("Makefile not found. Create it? (y/n): ")

		if ans ~= "y" and ans ~= "Y" then
			return false
		end

		local Success = Generator.EnsureMakefileVariables(MakefilePath, nil, M.Config.MakefileVars)
		if Success == nil then
			return nil
		end
		if Fargs[1] == "run" or Fargs[1] == "runb" then
			M.Make({ "add" })
			return false
		end
		M.Make(Fargs)
		return false
	end

	if arg == "open" then
		if uv.fs_stat(MakefilePath) then
			vim.cmd("edit " .. vim.fn.fnameescape(MakefilePath))
			Utils.Notify("Opened Makefile", vim.log.levels.INFO)
			return true
		else
			Utils.Notify("Makefile not found at " .. MakefilePath, vim.log.levels.WARN)
			return false
		end
	end

	local MakefileContent, _ = Utils.ReadFile(MakefilePath)
	local Success = Generator.EnsureMakefileVariables(MakefilePath, MakefileContent, M.Config.MakefileVars)
	if not Success then
		if Success == nil then
			Utils.Notify("Failed to ensure Makefile variables", vim.log.levels.ERROR)
			return nil
		end
		return M.Make(Fargs)
	end
	if not MakefileContent then
		MakefileContent = ""
	end

	local CurrentFile = vim.fn.expand("%:p")
	if CurrentFile == "" then
		Utils.Notify("No file currently open", vim.log.levels.WARN)
		return false
	end

	if arg == "add" then
		return M.AddToMakefile(MakefilePath, CurrentFile, Root.Path, MakefileContent)
	elseif arg == "bearall" then
		return require("make.modules.bear").SelectTarget(MakefileContent, Root.Path)
	elseif arg == "run" then
		local RelativePath, _ = Utils.GetRelativePath(CurrentFile, Root.Path)
		M.RunTargetInSpilt(MakefilePath, RelativePath, MakefileContent)
		return true
	elseif arg == "runb" then
		local Bear = require("make.modules.bear")
		local RelativePath, _ = Utils.GetRelativePath(CurrentFile, Root.Path)
		Bear.CurrentFile(MakefileContent, Root.Path, RelativePath, function()
			M.Make({ "run" })
		end)
		return true
	elseif arg == "build" then
		local RelativePath, _ = Utils.GetRelativePath(CurrentFile, Root.Path)
		M.BuildTarget(MakefilePath, RelativePath, MakefileContent)
	elseif arg == "edit" then
		return M.EditTarget(MakefilePath, CurrentFile, Root.Path, MakefileContent)
	elseif arg == "tasks" then
		return M.PickAndRunTargets(MakefileContent)
	elseif arg == "edit_all" then
		return M.EditAllTargets(MakefilePath, Root.Path, MakefileContent)
	elseif arg == "pick-add" or arg == "pick_add" then
		return M.PickAndAdd(Root.Path, MakefileContent)
	elseif arg == "remove" then
		return M.Remove(MakefilePath, MakefileContent)
	elseif arg == "analysis" then
		Parser.PrintAnalysisSummary(MakefileContent)
		return true
	elseif arg == "bear" then
		local Bear = require("make.modules.bear")
		return Bear.CurrentFile(MakefileContent, Root.Path)
	elseif arg == "mode" then
		return M.SetBuildMode(MakefilePath, MakefileContent, Fargs[2])
	elseif arg == "clean" then
		return M.CleanBuild(MakefilePath, MakefileContent)
	elseif arg == "link" then
		return M.ManageLinkOptionsInteractive(MakefilePath, MakefileContent)
	else
		Utils.Notify("Unknown command.", vim.log.levels.WARN)
		return false
	end
end

return M
