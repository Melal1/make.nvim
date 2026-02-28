---@module "make.modules.parser"
local Utils = require("make.shared.utils")
---@class Parser
local Parser = {}

Parser.CacheRoot = nil
Parser.CacheMakefilePath = nil
Parser.CacheLog = false
Parser.CacheUseHash = true
Parser.CacheFormat = "mpack"
Parser.CacheDir = ".cache/make.nvim"

---@param root_path string|nil
---@param makefile_path string|nil
function Parser.SetCacheRoot(root_path, makefile_path)
	if root_path and root_path ~= "" then
		Parser.CacheRoot = root_path
	end
	if makefile_path and makefile_path ~= "" then
		Parser.CacheMakefilePath = makefile_path
	end
end

local function cache_key_for(root_path)
	local normalized = vim.fn.fnamemodify(root_path or "", ":p")
	normalized = normalized:gsub("\\", "/")
	normalized = normalized:gsub("^/", "")
	normalized = normalized:gsub(":", "_")
	normalized = normalized:gsub("/", "_")
	if normalized == "" then
		return "default"
	end
	return normalized
end

local function cache_format()
	local fmt = (Parser.CacheFormat or "mpack"):lower()
	if fmt == "luabytecode" or fmt == "bytecode" or fmt == "luac" then
		return "luabytecode"
	end
	return "mpack"
end

local function cache_file_for(root_path)
	local dir = Parser.CacheDir or ".cache/make.nvim"
	if dir == "" then
		dir = ".cache/make.nvim"
	end
	if not dir:match("^/") and not dir:match("^~") then
		dir = "~/" .. dir
	end
	local base = vim.fn.expand(dir)
	local ext = cache_format() == "luabytecode" and ".luac" or ".mpack"
	return base .. "/" .. cache_key_for(root_path) .. ext
end

local function read_cache_file(cache_file)
	local file = io.open(cache_file, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	if not content or content == "" then
		return nil
	end
	return content
end

local function write_cache_file(cache_file, content)
	local file = io.open(cache_file, "wb")
	if not file then
		return false
	end
	file:write(content)
	file:close()
	return true
end

local function log_cache(message, opts)
	if not Parser.CacheLog or (opts and opts.silent) then
		return
	end
	vim.notify(message, vim.log.levels.DEBUG)
end

local function serialize_lua_value(value, seen)
	local t = type(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "number" or t == "boolean" then
		return tostring(value)
	elseif t == "table" then
		if seen[value] then
			return "nil"
		end
		seen[value] = true
		local parts = {}
		local idx = 0
		for _, item in ipairs(value) do
			idx = idx + 1
			parts[idx] = serialize_lua_value(item, seen)
		end
		for k, v in pairs(value) do
			local is_array = type(k) == "number" and k >= 1 and k <= #value and math.floor(k) == k
			if not is_array then
				local key
				if type(k) == "string" and k:match("^[%a_][%w_]*$") then
					key = k
				else
					key = "[" .. serialize_lua_value(k, seen) .. "]"
				end
				idx = idx + 1
				parts[idx] = key .. " = " .. serialize_lua_value(v, seen)
			end
		end
		seen[value] = nil
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return "nil"
end

local function encode_cache_payload(payload)
	if cache_format() == "luabytecode" then
		local source = "return " .. serialize_lua_value(payload, {})
		local chunk = load(source, "make.nvim cache", "t")
		if not chunk then
			return nil
		end
		return string.dump(chunk, true)
	end
	local ok_encode, encoded = pcall(vim.mpack.encode, payload)
	if not ok_encode or not encoded then
		return nil
	end
	return encoded
end

local function decode_cache_payload(raw)
	if cache_format() == "luabytecode" then
		local chunk = load(raw, "make.nvim cache", "b")
		if not chunk then
			return nil
		end
		local ok, payload = pcall(chunk)
		if not ok then
			return nil
		end
		return payload
	end
	local ok_decode, decoded = pcall(vim.mpack.decode, raw)
	if not ok_decode or not decoded then
		return nil
	end
	return decoded
end

local function normalize_lines(content)
	if type(content) == "table" then
		return content
	end
	if not content or content == "" then
		return {}
	end
	return vim.split(content, "\n", { plain = true, trimempty = false })
end

local function slice_lines(lines, start_line, end_line, return_table)
	local out = {}
	if not lines or #lines == 0 then
		return return_table and out or ""
	end
	for i = start_line + 1, end_line - 1 do
		table.insert(out, lines[i] or "")
	end
	if return_table then
		return out
	end
	return table.concat(out, "\n")
end

local function parse_variables_raw(Content)
	local Variables = {}
	if not Content then
		return Variables
	end
	for Line in Content:gmatch("[^\n]+") do
		Line = Line:match("^%s*(.-)%s*$")
		if Line and Line ~= "" and not Line:match("^#") then
			local VarName, VarValue = Line:match("^([%w_]+)%s*:?=%s*(.*)$")
			if VarName and VarValue then
				Variables[VarName] = VarValue
			end
		end
	end
	return Variables
end

local function parse_links_block(content)
	local groups = {}
	local group_map = {}
	local individuals = {}
	local individual_map = {}

	if not content or content == "" then
		return groups, individuals
	end

	local in_block = false
	for _, line in ipairs(vim.split(content, "\n", { plain = true })) do
		if line:match("^%s*#%s*links_start") then
			in_block = true
			goto continue
		end
		if line:match("^%s*#%s*links_end") then
			break
		end
		if not in_block then
			goto continue
		end

		local group_name, rest = line:match("^%s*#%s*group:%s*(%S+)%s*(.*)$")
		if group_name then
			local flags = {}
			for flag in (rest or ""):gmatch("%S+") do
				table.insert(flags, flag)
			end
			if #flags > 0 then
				local group = group_map[group_name]
				if not group then
					group = { name = group_name, flags = {} }
					group_map[group_name] = group
					table.insert(groups, group)
				end
				for _, flag in ipairs(flags) do
					local seen = false
					for _, existing in ipairs(group.flags) do
						if existing == flag then
							seen = true
							break
						end
					end
					if not seen then
						table.insert(group.flags, flag)
					end
				end
			end
			goto continue
		end

		local link_rest = line:match("^%s*#%s*link:%s*(.*)$")
		if link_rest then
			for flag in link_rest:gmatch("%S+") do
				if not individual_map[flag] then
					individual_map[flag] = true
					table.insert(individuals, flag)
				end
			end
		end

		::continue::
	end

	local group_flag_map = {}
	for _, group in ipairs(groups) do
		for _, flag in ipairs(group.flags) do
			group_flag_map[flag] = true
		end
	end

	local filtered_individuals = {}
	for _, flag in ipairs(individuals) do
		if not group_flag_map[flag] then
			table.insert(filtered_individuals, flag)
		end
	end

	return groups, filtered_individuals
end

local function is_links_assignment_line(line)
	return line:match("^%s*[^:]+%s*:%s*LINKS%s*[%+:%?]?=") ~= nil
end

local function search_flags_for(annotatedType)
	local searchFor = { obj = true, executable = true, run = true }
	if annotatedType then
		searchFor = { obj = false, executable = false, run = false }
		if annotatedType == "full" then
			searchFor.obj = true
			searchFor.executable = true
			searchFor.run = true
		elseif annotatedType == "executable" then
			searchFor.obj = true
			searchFor.executable = true
		elseif annotatedType == "obj" then
			searchFor.obj = true
		elseif annotatedType == "run" then
			searchFor.run = true
		end
	end
	return searchFor
end

local function read_makefile_content(makefile_path)
	if not makefile_path or makefile_path == "" then
		return nil
	end
	return Utils.ReadFile(makefile_path)
end

local function resolve_cache_paths(opts)
	local root_path = nil
	local makefile_path = nil
	if type(opts) == "table" then
		root_path = opts.root_path or opts.root or opts.project_root
		makefile_path = opts.makefile_path or opts.makefile or opts.makefilePath
	elseif type(opts) == "string" then
		root_path = opts
	end
	makefile_path = makefile_path or Parser.CacheMakefilePath
	root_path = root_path or Parser.CacheRoot or vim.fn.getcwd()
	if (not makefile_path or makefile_path == "") and root_path and root_path ~= "" then
		local candidate = root_path .. "/Makefile"
		if vim.loop.fs_stat(candidate) then
			makefile_path = candidate
		end
	end

	local cache_root = root_path
	if makefile_path and makefile_path ~= "" then
		cache_root = vim.fn.fnamemodify(makefile_path, ":h")
	end

	return cache_root, makefile_path
end

local write_cache

local function try_load_cache(root_path, makefile_path, content, opts)
	local cache_root = root_path or vim.fn.getcwd()
	local cache_file = cache_file_for(cache_root)
	local cache_stat = vim.loop.fs_stat(cache_file)
	if not cache_stat then
		return nil, nil, cache_file
	end

	local raw = read_cache_file(cache_file)
	if not raw or raw == "" then
		return nil, nil, cache_file
	end

	local decoded = decode_cache_payload(raw)
	if not decoded or type(decoded.sections) ~= "table" then
		return nil, nil, cache_file
	end

	if makefile_path and makefile_path ~= "" then
		local stat = vim.loop.fs_stat(makefile_path)
		if stat and decoded.mtime == stat.mtime.sec and decoded.size == stat.size then
			log_cache("MakeNvim cache hit (mtime/size)", opts)
			return decoded
		end
		if not Parser.CacheUseHash then
			log_cache("MakeNvim cache miss (mtime/size changed)", opts)
			return nil, nil, cache_file
		end
	end

	if not Parser.CacheUseHash then
		log_cache("MakeNvim cache miss (hash disabled)", opts)
		return nil, nil, cache_file
	end

	if not content then
		content = read_makefile_content(makefile_path)
	end
	if not content then
		log_cache("MakeNvim cache miss (no content for hash)", opts)
		return nil, nil, cache_file
	end

	local ok_hash, hash = pcall(vim.fn.sha256, content)
	if not ok_hash then
		log_cache("MakeNvim cache miss (hash error)", opts)
		return nil, nil, cache_file
	end

	if decoded.hash ~= hash then
		log_cache("MakeNvim cache miss (hash mismatch)", opts)
		return nil, hash, cache_file
	end

	log_cache("MakeNvim cache hit (hash)", opts)
	if makefile_path and makefile_path ~= "" then
		write_cache(cache_file, decoded, makefile_path, content)
		log_cache("MakeNvim cache metadata refreshed", opts)
	end
	return decoded, hash, cache_file
end

write_cache = function(cache_file, payload, makefile_path, content)
	if not cache_file then
		return
	end
	local dir = Parser.CacheDir or ".cache/make.nvim"
	if dir == "" then
		dir = ".cache/make.nvim"
	end
	if not dir:match("^/") and not dir:match("^~") then
		dir = "~/" .. dir
	end
	vim.fn.mkdir(vim.fn.expand(dir), "p")
	local out = { sections = {} }
	if type(payload) == "table" then
		if payload.sections ~= nil or payload.vars ~= nil or payload.links ~= nil then
			if type(payload.sections) == "table" then
				out.sections = payload.sections
			end
			if type(payload.vars) == "table" then
				out.vars = payload.vars
			end
			if type(payload.links) == "table" then
				out.links = payload.links
			end
		else
			out.sections = payload
		end
	end
	if makefile_path and makefile_path ~= "" then
		local stat = vim.loop.fs_stat(makefile_path)
		if stat then
			out.mtime = stat.mtime.sec
			out.size = stat.size
		end
	end
	if Parser.CacheUseHash then
		if not content and makefile_path and makefile_path ~= "" then
			content = read_makefile_content(makefile_path)
		end
		if content then
			local ok_hash, hash = pcall(vim.fn.sha256, content)
			if ok_hash then
				out.hash = hash
			end
		end
	end
	local encoded = encode_cache_payload(out)
	if not encoded then
		return
	end
	write_cache_file(cache_file, encoded)
end

---@param Content string|nil
---@return table<string, string>
function Parser.ParseVariables(Content, opts)
	if opts and opts.skip_cache then
		return parse_variables_raw(Content)
	end
	local cache_root, makefile_path = resolve_cache_paths(opts)
	local cached = nil
	local cache_file = nil
	if cache_root and cache_root ~= "" then
		local cache_opts = nil
		if not Parser.CacheLog and not (opts and opts.cache_log) then
			cache_opts = { silent = true }
		end
		cached, _, cache_file = try_load_cache(cache_root, makefile_path, Content, cache_opts)
	end
	if cached and type(cached.vars) == "table" then
		return cached.vars
	end
	local vars = parse_variables_raw(Content)
	if cached and cache_file then
		write_cache(cache_file, {
			sections = cached.sections,
			vars = vars,
			links = cached.links,
		}, makefile_path, Content)
	end
	return vars
end

---@param Content string|nil
---@return table[] groups, string[] individuals
function Parser.ParseLinkOptions(Content, opts)
	if opts and opts.skip_cache then
		return parse_links_block(Content)
	end
	local cache_root, makefile_path = resolve_cache_paths(opts)
	local cached = nil
	local cache_file = nil
	if cache_root and cache_root ~= "" then
		local cache_opts = nil
		if not Parser.CacheLog and not (opts and opts.cache_log) then
			cache_opts = { silent = true }
		end
		cached, _, cache_file = try_load_cache(cache_root, makefile_path, Content, cache_opts)
	end
	if cached and cached.links and cached.links.options then
		local options = cached.links.options
		return options.groups or {}, options.individuals or {}
	end
	local groups, individuals = parse_links_block(Content)
	if cached and cache_file then
		local links = cached.links or {}
		links.options = { groups = groups, individuals = individuals }
		write_cache(cache_file, {
			sections = cached.sections,
			vars = cached.vars,
			links = links,
		}, makefile_path, Content)
	end
	return groups, individuals
end

---@param Content string|nil
---@param RelativePath string
---@param opts table|string|nil
---@return string[]|nil
function Parser.GetCachedTargetLinks(Content, RelativePath, opts)
	local cache_root, makefile_path = resolve_cache_paths(opts)
	local cached = nil
	if cache_root and cache_root ~= "" then
		local cache_opts = nil
		if not Parser.CacheLog and not (opts and opts.cache_log) then
			cache_opts = { silent = true }
		end
		cached = (select(1, try_load_cache(cache_root, makefile_path, Content, cache_opts)))
	end
	if cached and cached.links and cached.links.targets then
		local entry = cached.links.targets[RelativePath]
		if entry and type(entry.flags) == "table" then
			return entry.flags
		end
	end
	return nil
end

---@class MarkerInfo
---@field M_start integer|nil
---@field M_end integer|nil
---@field type string|nil

---@param Content string
---@param RelativePath string
---@param CheckStart boolean
---@param CheckEnd boolean
---@return MarkerInfo
function Parser.FindMarker(Content, RelativePath, CheckStart, CheckEnd)
	local info = { M_start = nil, M_end = nil, type = nil }
	local escapedPath = Utils.EscapePattern(RelativePath)
	if not CheckStart then
		info.M_start = -1
	end
	if not CheckEnd then
		info.M_end = -1
	end

	if info.M_start == -1 and info.M_end == -1 then
		return info
	end

	local lines = normalize_lines(Content)
	for lineNumber, line in ipairs(lines) do
		local trimmedLine = line:match("^%s*(.-)%s*$")
		if not trimmedLine:match("^%s*#") or trimmedLine == "" then
			goto continue
		end
		if not info.M_start and CheckStart then
			local markerMatch = trimmedLine:match("^%s*#%s*marker_start%s*:%s*" .. escapedPath .. "(.*)$")
			if markerMatch then
				info.M_start = lineNumber
				-- Extract type if present
				local typeAnnotation = markerMatch:match("%s+type:(%S+)")
				if typeAnnotation then
					info.type = typeAnnotation
				end
				if not CheckEnd then
					return info
				end
			end
		end
		if not info.M_end and info.M_start and CheckEnd then
			if trimmedLine:match("^%s*#%s*marker_end%s*:%s*" .. escapedPath) then
				info.M_end = lineNumber
				return info
			end
		end
		::continue::
	end
	return info
end

---@class MarkerPair
---@field path string
---@field StartLine integer
---@field EndLine integer
---@field annotatedType string|nil

---@param Content string|nil
---@return MarkerPair[]
function Parser.FindAllMarkerPairs(Content)
	local allPairs = {}
	local openMarkers = {}
	local lines = normalize_lines(Content)
	if #lines == 0 then
		return allPairs
	end
	for lineNumber, line in ipairs(lines) do
		local trimmedLine = line:match("^%s*(.-)%s*$")
		if trimmedLine:match("^%s*#") then
			local startMatch = trimmedLine:match("^%s*#%s*marker_start%s*:%s*(.*)$")
			if startMatch then
				local path = startMatch:match("^(%S+)")
				local typeAnnotation = startMatch:match("%s+type:(%S+)")
				openMarkers[path] = { line = lineNumber, type = typeAnnotation }
			end
			local endPath = trimmedLine:match("^%s*#%s*marker_end%s*:%s*(.*)$")
			if endPath then
				endPath = endPath:match("^(%S+)")
				local markerData = openMarkers[endPath]
				if markerData then
					table.insert(allPairs, {
						path = endPath,
						StartLine = markerData.line,
						EndLine = lineNumber,
						annotatedType = markerData.type,
					})
					openMarkers[endPath] = nil
				end
			end
		end
	end
	return allPairs
end

---@param Content string
---@param StartLine integer
---@param EndLine integer
---@param ReturnTable boolean?
---@return string|string[]
function Parser.ReadContentBetweenLines(Content, StartLine, EndLine, ReturnTable)
	ReturnTable = not not ReturnTable
	local lines = normalize_lines(Content)
	return slice_lines(lines, StartLine, EndLine, ReturnTable)
end

---@param Content string
---@param RelativePath string
---@param ReturnTable boolean?
---@return string|string[]
function Parser.ReadContentBetweenMarkers(Content, RelativePath, ReturnTable)
	ReturnTable = not not ReturnTable
	local lines = normalize_lines(Content)
	local markerInfo = Parser.FindMarker(lines, RelativePath, true, true)
	local StartLine = markerInfo.M_start
	local EndLine = markerInfo.M_end
	if StartLine == -1 or EndLine == -1 then
		return ""
	end
	return slice_lines(lines, StartLine, EndLine, ReturnTable)
end

---@param Content string|nil
---@param RelativePath string
---@return boolean
function Parser.TargetExists(Content, RelativePath)
	if not Content then
		return false
	end
	local markerInfo = Parser.FindMarker(Content, RelativePath, true, false)
	return markerInfo.M_start ~= nil
end

---@param targetLine string
---@return string[]
function Parser.ParseDependencies(targetLine)
	local dependencies = {}

	local depString = targetLine:match("^[^:]*:%s*(.*)$")
	if not depString then
		return dependencies
	end

	for dep in depString:gmatch("%S+") do
		table.insert(dependencies, dep)
	end

	return dependencies
end

---@param sectionContent string
---@param baseName string|nil
---@return string|nil
function Parser.FindExecutableTargetName(sectionContent, baseName)
	local fallback = nil
	local escapedBase = baseName and Utils.EscapePattern(baseName) or nil
	for line in sectionContent:gmatch("[^\n]+") do
		local trimmedLine = line:match("^%s*(.-)%s*$")
		if trimmedLine == "" or trimmedLine:match("^#") then
			goto continue
		end
		if is_links_assignment_line(trimmedLine) then
			goto continue
		end

		local targetName = trimmedLine:match("^([^:]+):")
		if targetName then
			targetName = targetName:match("^%s*(.-)%s*$")
			if not targetName:match("%.o%s*$") and not targetName:match("^run") then
				if escapedBase then
					if
						targetName == baseName
						or targetName:match("/" .. escapedBase .. "$")
						or targetName:match("%$%(BUILD_DIR%)/" .. escapedBase .. "$")
						or targetName:match("%$%(BUILD_DIR%)/%$%(BUILD_MODE%)/" .. escapedBase .. "$")
					then
						return targetName
					end
				end
				fallback = fallback or targetName
			end
		end

		::continue::
	end

	return fallback
end

---@param sectionContent string
---@param targetName string
---@return string[]
function Parser.GetLinksForTarget(sectionContent, targetName)
	local links = {}
	if not targetName or targetName == "" then
		return links
	end

	local targetPattern = "^%s*" .. Utils.EscapePattern(targetName) .. "%s*:%s*LINKS%s*[%+:%?]?=%s*(.*)$"
	for line in sectionContent:gmatch("[^\n]+") do
		local trimmedLine = line:match("^%s*(.-)%s*$")
		local match = trimmedLine:match(targetPattern)
		if match then
			for flag in match:gmatch("%S+") do
				table.insert(links, flag)
			end
			return links
		end
	end

	return links
end

---@class TargetInfo
---@field name string
---@field dependencies string[]
---@field recipe string[]
---@field found boolean

---@param sectionContent string
---@param targetName string
---@return TargetInfo
function Parser.ParseTarget(sectionContent, targetName)
	local target = {
		name = targetName,
		dependencies = {},
		recipe = {},
		found = false,
	}

	local lines = {}
	for line in sectionContent:gmatch("[^\n]+") do
		table.insert(lines, line)
	end

	local targetPattern = "^" .. Utils.EscapePattern(targetName) .. "%s*:"
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local trimmedLine = line:match("^%s*(.-)%s*$")

		if trimmedLine:match(targetPattern) then
			if is_links_assignment_line(trimmedLine) then
				goto continue
			end
			target.found = true
			target.dependencies = Parser.ParseDependencies(trimmedLine)

			i = i + 1
			while i <= #lines do
				local nextLine = lines[i]
				if nextLine:match("^%s+") and not nextLine:match("^%s*#") then
					table.insert(target.recipe, nextLine:match("^%s*(.*)$"))
					i = i + 1
				else
					break
				end
			end
			break
		end
		::continue::
		i = i + 1
	end

	return target
end

---@param sectionContent string
---@param baseName string|nil
---@param annotatedType string|nil
---@return boolean hasObj
---@return boolean hasExecutable
---@return boolean hasRun
function Parser.DetectTargetTypes(sectionContent, baseName, annotatedType)
	local hasObj = false
	local hasExecutable = false
	local hasRun = false

	local searchFor = search_flags_for(annotatedType)
	local escapedBase = baseName and Utils.EscapePattern(baseName) or nil

	for line in sectionContent:gmatch("[^\n]+") do
		local trimmedLine = line:match("^%s*(.-)%s*$")

		if trimmedLine == "" or trimmedLine:match("^#") then
			goto continue
		end
		if is_links_assignment_line(trimmedLine) then
			goto continue
		end

		local targetName = trimmedLine:match("^([^:]+):")
		if targetName then
			targetName = targetName:match("^%s*(.-)%s*$")

			if searchFor.obj and not hasObj then
				if targetName:match("%.o$") or targetName:match("%.o%s*$") then
					hasObj = true
				end
			end

			if searchFor.executable and not hasExecutable then
				if escapedBase and (targetName == baseName or targetName:match("/" .. escapedBase .. "$")) then
					hasExecutable = true
				end
			end

			if searchFor.run and not hasRun then
				if
					escapedBase
					and (targetName == "run" .. baseName or targetName:match("/run" .. escapedBase .. "$"))
				then
					hasRun = true
				end
			end

			if
				(not searchFor.obj or hasObj)
				and (not searchFor.executable or hasExecutable)
				and (not searchFor.run or hasRun)
			then
				break
			end
		end

		::continue::
	end

	return hasObj, hasExecutable, hasRun
end

---@class SectionAnalysis
---@field hasObj boolean
---@field hasExecutable boolean
---@field hasRun boolean
---@field type string
---@field targets TargetInfo[]
---@field valid boolean
---@field error string|nil
---@field annotatedType string|nil

---@param sectionContent string
---@param baseName string|nil
---@param annotatedType string|nil
---@return SectionAnalysis
function Parser.AnalyzeSection(sectionContent, baseName, annotatedType)
	if not sectionContent or sectionContent == "" then
		return {
			hasObj = false,
			hasExecutable = false,
			hasRun = false,
			type = "empty",
			targets = {},
			valid = true,
			error = nil,
		}
	end

	local targets = {}
	local seen_targets = {}

	if not baseName then
		baseName = sectionContent:match("([^/]+)%.cpp") or ""
		baseName = baseName:gsub("%.cpp$", "")
	end

	local hasObj = false
	local hasExecutable = false
	local hasRun = false
	local searchFor = search_flags_for(annotatedType)
	local escapedBase = baseName ~= "" and Utils.EscapePattern(baseName) or nil

	local lines = vim.split(sectionContent, "\n", { plain = true })
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local trimmedLine = line:match("^%s*(.-)%s*$")

		if trimmedLine == "" or trimmedLine:match("^#") then
			i = i + 1
			goto continue
		end
		if is_links_assignment_line(trimmedLine) then
			i = i + 1
			goto continue
		end

		local targetName = trimmedLine:match("^([^:]+):")
		if not targetName then
			i = i + 1
			goto continue
		end

		targetName = targetName:match("^%s*(.-)%s*$")
		if not seen_targets[targetName] then
			if searchFor.obj and not hasObj and targetName:match("%.o%s*$") then
				hasObj = true
			end
			if searchFor.executable and not hasExecutable and escapedBase then
				if targetName == baseName or targetName:match("/" .. escapedBase .. "$") then
					hasExecutable = true
				end
			end
			if searchFor.run and not hasRun and escapedBase then
				if targetName == "run" .. baseName or targetName:match("/run" .. escapedBase .. "$") then
					hasRun = true
				end
			end

			local deps = Parser.ParseDependencies(trimmedLine)
			local recipe = {}
			local j = i + 1
			while j <= #lines do
				local nextLine = lines[j]
				if nextLine:match("^%s+") and not nextLine:match("^%s*#") then
					table.insert(recipe, nextLine:match("^%s*(.*)$"))
					j = j + 1
				else
					break
				end
			end

			table.insert(targets, {
				name = targetName,
				dependencies = deps,
				recipe = recipe,
				found = true,
			})
			seen_targets[targetName] = true
			i = j
			goto continue
		end

		i = i + 1
		::continue::
	end

	local inferredType
	if hasObj and hasExecutable and hasRun then
		inferredType = "full"
	elseif hasObj and hasExecutable then
		inferredType = "executable"
	elseif hasObj then
		inferredType = "obj"
	elseif hasRun then
		inferredType = "run"
	else
		inferredType = "unknown"
	end

	local valid = true
	local error = nil

	if annotatedType then
		local expectedTargets = {}

		if annotatedType == "full" then
			expectedTargets = { "obj", "executable", "run" }
		elseif annotatedType == "executable" then
			expectedTargets = { "obj", "executable" }
		elseif annotatedType == "obj" then
			expectedTargets = { "obj" }
		elseif annotatedType == "run" then
			expectedTargets = { "run" }
		end

		local missingTargets = {}
		for _, expected in ipairs(expectedTargets) do
			if expected == "obj" and not hasObj then
				table.insert(missingTargets, "object file (.o)")
			elseif expected == "executable" and not hasExecutable then
				table.insert(missingTargets, "executable")
			elseif expected == "run" and not hasRun then
				table.insert(missingTargets, "run target")
			end
		end

		if #missingTargets > 0 then
			valid = false
			error = string.format(
				"Type mismatch: marker specifies type '%s' but missing: %s",
				annotatedType,
				table.concat(missingTargets, ", ")
			)
		end
	end

	return {
		hasObj = hasObj,
		hasExecutable = hasExecutable,
		hasRun = hasRun,
		type = inferredType,
		targets = targets,
		valid = valid,
		error = error,
		annotatedType = annotatedType,
	}
end

---@param Content string
---@param opts table|nil
---@return { path: string, baseName: string|nil, startLine: integer, endLine: integer, analysis: SectionAnalysis }[]
function Parser.AnalyzeAllSections(Content, opts)
	local cache_root, makefile_path = resolve_cache_paths(opts)
	local cached, _, cache_file = try_load_cache(cache_root, makefile_path, Content)
	if cached and type(cached.sections) == "table" then
		return cached.sections
	end
	log_cache("MakeNvim cache miss (rebuild)")

	local lines = normalize_lines(Content)
	local allPairs = Parser.FindAllMarkerPairs(lines)
	local sectionAnalysis = {}
	local target_links = {}
	local vars = parse_variables_raw(Content or "")
	local groups, individuals = parse_links_block(Content or "")

	for _, pair in ipairs(allPairs) do
		local sectionContent = slice_lines(lines, pair.StartLine, pair.EndLine, false)

		local baseName = pair.path:match("([^/]+)%.cpp$")
		if baseName then
			baseName = baseName:gsub("%.cpp$", "")
		end

		local analysis = Parser.AnalyzeSection(sectionContent, baseName, pair.annotatedType)
		local target_name = Parser.FindExecutableTargetName(sectionContent, baseName)
		if target_name then
			target_links[pair.path] = {
				target = target_name,
				flags = Parser.GetLinksForTarget(sectionContent, target_name),
			}
		end

		if analysis.valid then
			table.insert(sectionAnalysis, {
				path = pair.path,
				baseName = baseName,
				startLine = pair.StartLine,
				endLine = pair.EndLine,
				analysis = analysis,
			})
		else
			Utils.Notify(string.format("Section error: %s (%s)", analysis.error, pair.path), vim.log.levels.ERROR)
		end
	end

	write_cache(cache_file, {
		sections = sectionAnalysis,
		vars = vars,
		links = {
			options = { groups = groups, individuals = individuals },
			targets = target_links,
		},
	}, makefile_path, Content)
	return sectionAnalysis
end

---@param Content string
---@param targetType string
---@return table[]
function Parser.GetSectionsByType(Content, targetType)
	local allSections = Parser.AnalyzeAllSections(Content)
	local filteredSections = {}

	for _, section in ipairs(allSections) do
		if section.analysis.type == targetType then
			table.insert(filteredSections, section)
		end
	end

	return filteredSections
end

---@param Content string
function Parser.PrintAnalysisSummary(Content)
	local allSections = Parser.AnalyzeAllSections(Content)
	local lines = normalize_lines(Content)

	vim.notify("Makefile Section Analysis:")
	vim.notify("=" .. string.rep("=", 50))

	for _, section in ipairs(allSections) do
		local analysis = section.analysis
		local sectionContent = slice_lines(lines, section.startLine, section.endLine, false)
		local exeTargetName = Parser.FindExecutableTargetName(sectionContent, section.baseName)
		local exeLinks = {}
		if exeTargetName then
			exeLinks = Parser.GetLinksForTarget(sectionContent, exeTargetName)
		end
		local function target_kind(name)
			if name:match("%.o%s*$") then
				return "obj"
			elseif name:match("^run") then
				return "run"
			end
			return "exe"
		end

		vim.notify(string.format("Path: %s", section.path))
		vim.notify(string.format("Base Name: %s", section.baseName or "N/A"))
		vim.notify(string.format("Type: %s", analysis.type))

		if analysis.annotatedType then
			vim.notify(string.format("Annotated Type: %s", analysis.annotatedType))
		end

		vim.notify(string.format("Has Object: %s", analysis.hasObj and "Yes" or "No"))
		vim.notify(string.format("Has Executable: %s", analysis.hasExecutable and "Yes" or "No"))
		vim.notify(string.format("Has Run: %s", analysis.hasRun and "Yes" or "No"))

		if #analysis.targets > 0 then
			vim.notify("Targets:")
			for _, target in ipairs(analysis.targets) do
				vim.notify(string.format("  - %s (%s)", target.name, target_kind(target.name)))
				if #target.dependencies > 0 then
					vim.notify(string.format("    Dependencies: %s", table.concat(target.dependencies, ", ")))
				end
				if #target.recipe > 0 then
					vim.notify("    Recipe:")
					for _, recipeLine in ipairs(target.recipe) do
						vim.notify(string.format("      %s", recipeLine))
					end
				end
				if exeTargetName and target.name == exeTargetName then
					if #exeLinks > 0 then
						vim.notify(string.format("    Links: %s", table.concat(exeLinks, " ")))
					else
						vim.notify("    Links: (none)")
					end
				end
			end
		end
		vim.notify(string.rep("-", 50))
	end
end

---@param Content string|nil
---@param MakefileVars MakefileVars
---@return boolean
function Parser.HasReqVars(Content, MakefileVars)
	if not Content then
		return false
	end
	local Variables = Parser.ParseVariables(Content)
	for VarName, _ in pairs(MakefileVars) do
		if not Variables[VarName] then
			return false
		end
	end
	return true
end

return Parser
