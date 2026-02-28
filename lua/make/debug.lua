local M = {}

local Utils = require("make.shared.utils")
local Finder = require("make.shared.finder")
local Parser = require("make.modules.parser")
local uv = vim.uv or vim.loop

local function resolve_build_dir(root_path, vars)
	local build_out = Utils.GetBuildOutputDir(vars or {})
	if not build_out or build_out == "" then
		build_out = "build"
	end
	build_out = build_out:gsub("^%./", "")
	if build_out:match("^/") then
		return build_out
	end
	return root_path .. "/" .. build_out
end

local function find_executables(file_path, config)
	local start_dir = nil
	if file_path and file_path ~= "" then
		start_dir = vim.fn.fnamemodify(file_path, ":h")
	end

	local root = Finder.FindRoot(start_dir, config and config.MaxSearchLevels, config and config.RootMarkers)
	if not root then
		Utils.Notify("Could not find project root", vim.log.levels.ERROR)
		return nil
	end

	local makefile_path = root.Path .. "/Makefile"
	Parser.SetCacheRoot(root.Path, makefile_path)

	local content = Utils.ReadFile(makefile_path) or ""
	local vars = Parser.ParseVariables(content, { root_path = root.Path, makefile_path = makefile_path })
	if config and config.MakefileVars then
		vars = vim.tbl_deep_extend("force", config.MakefileVars, vars)
	end
	if (vars.BUILD_MODE or "debug") ~= "debug" then
		Utils.Notify(
			"Build mode is not debug. Run :Make mode debug (or set BUILD_MODE=debug) first.",
			vim.log.levels.ERROR
		)
		return nil
	end

	local build_dir = resolve_build_dir(root.Path, vars)
	local scandir = uv.fs_scandir(build_dir)
	if not scandir then
		Utils.Notify("Could not open build directory: " .. build_dir, vim.log.levels.ERROR)
		return nil
	end

	local exe_files = {}
	while true do
		local name, entry_type = uv.fs_scandir_next(scandir)
		if not name then
			break
		end
		if entry_type == "file" and vim.fn.fnamemodify(name, ":e") == "" then
			table.insert(exe_files, name)
		end
	end

	if #exe_files == 0 then
		Utils.Notify("No executables found in build directory", vim.log.levels.WARN)
		return nil
	end

	table.sort(exe_files)
	return exe_files, root, build_dir
end

function M.RunDebug(filetype, executable_path)
	local function run_gdbserver()
		local args = { "gdbserver", "--no-startup-with-shell", ":1234", executable_path }
		if os.getenv("TMUX") then
			local cmd = { "tmux", "split-window", "-h", "-l", "30" }
			vim.list_extend(cmd, args)
			vim.system(cmd, { detach = true })
		else
			local term = require("make.terminal")
			term.SingleShotJob(args)
		end
	end

	local db = {
		c = run_gdbserver,
		cpp = run_gdbserver,
	}

	if db[filetype] then
		db[filetype]()
	else
		Utils.Notify("No debug configuration for filetype: " .. filetype, vim.log.levels.WARN)
	end
end

---@param make_build_first? boolean
---@param config? MakeConfig
function M.Debug(make_build_first, config)
	local ok_dap, dap = pcall(require, "dap")
	if not ok_dap then
		Utils.Notify("nvim-dap is not available", vim.log.levels.ERROR)
		return nil
	end

	local picker = require("make.pick")
	if not picker.available then
		Utils.Notify("Pickers are not available", vim.log.levels.ERROR)
		return dap.ABORT
	end

	make_build_first = make_build_first or false
	if make_build_first then
		vim.cmd("Make build")
	end

	local file_path = vim.fn.expand("%:p")
	local files, _, build_dir = find_executables(file_path, config)
	if not files then
		Utils.Notify("No executable files found.", vim.log.levels.WARN)
		return dap.ABORT
	end

	return coroutine.create(function(dap_run_co)
		picker.pick_single(files, function(selected)
			local executable_path
			if selected then
				executable_path = build_dir .. "/" .. selected
				M.RunDebug(vim.bo.filetype, executable_path)
			else
				executable_path = dap.ABORT
			end
			coroutine.resume(dap_run_co, executable_path)
		end, { prompt_title = "Select executable to debug" })
	end)
end

return M
