local LinksParse = require("make.modules.links.parse") -- link block parser
local uv = vim.uv or vim.loop -- libuv handle for stat calls

---@class MakeCacheState
---@field CacheRoot string|nil
---@field CacheMakefilePath string|nil
---@field CacheLog boolean
---@field CacheFormat MakeCacheFormat|nil
---@field CacheDir string|nil

---@class MakeCacheOpts
---@field skip_cache? boolean

---@class MakeCacheLinksOptions
---@field groups table
---@field individuals table

---@class MakeCacheLinksTarget
---@field target string
---@field flags string[]

---@class MakeCacheLinks
---@field options? MakeCacheLinksOptions
---@field targets? table<string, MakeCacheLinksTarget>

---@class MakeCachePayload
---@field sections table
---@field vars? table<string, string>
---@field links? MakeCacheLinks
---@field mtime? integer
---@field size? integer

---@class MakeCacheApi
---@field SetCacheRoot fun(root_path: string|nil, makefile_path: string|nil)
---@field ParseVariables fun(Content: string|nil, opts?: MakeCacheOpts): table<string, string>
---@field ParseLinkOptions fun(Content: string|nil, opts?: MakeCacheOpts): table, table
---@field GetCachedTargetLinks fun(Content: string|nil, RelativePath: string, opts?: MakeCacheOpts): string[]|nil
---@field resolve_cache_paths fun(opts?: MakeCacheOpts): string|nil, string|nil
---@field try_load_cache fun(root_path: string|nil, makefile_path: string|nil, opts?: MakeCacheOpts): MakeCachePayload|nil, string|nil, string|nil
---@field write_cache fun(cache_file: string|nil, payload: MakeCachePayload|table|nil, makefile_path: string|nil, Content?: string|nil)

local M = {} -- module table

---@param state MakeCacheState
---@return MakeCacheApi
function M.setup(state) -- build cache helpers bound to config
	-- Cache strategy: disk-only, validated by Makefile mtime/size

	-- Resolve the expanded cache directory path from current config.
	---@return string
	local function resolve_cache_dir()
		local dir = state.CacheDir
		if not dir or dir == "" then
			dir = ".cache/make.nvim"
		end
		if not dir:match("^/") and not dir:match("^~") then -- convert relative to home-based
			dir = "~/" .. dir
		end
		return vim.fn.expand(dir)
	end

	-- Create a filesystem-safe cache key from a root path.
	local function cache_key_for(root_path)
		local normalized = vim.fn.fnamemodify(root_path or "", ":p") -- normalize to absolute path
		normalized = normalized:gsub("^/", "") -- trim leading slash
		if normalized == "" then
			return "default"
		end
		-- normalized = normalized:gsub("\\", "/") -- normalize Windows separators
		normalized = normalized:gsub(":", "_") -- replace drive separator
		normalized = normalized:gsub("/", "_") -- replace path separators
		return normalized
	end

	-- Pick cache encoding format based on config.
	local function cache_format()
		local fmt = (state.CacheFormat or "mpack"):lower()
		if fmt == "mpack" then
			return "mpack"
		end
		return "luabytecode"
	end

	-- Build the full cache file path for a given root.
	local function make_cache_file_path(root_path)
		local base = resolve_cache_dir()
		local ext = cache_format() == "luabytecode" and ".luac" or ".mpack"
		return base .. "/" .. cache_key_for(root_path) .. ext
	end

	-- Read cache file bytes from disk (or nil on failure).
	local function read_cache_file(cache_file)
		local file = io.open(cache_file, "rb") -- r (Read) b bin
		if not file then -- open failed
			return nil
		end
		local content = file:read("*a") -- read entire file
		file:close()
		if not content or content == "" then -- empty content treated as miss
			return nil
		end
		return content
	end

	-- Write cache bytes to disk (returns success).
	local function write_cache_file(cache_file, content)
		if content then
			local file = io.open(cache_file, "wb")
			if not file then
				return false
			end
			file:write(content)
			file:close()
			return true
		else
			return false
		end
	end

	-- Emit cache log messages when enabled.
	local function log_cache(message, opts)
		if not state.CacheLog or (opts and opts.silent) then -- logging disabled or silent
			return
		end
		vim.notify(message, vim.log.levels.DEBUG)
	end

	-- Serialize a Lua table into source for bytecode caching.
	local function serialize_lua_value(value, seen)
		local t = type(value)
		if t == "string" then
			return string.format("%q", value)
		elseif t == "number" or t == "boolean" then
			return tostring(value)
		elseif t == "table" then
			if seen[value] then -- guard against cycles
				return "nil"
			end
			seen[value] = true -- mark table as visited
			local parts = {} -- hold serialized array + map entries
			local idx = 0 -- manual index to avoid table.insert overhead
			for _, item in ipairs(value) do -- serialize array-like part in order
				idx = idx + 1
				parts[idx] = serialize_lua_value(item, seen)
			end
			for k, v in pairs(value) do -- serialize non-array keys
				local is_array = type(k) == "number" and k >= 1 and k <= #value and math.floor(k) == k
				if not is_array then
					local key
					if type(k) == "string" and k:match("^[%a_][%w_]*$") then
						key = k -- bare identifier key
					else
						key = "[" .. serialize_lua_value(k, seen) .. "]" -- complex key
					end
					idx = idx + 1
					parts[idx] = key .. " = " .. serialize_lua_value(v, seen)
				end
			end
			seen[value] = nil -- unmark to allow reuse in other branches
			return "{" .. table.concat(parts, ", ") .. "}" -- assemble table literal
		end
		return "nil" -- unsupported types serialize as nil
	end

	-- Encode the cache payload to bytecode or msgpack.
	local function encode_cache_payload(payload)
		if cache_format() == "luabytecode" then
			local source = "return " .. serialize_lua_value(payload, {})
			local chunk = load(source, "make.nvim cache", "t") -- compile as text chunk
			if not chunk then
				return nil
			end
			return string.dump(chunk, true)
		end
		local ok_encode, encoded = pcall(vim.mpack.encode, payload) -- encode to msgpack
		if not ok_encode or not encoded then
			return nil
		end
		return encoded
	end

	-- Decode cache bytes back into a Lua table.
	local function decode_cache_payload(raw) -- deserialize bytes to table
		if cache_format() == "luabytecode" then -- bytecode format
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
		local ok_decode, decoded = pcall(vim.mpack.decode, raw) -- decode msgpack
		if not ok_decode or not decoded then
			return nil
		end
		return decoded
	end

	-- Resolve cache_root and makefile_path from state only.
	---@return string|nil, string|nil
	local function resolve_cache_paths() -- compute cache root + makefile path
		return state.CacheRoot, state.CacheMakefilePath
	end

	-- Load, decode, and validate cache from disk (mtime/size).
	local function try_load_cache(root_path, makefile_path, opts)
		local cache_root = root_path
		local cache_file = make_cache_file_path(cache_root)
		if not uv.fs_stat(cache_file) then -- cache file missing
			return nil, nil, cache_file
		end

		local raw = read_cache_file(cache_file)
		if not raw or raw == "" then -- empty cache
			return nil, nil, cache_file
		end

		local decoded = decode_cache_payload(raw)
		if not decoded or type(decoded.sections) ~= "table" then
			return nil, nil, cache_file
		end

		local stat = uv.fs_stat(makefile_path) -- stat makefile
		if stat and decoded.mtime == stat.mtime.sec and decoded.size == stat.size then -- mtime/size match
			log_cache("MakeNvim cache hit (mtime/size)", opts) -- log hit
			return decoded, nil, cache_file
		else
			log_cache("MakeNvim cache miss (mtime/size changed)", opts) -- log miss
			return nil, nil, cache_file
		end
	end

	-- Write cache to disk with normalized payload + Makefile metadata.
	local function write_cache(cache_file, payload, makefile_path)
		if not cache_file then -- no path to write
			return
		end
		local dir = resolve_cache_dir()
		if not dir or dir == "" then
			return
		end
		vim.fn.mkdir(dir, "p") -- ensure directory exists
		local out = { sections = {} } -- normalized output payload
		if type(payload) == "table" then -- handle table payload
			if payload.sections ~= nil or payload.vars ~= nil or payload.links ~= nil then -- structured payload
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
				out.sections = payload -- treat payload as sections list
			end
		end
		if makefile_path and makefile_path ~= "" then -- attach metadata when available
			local stat = uv.fs_stat(makefile_path)
			if stat then
				out.mtime = stat.mtime.sec -- store mtime seconds
				out.size = stat.size -- store file size
			end
		end
		local encoded = encode_cache_payload(out) -- encode payload
		if not encoded then
			return
		end
		write_cache_file(cache_file, encoded)
	end

	-- Parse variables without caching, from markers.
	local function parse_variables_raw(Content)
		local Variables = {}
		if not Content then
			return Variables
		end
		for Line in Content:gmatch("[^\n]+") do -- iterate lines
			Line = Line:match("^%s*(.-)%s*$") -- trim whitespace
			if Line and Line ~= "" and not Line:match("^#") then -- skip empty/comments
				local VarName, VarValue = Line:match("^([%w_]+)%s*:?=%s*(.*)$") -- parse assignment
				if VarName and VarValue then
					Variables[VarName] = VarValue -- store variable
				end
			end
		end
		return Variables
	end

	-- Store default cache root/makefile path in state.
	local function SetCacheRoot(root_path, makefile_path)
		if root_path and root_path ~= "" then
			state.CacheRoot = root_path
		end
		if makefile_path and makefile_path ~= "" then
			state.CacheMakefilePath = makefile_path
		end
	end

	-- Parse Makefile variables with cache fallback.
	local function ParseVariables(Content, opts)
		if opts and opts.skip_cache then -- skip cache if requested
			return parse_variables_raw(Content)
		end
		local cache_root, makefile_path = resolve_cache_paths()
		local cached = nil -- cache payload
		local cache_file = nil
		cached, _, cache_file = try_load_cache(cache_root, makefile_path, opts) -- try cache
		if cached and type(cached.vars) == "table" then
			return cached.vars
		end
		local vars = parse_variables_raw(Content)
		if cached and cache_file then -- refresh cache with new vars
			write_cache(cache_file, {
				sections = cached.sections,
				vars = vars,
				links = cached.links,
			}, makefile_path)
		end
		return vars
	end

	-- Parse links block with cache fallback.
	local function ParseLinkOptions(Content, opts) -- parse links with cache
		if opts and opts.skip_cache then -- skip cache if requested
			return LinksParse.parse_links_block(Content)
		end
		local cache_root, makefile_path = resolve_cache_paths() -- resolve paths
		local cached = nil -- cache payload
		local cache_file = nil -- cache file path
		if cache_root and cache_root ~= "" then -- only when root is valid
			cached, _, cache_file = try_load_cache(cache_root, makefile_path, opts) -- try cache
		end
		if cached and cached.links and cached.links.options then -- return cached links
			local options = cached.links.options
			return options.groups or {}, options.individuals or {}
		end
		local groups, individuals = LinksParse.parse_links_block(Content) -- parse raw links
		if cached and cache_file then -- refresh cache with new links
			local links = cached.links or {}
			links.options = { groups = groups, individuals = individuals }
			write_cache(cache_file, { -- write combined payload
				sections = cached.sections,
				vars = cached.vars,
				links = links,
			}, makefile_path)
		end
		return groups, individuals -- return parsed links
	end

	-- Fetch cached per-target link flags (if available).
	local function GetCachedTargetLinks(_Content, RelativePath, opts) -- get cached link flags
		local cache_root, makefile_path = resolve_cache_paths() -- resolve paths
		local cached = nil -- cache payload
		if cache_root and cache_root ~= "" then -- only when root is valid
			cached = (select(1, try_load_cache(cache_root, makefile_path, opts))) -- try cache
		end
		if cached and cached.links and cached.links.targets then -- read cached target links
			local entry = cached.links.targets[RelativePath] -- lookup by relative path
			if entry and type(entry.flags) == "table" then -- validate entry
				return entry.flags -- return flags list
			end
		end
		return nil -- cache miss
	end

	return { -- exported cache API
		SetCacheRoot = SetCacheRoot,
		ParseVariables = ParseVariables,
		ParseLinkOptions = ParseLinkOptions,
		GetCachedTargetLinks = GetCachedTargetLinks,
		resolve_cache_paths = resolve_cache_paths,
		try_load_cache = try_load_cache,
		write_cache = write_cache,
	}
end

return M -- export module
