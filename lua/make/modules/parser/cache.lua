local Utils = require("make.shared.utils")
local LinksParse = require("make.modules.links.parse")
local uv = vim.uv or vim.loop

local M = {}

---@param state table
function M.setup(state)
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
		local fmt = (state.CacheFormat or "mpack"):lower()
		if fmt == "luabytecode" or fmt == "bytecode" or fmt == "luac" then
			return "luabytecode"
		end
		return "mpack"
	end

	local function cache_file_for(root_path)
		local dir = state.CacheDir or ".cache/make.nvim"
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
		if not state.CacheLog or (opts and opts.silent) then
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
		makefile_path = makefile_path or state.CacheMakefilePath
		root_path = root_path or state.CacheRoot or vim.fn.getcwd()
		if (not makefile_path or makefile_path == "") and root_path and root_path ~= "" then
			local candidate = root_path .. "/Makefile"
			if uv.fs_stat(candidate) then
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
		local cache_stat = uv.fs_stat(cache_file)
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
			local stat = uv.fs_stat(makefile_path)
			if stat and decoded.mtime == stat.mtime.sec and decoded.size == stat.size then
				log_cache("MakeNvim cache hit (mtime/size)", opts)
				return decoded
			end
			if not state.CacheUseHash then
				log_cache("MakeNvim cache miss (mtime/size changed)", opts)
				return nil, nil, cache_file
			end
		end

		if not state.CacheUseHash then
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
		local dir = state.CacheDir or ".cache/make.nvim"
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
			local stat = uv.fs_stat(makefile_path)
			if stat then
				out.mtime = stat.mtime.sec
				out.size = stat.size
			end
		end
		if state.CacheUseHash then
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

	local function SetCacheRoot(root_path, makefile_path)
		if root_path and root_path ~= "" then
			state.CacheRoot = root_path
		end
		if makefile_path and makefile_path ~= "" then
			state.CacheMakefilePath = makefile_path
		end
	end

	local function ParseVariables(Content, opts)
		if opts and opts.skip_cache then
			return parse_variables_raw(Content)
		end
		local cache_root, makefile_path = resolve_cache_paths(opts)
		local cached = nil
		local cache_file = nil
		if cache_root and cache_root ~= "" then
			local cache_opts = nil
			if not state.CacheLog and not (opts and opts.cache_log) then
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

	local function ParseLinkOptions(Content, opts)
		if opts and opts.skip_cache then
			return LinksParse.parse_links_block(Content)
		end
		local cache_root, makefile_path = resolve_cache_paths(opts)
		local cached = nil
		local cache_file = nil
		if cache_root and cache_root ~= "" then
			local cache_opts = nil
			if not state.CacheLog and not (opts and opts.cache_log) then
				cache_opts = { silent = true }
			end
			cached, _, cache_file = try_load_cache(cache_root, makefile_path, Content, cache_opts)
		end
		if cached and cached.links and cached.links.options then
			local options = cached.links.options
			return options.groups or {}, options.individuals or {}
		end
		local groups, individuals = LinksParse.parse_links_block(Content)
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

	local function GetCachedTargetLinks(Content, RelativePath, opts)
		local cache_root, makefile_path = resolve_cache_paths(opts)
		local cached = nil
		if cache_root and cache_root ~= "" then
			local cache_opts = nil
			if not state.CacheLog and not (opts and opts.cache_log) then
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

	return {
		SetCacheRoot = SetCacheRoot,
		ParseVariables = ParseVariables,
		ParseLinkOptions = ParseLinkOptions,
		GetCachedTargetLinks = GetCachedTargetLinks,
		resolve_cache_paths = resolve_cache_paths,
		try_load_cache = try_load_cache,
		write_cache = write_cache,
	}
end

return M
