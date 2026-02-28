---@class RootInfo
---@field Path string           # Absolute path to the detected project root
---@field Marker string         # The marker that determined the root (e.g. ".git", "Makefile")
---@field Level integer         # How many levels up the search went

local Finder = {}
local Utils = require("make.shared.utils")
local uv = vim.uv or vim.loop
local header_index_cache = {}

local function normalize_root(root_path)
	local normalized = vim.fn.fnamemodify(root_path or "", ":p")
	if normalized:sub(-1) == "/" then
		normalized = normalized:sub(1, -2)
	end
	return normalized
end

local function build_header_index(root_path)
	local index = {}
	if not root_path or root_path == "" then
		return index
	end

	local headers = vim.fs.find(function(name)
		return name:sub(-2) == ".h"
	end, { path = root_path, type = "file", limit = math.huge })

	for _, header_path in ipairs(headers) do
		local base = vim.fn.fnamemodify(header_path, ":t:r")
		if not index[base] then
			local header_dir = vim.fn.fnamemodify(header_path, ":h")
			local relative_dir, ok = Utils.GetRelativePath(header_dir, root_path)
			if ok then
				index[base] = relative_dir
			else
				index[base] = header_dir
			end
		end
	end

	return index
end

---Finds the root directory of a project by searching upward from a starting point
---for known root markers (e.g. `.git`, `Makefile`).
---
---@param StartingPoint? string  # Directory to start the search from (defaults to current buffer's directory)
---@param MaxSearchLevels? integer # Maximum number of parent directories to search
---@param RootMarkers? string[]  # List of marker names to look for
---@return RootInfo|nil, string? # Returns root info table if found, otherwise nil and an error message
function Finder.FindRoot(StartingPoint, MaxSearchLevels, RootMarkers)
	StartingPoint = StartingPoint or vim.fn.expand("%:p:h")

	if not StartingPoint or StartingPoint == "" then
		return nil, "Invalid starting location"
	end

	if not vim.fn.isdirectory(StartingPoint) then
		return nil, "Starting point is not a directory: " .. StartingPoint
	end

	MaxSearchLevels = MaxSearchLevels or 5
	RootMarkers = RootMarkers or { ".git", "src", "include", "build", "Makefile" }

	local CurrentPath = StartingPoint
	for i = 1, MaxSearchLevels do
		for _, Marker in ipairs(RootMarkers) do
			local MarkerPath = CurrentPath .. "/" .. Marker
			local Stat = uv.fs_stat(MarkerPath)
			if Stat then
				return {
					Path = CurrentPath,
					Marker = Marker,
					Level = i,
				}
			end
		end

		local ParentPath = vim.fn.fnamemodify(CurrentPath, ":h")
		if ParentPath == CurrentPath then
			break
		end
		CurrentPath = ParentPath
	end

	return nil, "No project root found within " .. MaxSearchLevels .. " levels"
end

---Build or fetch a cached header index for the project root.
---@param RootPath string
---@return table<string, string>
function Finder.BuildHeaderIndex(RootPath)
	local root = normalize_root(RootPath)
	if root == "" then
		return {}
	end
	if header_index_cache[root] then
		return header_index_cache[root]
	end
	local index = build_header_index(root)
	header_index_cache[root] = index
	return index
end

---Clear cached header index (all roots or a specific root).
---@param RootPath? string
function Finder.ClearHeaderIndex(RootPath)
	if not RootPath then
		header_index_cache = {}
		return
	end
	header_index_cache[normalize_root(RootPath)] = nil
end

---Finds the directory containing a header file with the given basename, relative to the project root.
---For example, if `Basename` is `"utils"`, it will search for `"utils.h"`.
---
---@param Basename string # Base name of the header file (without extension)
---@param RootPath string # Root directory to start the search
---@return string|nil     # Relative or absolute path to the header's directory, or nil if not found
function Finder.FindHeaderDirectory(Basename, RootPath)
	if not Basename or Basename == "" or not RootPath or RootPath == "" then
		return nil
	end
	local index = Finder.BuildHeaderIndex(RootPath)
	return index[Basename]
end

return Finder
