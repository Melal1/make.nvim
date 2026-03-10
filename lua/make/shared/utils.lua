---@class Utils
local Utils = {}

Utils.BackupEnabled = true

---Reads the entire contents of a file.
---@param FilePath string
---@return string|nil content
---@return string? err
function Utils.ReadFile(FilePath)
	local File, Err = io.open(FilePath, "r")
	if not File then
		return nil, "Could not open file: " .. FilePath .. " (" .. (Err or "unknown error") .. ")"
	end

	local Content = File:read("*a")
	File:close()

	if not Content then
		return nil, "Could not read file content: " .. FilePath
	end

	return Content
end

---Writes content to a file (creates a backup if file exists).
---@param FilePath string
---@param Content string
---@param EnableBackup boolean?
---@return boolean success
---@return string? err
function Utils.WriteFile(FilePath, Content, EnableBackup)
	if EnableBackup == nil then
		EnableBackup = Utils.BackupEnabled
	end
	if EnableBackup then
		local BackupPath = FilePath .. ".bak"
		local OriginalContent = Utils.ReadFile(FilePath)
		if OriginalContent then
			local BackupFile = io.open(BackupPath, "w")
			if BackupFile then
				BackupFile:write(OriginalContent)
				BackupFile:close()
			end
		end
	end

	local File, Err = io.open(FilePath, "w")
	if not File then
		return false, "Could not open file for writing: " .. FilePath .. " (" .. (Err or "unknown error") .. ")"
	end

	local Success, WriteErr = File:write(Content)
	File:close()

	if not Success then
		return false, "Could not write to file: " .. FilePath .. " (" .. (WriteErr or "unknown error") .. ")"
	end

	return true
end

---Appends multiple lines to a file.
---@param FilePath string
---@param Lines string[]
---@return boolean success
---@return string? err
function Utils.AppendToFile(FilePath, Lines)
	local File, Err = io.open(FilePath, "a")
	if not File then
		return false, "Could not open file for appending: " .. FilePath .. " (" .. (Err or "unknown error") .. ")"
	end

	for _, Line in ipairs(Lines) do
		File:write(Line .. "\n")
	end
	File:close()
	return true
end

---Checks if a file has a valid source extension.
---@param FilePath string
---@param SourceExtensions string[]
---@return boolean
function Utils.IsValidSourceFile(FilePath, SourceExtensions)
	local Ext = vim.fn.fnamemodify(FilePath, ":e")
	for _, ValidExt in ipairs(SourceExtensions) do
		if "." .. Ext == ValidExt then
			return true
		end
	end
	return false
end

---Escapes Lua pattern magic characters in a string.
---@param Str string
---@return string escaped
---@return integer count
function Utils.EscapePattern(Str)
	return Str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

---Returns the relative path of a file with respect to a root path.
---@param FilePath string
---@param RootPath string
---@return string relativePath
---@return boolean okay
function Utils.GetRelativePath(FilePath, RootPath)
	local AbsFilePath = vim.fn.fnamemodify(FilePath, ":p")
	local AbsRoot = vim.fn.fnamemodify(RootPath, ":p")

	if AbsRoot:sub(-1) ~= "/" then
		AbsRoot = AbsRoot .. "/"
	end

	if AbsFilePath:sub(1, #AbsRoot) == AbsRoot then
		return "./" .. AbsFilePath:sub(#AbsRoot + 1), true
	else
		return "File is outside the project root", false
	end
end

---Standardized notifications for MakeNvim.
---@param Message string
---@param Level integer|nil
---@param Opts table|nil
function Utils.Notify(Message, Level, Opts)
	local msg = vim.trim(Message or "")
	if msg == "" then
		return
	end
	if not msg:match("^MakeNvim:%s") then
		msg = "MakeNvim: " .. msg
	end
	vim.notify(msg, Level or vim.log.levels.INFO, Opts)
end

---Returns the build output directory using BUILD_DIR and BUILD_MODE.
---@param Vars table
---@return string
function Utils.GetBuildOutputDir(Vars)
	if not Vars then
		return "build"
	end
	local build_out = Vars.BUILD_OUT
	if build_out and build_out ~= "" and not build_out:find("%$%(") then
		return build_out
	end
	local build_dir = Vars.BUILD_DIR or "build"
	local build_mode = Vars.BUILD_MODE or ""
	if build_mode ~= "" then
		if build_dir:match("/" .. Utils.EscapePattern(build_mode) .. "$") then
			return build_dir
		end
		return build_dir .. "/" .. build_mode
	end
	return build_dir
end

---Normalize a relative path by stripping a leading "./".
---@param path string
---@return string
function Utils.NormalizeRelativePath(path)
	path = path or ""
	return (path:gsub("^%./", ""))
end

---Return a relative path without its extension, without a leading "./".
---@param path string
---@return string
function Utils.RelativePathNoExt(path)
	local normalized = Utils.NormalizeRelativePath(path)
	if normalized == "" then
		return normalized
	end
	return vim.fn.fnamemodify(normalized, ":r")
end

---Flatten a relative path into a single name segment (no directory separators).
---@param path string
---@return string
function Utils.FlattenRelativePath(path)
	local rel_no_ext = Utils.RelativePathNoExt(path)
	if rel_no_ext == "" then
		return rel_no_ext
	end
	return (rel_no_ext:gsub("[/\\\\]", "__"))
end

---Sanitize a target name by removing whitespace and path separators.
---@param name string
---@return string
function Utils.SanitizeTargetName(name)
	name = vim.trim(name or "")
	if name == "" then
		return ""
	end
	name = name:gsub("%s+", "_")
	name = name:gsub("[/\\\\]", "__")
	return name
end

---Resolve a target name by substituting BUILD_DIR / BUILD_MODE placeholders.
---@param target string|nil
---@param vars table|nil
---@return string|nil
function Utils.ResolveTargetName(target, vars)
	if not target then
		return target
	end
	vars = vars or {}
	local build_out = Utils.GetBuildOutputDir(vars)
	local resolved = target
	if resolved:find("%$%(BUILD_OUT%)") then
		resolved = resolved:gsub("%$%(BUILD_OUT%)", build_out)
	end
	return resolved
end

return Utils
