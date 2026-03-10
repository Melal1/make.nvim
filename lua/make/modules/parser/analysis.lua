local Utils = require("make.shared.utils")

local M = {}

---@param deps table
---@return table
function M.build(deps)
	local Cache = deps.cache -- cache module dependency
	local Markers = deps.markers -- marker parser dependency

	local function is_links_assignment_line(line)
		return line:match("^%s*[^:]+%s*:%s*LINKS%s*[%+:%?]?=") ~= nil -- detect "target: LINKS +=" lines
	end

	local function search_flags_for(annotatedType)
		local searchFor = { obj = true, executable = true, run = true } -- default to all target kinds
		if annotatedType then -- override based on marker annotation
			searchFor = { obj = false, executable = false, run = false } -- reset all flags
			if annotatedType == "full" then -- full means obj + exe + run
				searchFor.obj = true
				searchFor.executable = true
				searchFor.run = true
			elseif annotatedType == "executable" then -- executable means obj + exe
				searchFor.obj = true
				searchFor.executable = true
			elseif annotatedType == "obj" then -- obj only
				searchFor.obj = true
			elseif annotatedType == "run" then -- run only
				searchFor.run = true
			end
		end
		return searchFor -- return flag table
	end

	local function is_object_target_name(name)
		return name:match("%.o%s*$") ~= nil -- true if name ends with ".o"
	end

	local function build_key_matchers(target_key, opts)
		opts = opts or {} -- ensure options table
		local keys = {} -- target key(s) to match
		if target_key and target_key ~= "" then -- only add non-empty key
			table.insert(keys, target_key)
		end

		local escaped = {} -- pre-escaped patterns
		for _, key in ipairs(keys) do -- iterate keys
			escaped[key] = Utils.EscapePattern(key) -- escape for pattern matching
		end

		local function matches_exe(target_name)
			if #keys == 0 then -- no keys means no match
				return false
			end
			for _, key in ipairs(keys) do -- test each key
				local esc = escaped[key] -- fetch escaped pattern
				if target_name:match("%$%(BUILD_OUT%)/" .. esc .. "$") then -- match build out path
					return true
				end
			end
			return false -- nothing matched
		end

		local function matches_run(target_name)
			if opts.allow_run_prefix_any and target_name:match("^run") then -- allow any run* name
				return true
			end
			if #keys == 0 then -- no keys means only prefix rule applies
				return opts.allow_run_prefix and target_name:match("^run") ~= nil or false
			end
			for _, key in ipairs(keys) do -- test each key
				local esc = escaped[key] -- fetch escaped pattern
				if target_name:match("^run") and target_name:match(esc .. "$") then -- run + key suffix match
					return true
				end
			end
			return false -- nothing matched
		end

		return matches_exe, matches_run -- return matcher functions
	end

	local function target_kind(target_name, target_key, opts)
		if not target_name or target_name == "" then -- invalid name
			return nil
		end
		if is_object_target_name(target_name) then -- object target
			return "obj"
		end
		local matches_exe, matches_run = build_key_matchers(target_key, opts) -- build matchers
		if matches_run(target_name) then -- run target
			return "run"
		end
		if matches_exe(target_name) then -- executable target
			return "exe"
		end
		if opts and opts.allow_fallback_exe then -- optionally assume exe
			return "exe"
		end
		return "other" -- unknown kind
	end

	local function ParseDependencies(targetLine)
		local dependencies = {} -- collected deps

		local depString = targetLine:match("^[^:]*:%s*(.*)$") -- capture dependencies after ':'
		if not depString then -- no deps section
			return dependencies
		end

		for dep in depString:gmatch("%S+") do -- split on whitespace
			table.insert(dependencies, dep)
		end

		return dependencies -- return list
	end

	local function FindExecutableTargetName(sectionContent, _baseName, targetKey)
		if not targetKey or targetKey == "" then -- no key to match
			return nil
		end

		for line in sectionContent:gmatch("[^\n]+") do -- iterate section lines
			local trimmedLine = line:match("^%s*(.-)%s*$") -- trim whitespace
			if trimmedLine == "" or trimmedLine:match("^#") then -- skip empty/comment
				goto continue
			end
			if is_links_assignment_line(trimmedLine) then -- skip LINKS assignment
				goto continue
			end

			local targetName = trimmedLine:match("^([^:]+):") -- capture target before ':'
			if targetName then
				targetName = targetName:match("^%s*(.-)%s*$") -- trim target name
				if target_kind(targetName, targetKey) == "exe" then -- found executable
					return targetName
				end
			end

			::continue:: -- label for loop continue
		end

		return nil -- nothing found
	end

	local function GetLinksForTarget(sectionContent, targetName)
		local links = {} -- collected flags
		if not targetName or targetName == "" then -- invalid name
			return links
		end

		local targetPattern = "^%s*" .. Utils.EscapePattern(targetName) .. "%s*:%s*LINKS%s*[%+:%?]?=%s*(.*)$" -- match LINKS line
		for line in sectionContent:gmatch("[^\n]+") do -- iterate section lines
			local trimmedLine = line:match("^%s*(.-)%s*$") -- trim whitespace
			local match = trimmedLine:match(targetPattern) -- capture flags string
			if match then
				for flag in match:gmatch("%S+") do -- split into flags
					table.insert(links, flag)
				end
				return links -- return on first match
			end
		end

		return links -- no links found
	end

	local function ParseTarget(sectionContent, targetName)
		local target = { -- target info
			name = targetName,
			dependencies = {},
			recipe = {},
			found = false,
		}

		local lines = {} -- section lines
		for line in sectionContent:gmatch("[^\n]+") do -- split lines
			table.insert(lines, line)
		end

		local targetPattern = "^" .. Utils.EscapePattern(targetName) .. "%s*:" -- match exact target line
		local i = 1 -- line index
		while i <= #lines do -- loop lines
			local line = lines[i] -- current line
			local trimmedLine = line:match("^%s*(.-)%s*$") -- trim whitespace

			if trimmedLine:match(targetPattern) then -- found target line
				if is_links_assignment_line(trimmedLine) then -- ignore LINKS assignment line
					goto continue
				end
				target.found = true -- mark found
				target.dependencies = ParseDependencies(trimmedLine) -- parse deps

				i = i + 1 -- move to recipe lines
				while i <= #lines do -- consume recipe lines
					local nextLine = lines[i] -- next line
					if nextLine:match("^%s+") and not nextLine:match("^%s*#") then -- indented non-comment
						table.insert(target.recipe, nextLine:match("^%s*(.*)$")) -- add recipe line
						i = i + 1 -- advance
					else
						break -- stop on non-recipe
					end
				end
				break -- stop after first target
			end
			::continue:: -- label for loop continue
			i = i + 1 -- advance
		end

		return target -- return parsed target
	end

	local function ScanTargets(sectionContent, opts)
		opts = opts or {} -- ensure options
		local annotatedType = opts.annotatedType -- requested type filter
		local targetKey = opts.targetKey -- key for matching
		local searchFor = search_flags_for(annotatedType) -- flags to search
		local targets = {} -- collected targets
		local seen_targets = {} -- dedupe map

		local hasObj = false -- saw object target
		local hasExecutable = false -- saw executable target
		local hasRun = false -- saw run target

		local lines = vim.split(sectionContent or "", "\n", { plain = true }) -- split lines
		local i = 1 -- line index
		while i <= #lines do -- iterate lines
			local line = lines[i] -- current line
			local trimmedLine = line:match("^%s*(.-)%s*$") -- trim whitespace

			if trimmedLine == "" or trimmedLine:match("^#") then -- skip empty/comment
				i = i + 1
				goto continue
			end
			if is_links_assignment_line(trimmedLine) then -- skip LINKS assignment
				i = i + 1
				goto continue
			end

			local targetName = trimmedLine:match("^([^:]+):") -- capture target before ':'
			if not targetName then -- no target line
				i = i + 1
				goto continue
			end

			targetName = targetName:match("^%s*(.-)%s*$") -- trim target name
			if not seen_targets[targetName] then -- process only first occurrence
				local kind = target_kind(targetName, targetKey) -- determine kind
				if searchFor.obj and not hasObj and kind == "obj" then -- update obj flag
					hasObj = true
				end
				if searchFor.executable and not hasExecutable and kind == "exe" then -- update exe flag
					hasExecutable = true
				end
				if searchFor.run and not hasRun and kind == "run" then -- update run flag
					hasRun = true
				end

				local dependencies = ParseDependencies(trimmedLine) -- parse deps
				local recipe = {} -- recipe lines
				local j = i + 1 -- next line index
				while j <= #lines do -- scan for recipe lines
					local nextLine = lines[j] -- candidate line
					if nextLine:match("^%s+") and not nextLine:match("^%s*#") then -- indented non-comment
						table.insert(recipe, nextLine:match("^%s*(.*)$")) -- add recipe
						j = j + 1 -- advance
					else
						break -- stop on non-recipe
					end
				end

				table.insert(targets, { -- store target entry
					name = targetName,
					dependencies = dependencies,
					recipe = recipe,
					found = true,
					kind = kind,
				})
				seen_targets[targetName] = true -- mark as seen
				i = j -- skip recipe lines
				goto continue
			end

			i = i + 1 -- advance
			::continue:: -- label for loop continue
		end

		return targets, hasObj, hasExecutable, hasRun -- return targets and flags
	end

	local function DetectTargetTypes(sectionContent, _baseName, annotatedType, targetKey)
		local _, hasObj, hasExecutable, hasRun = ScanTargets(sectionContent, { -- scan for types
			annotatedType = annotatedType,
			targetKey = targetKey,
		})
		return hasObj, hasExecutable, hasRun -- return type flags
	end

	local function AnalyzeSection(sectionContent, baseName, annotatedType, targetKey)
		if not sectionContent or sectionContent == "" then -- empty section
			return { -- return empty analysis
				hasObj = false,
				hasExecutable = false,
				hasRun = false,
				type = "empty",
				targets = {},
				valid = true,
				error = nil,
			}
		end

		if not baseName then -- infer baseName from path
			baseName = sectionContent:match("([^/]+)%.cpp") or ""
			baseName = baseName:gsub("%.cpp$", "")
		end

		local targets, hasObj, hasExecutable, hasRun = ScanTargets(sectionContent, { -- scan targets
			annotatedType = annotatedType,
			targetKey = targetKey,
		})

		local inferredType -- type inferred from targets
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

		local valid = true -- validity flag
		local error = nil -- error message

		if annotatedType then -- validate against annotation
			local expectedTargets = {} -- expected kinds

			if annotatedType == "full" then
				expectedTargets = { "obj", "executable", "run" }
			elseif annotatedType == "executable" then
				expectedTargets = { "obj", "executable" }
			elseif annotatedType == "obj" then
				expectedTargets = { "obj" }
			elseif annotatedType == "run" then
				expectedTargets = { "run" }
			end

			local missingTargets = {} -- collect missing kinds
			for _, expected in ipairs(expectedTargets) do -- check each expectation
				if expected == "obj" and not hasObj then
					table.insert(missingTargets, "object file (.o)")
				elseif expected == "executable" and not hasExecutable then
					table.insert(missingTargets, "executable")
				elseif expected == "run" and not hasRun then
					table.insert(missingTargets, "run target")
				end
			end

			if #missingTargets > 0 then -- mark invalid if missing
				valid = false
				error = string.format(
					"Type mismatch: marker specifies type '%s' but missing: %s",
					annotatedType,
					table.concat(missingTargets, ", ")
				)
			end
		end

		return { -- return analysis result
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

	local function AnalyzeAllSections(Content, opts)
		local cache_root, makefile_path = Cache.resolve_cache_paths(opts) -- resolve cache paths
		local cached, _, cache_file = Cache.try_load_cache(cache_root, makefile_path) -- attempt cache load
		if cached and type(cached.sections) == "table" then -- cache hit
			return cached.sections
		end
		local lines = Markers.normalize_lines(Content) -- normalize content into lines
		local allPairs = Markers.FindAllMarkerPairs(lines) -- find all marker sections
		local sectionAnalysis = {} -- collected analyses
		local target_links = {} -- map of target links
		local vars = Cache.ParseVariables(Content or "", { skip_cache = true }) -- parse vars without cache
		local groups, individuals = Cache.ParseLinkOptions(Content or "", { skip_cache = true }) -- parse links without cache

		for _, pair in ipairs(allPairs) do -- analyze each section
			local sectionContent = Markers.slice_lines(lines, pair.StartLine, pair.EndLine, false) -- slice section lines

			local baseName = pair.path:match("([^/]+)%.cpp$") -- infer base name from path
			if baseName then
				baseName = baseName:gsub("%.cpp$", "")
			end
			local targetKey = pair.name or Utils.FlattenRelativePath(pair.path) -- target key for matching

			local analysis = AnalyzeSection(sectionContent, baseName, pair.annotatedType, targetKey) -- analyze section
			local target_name = FindExecutableTargetName(sectionContent, baseName, targetKey) -- find executable target
			if target_name then
				target_links[pair.path] = { -- record link flags
					target = target_name,
					flags = GetLinksForTarget(sectionContent, target_name),
				}
			end

			if analysis.valid then -- add valid analysis
				table.insert(sectionAnalysis, {
					path = pair.path,
					baseName = baseName,
					targetKey = targetKey,
					startLine = pair.StartLine,
					endLine = pair.EndLine,
					analysis = analysis,
				})
			else -- notify on invalid section
				Utils.Notify(string.format("Section error: %s (%s)", analysis.error, pair.path), vim.log.levels.ERROR)
			end
		end

		Cache.write_cache(cache_file, { -- write cache payload
			sections = sectionAnalysis,
			vars = vars,
			links = {
				options = { groups = groups, individuals = individuals },
				targets = target_links,
			},
		}, makefile_path, Content)
		return sectionAnalysis -- return analyses
	end

	local function GetSectionsByType(Content, targetType)
		local allSections = AnalyzeAllSections(Content) -- analyze all sections
		local filteredSections = {} -- filtered result

		for _, section in ipairs(allSections) do -- filter by type
			if section.analysis.type == targetType then
				table.insert(filteredSections, section)
			end
		end

		return filteredSections -- return filtered list
	end

	return { -- exported analysis API
		ParseDependencies = ParseDependencies,
		ParseTarget = ParseTarget,
		FindExecutableTargetName = FindExecutableTargetName,
		GetLinksForTarget = GetLinksForTarget,
		DetectTargetTypes = DetectTargetTypes,
		AnalyzeSection = AnalyzeSection,
		AnalyzeAllSections = AnalyzeAllSections,
		GetSectionsByType = GetSectionsByType,
		ScanTargets = ScanTargets,
		TargetKind = target_kind,
		IsObjectTargetName = is_object_target_name,
	}
end

return M
