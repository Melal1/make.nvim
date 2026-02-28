local M = {}

local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")

local function normalize_build_mode(mode)
	if not mode or mode == "" then
		return nil
	end
	local normalized = mode:lower()
	if normalized == "debug" or normalized == "release" then
		return normalized
	end
	return nil
end

local function update_makefile_var(lines, var_name, value)
	for i, line in ipairs(lines) do
		local name, op = line:match("^%s*([%w_]+)%s*(:?=)")
		if name == var_name then
			local prefix = line:match("^(%s*)") or ""
			lines[i] = string.format("%s%s %s %s", prefix, var_name, op or "=", value)
			return true
		end
	end
	return false
end

local function insert_makefile_var(lines, var_name, value)
	local insert_at = 1
	for i, line in ipairs(lines) do
		if line:match("^%s*%w[%w_]*%s*:?=") or line:match("^%s*$") then
			insert_at = i + 1
		else
			break
		end
	end
	table.insert(lines, insert_at, string.format("%s = %s", var_name, value))
end

local function resolve_build_path(makefile_path, build_out)
	if not build_out or build_out == "" then
		return nil
	end
	if build_out:match("^%a:[/\\]") or build_out:match("^/") then
		return build_out
	end
	local base_dir = vim.fn.fnamemodify(makefile_path or "", ":h")
	if base_dir == "" then
		return build_out
	end
	build_out = build_out:gsub("^%./", "")
	return base_dir .. "/" .. build_out
end

local function normalize_clean_path(path)
	if not path or path == "" then
		return nil
	end
	local normalized = vim.fn.fnamemodify(path, ":p")
	if normalized == "/" or normalized == "" then
		return nil
	end
	return normalized
end

function M.SetBuildMode(MakefilePath, Content, Mode)
	local normalized = normalize_build_mode(Mode)
	if not normalized then
		Utils.Notify("Usage: Make mode [debug|release].", vim.log.levels.WARN)
		return false
	end

	local value = normalized == "release" and "$(RELEASEFLAGS)" or "$(DEBUGFLAGS)"
	local lines = vim.split(Content or "", "\n", { plain = true })
	if not update_makefile_var(lines, "CXXFLAGS", value) then
		insert_makefile_var(lines, "CXXFLAGS", value)
	end

	local vars = Parser.ParseVariables(Content or "")
	local base_dir = vars.BUILD_DIR or "build"
	base_dir = base_dir:gsub("/debug$", ""):gsub("/release$", "")
	if base_dir:sub(-1) == "/" then
		base_dir = base_dir:sub(1, -2)
	end
	if base_dir == "" then
		base_dir = "build"
	end
	if not update_makefile_var(lines, "BUILD_DIR", base_dir) then
		insert_makefile_var(lines, "BUILD_DIR", base_dir)
	end
	if not update_makefile_var(lines, "BUILD_MODE", normalized) then
		insert_makefile_var(lines, "BUILD_MODE", normalized)
	end

	local new_content = table.concat(lines, "\n")
	local ok, err = Utils.WriteFile(MakefilePath, new_content)
	if not ok then
		Utils.Notify("Failed to update build mode: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return false
	end

	Utils.Notify("Build mode set to " .. normalized .. ".", vim.log.levels.INFO)
	return true
end

function M.CleanBuild(MakefilePath, Content)
	local vars = Parser.ParseVariables(Content or "")
	local build_out = Utils.GetBuildOutputDir(vars)
	if not build_out or build_out == "" then
		Utils.Notify("Build output directory not found.", vim.log.levels.WARN)
		return false
	end

	local resolved = resolve_build_path(MakefilePath, build_out)
	local clean_path = normalize_clean_path(resolved)
	if not clean_path then
		Utils.Notify("Refusing to clean an invalid build path.", vim.log.levels.ERROR)
		return false
	end

	if not vim.loop.fs_stat(clean_path) then
		local mode = vars.BUILD_MODE or "debug"
		Utils.Notify("No build output to clean for mode '" .. mode .. "'.", vim.log.levels.INFO)
		return true
	end

	local ok = vim.fn.delete(clean_path, "rf")
	if ok ~= 0 then
		Utils.Notify("Failed to clean build output: " .. clean_path, vim.log.levels.ERROR)
		return false
	end

	local mode = vars.BUILD_MODE or "debug"
	Utils.Notify("Cleaned build output for mode '" .. mode .. "': " .. build_out, vim.log.levels.INFO)
	return true
end

return M
