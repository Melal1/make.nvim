local Utils = require("make.shared.utils")

local M = {}

---@param deps table
---@return table
function M.build(deps)
	local Cache = deps.cache
	local Markers = deps.markers

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

	local function is_object_target_name(name)
		return name:match("%.o%s*$") ~= nil
	end

	local function build_key_matchers(target_key, opts)
		opts = opts or {}
		local keys = {}
		if target_key and target_key ~= "" then
			table.insert(keys, target_key)
		end

		local escaped = {}
		for _, key in ipairs(keys) do
			escaped[key] = Utils.EscapePattern(key)
		end

		local function matches_exe(target_name)
			if #keys == 0 then
				return false
			end
			for _, key in ipairs(keys) do
				local esc = escaped[key]
				if target_name:match("%$%(BUILD_OUT%)/" .. esc .. "$") then
					return true
				end
			end
			return false
		end

		local function matches_run(target_name)
			if opts.allow_run_prefix_any and target_name:match("^run") then
				return true
			end
			if #keys == 0 then
				return opts.allow_run_prefix and target_name:match("^run") ~= nil or false
			end
			for _, key in ipairs(keys) do
				local esc = escaped[key]
				if target_name:match("^run") and target_name:match(esc .. "$") then
					return true
				end
			end
			return false
		end

		return matches_exe, matches_run
	end

	local function target_kind(target_name, target_key, opts)
		if not target_name or target_name == "" then
			return nil
		end
		if is_object_target_name(target_name) then
			return "obj"
		end
		local matches_exe, matches_run = build_key_matchers(target_key, opts)
		if matches_run(target_name) then
			return "run"
		end
		if matches_exe(target_name) then
			return "exe"
		end
		if opts and opts.allow_fallback_exe then
			return "exe"
		end
		return "other"
	end

	local function ParseDependencies(targetLine)
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

	local function FindExecutableTargetName(sectionContent, baseName, targetKey)
		if not targetKey or targetKey == "" then
			return nil
		end

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
				if target_kind(targetName, targetKey) == "exe" then
					return targetName
				end
			end

			::continue::
		end

		return nil
	end

	local function GetLinksForTarget(sectionContent, targetName)
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

	local function ParseTarget(sectionContent, targetName)
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
				target.dependencies = ParseDependencies(trimmedLine)

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

	local function ScanTargets(sectionContent, opts)
		opts = opts or {}
		local annotatedType = opts.annotatedType
		local targetKey = opts.targetKey
		local searchFor = search_flags_for(annotatedType)
		local targets = {}
		local seen_targets = {}

		local hasObj = false
		local hasExecutable = false
		local hasRun = false

		local lines = vim.split(sectionContent or "", "\n", { plain = true })
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
				local kind = target_kind(targetName, targetKey)
				if searchFor.obj and not hasObj and kind == "obj" then
					hasObj = true
				end
				if searchFor.executable and not hasExecutable and kind == "exe" then
					hasExecutable = true
				end
				if searchFor.run and not hasRun and kind == "run" then
					hasRun = true
				end

				local deps = ParseDependencies(trimmedLine)
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
					kind = kind,
				})
				seen_targets[targetName] = true
				i = j
				goto continue
			end

			i = i + 1
			::continue::
		end

		return targets, hasObj, hasExecutable, hasRun
	end

	local function DetectTargetTypes(sectionContent, baseName, annotatedType, targetKey)
		local _, hasObj, hasExecutable, hasRun = ScanTargets(sectionContent, {
			annotatedType = annotatedType,
			targetKey = targetKey,
		})
		return hasObj, hasExecutable, hasRun
	end

	local function AnalyzeSection(sectionContent, baseName, annotatedType, targetKey)
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

		if not baseName then
			baseName = sectionContent:match("([^/]+)%.cpp") or ""
			baseName = baseName:gsub("%.cpp$", "")
		end

		local targets, hasObj, hasExecutable, hasRun = ScanTargets(sectionContent, {
			annotatedType = annotatedType,
			targetKey = targetKey,
		})

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

	local function AnalyzeAllSections(Content, opts)
		local cache_root, makefile_path = Cache.resolve_cache_paths(opts)
		local cached, _, cache_file = Cache.try_load_cache(cache_root, makefile_path, Content)
		if cached and type(cached.sections) == "table" then
			return cached.sections
		end
		local lines = Markers.normalize_lines(Content)
		local allPairs = Markers.FindAllMarkerPairs(lines)
		local sectionAnalysis = {}
		local target_links = {}
		local vars = Cache.ParseVariables(Content or "", { skip_cache = true })
		local groups, individuals = Cache.ParseLinkOptions(Content or "", { skip_cache = true })

		for _, pair in ipairs(allPairs) do
			local sectionContent = Markers.slice_lines(lines, pair.StartLine, pair.EndLine, false)

			local baseName = pair.path:match("([^/]+)%.cpp$")
			if baseName then
				baseName = baseName:gsub("%.cpp$", "")
			end
			local targetKey = pair.name or Utils.FlattenRelativePath(pair.path)

			local analysis = AnalyzeSection(sectionContent, baseName, pair.annotatedType, targetKey)
			local target_name = FindExecutableTargetName(sectionContent, baseName, targetKey)
			if target_name then
				target_links[pair.path] = {
					target = target_name,
					flags = GetLinksForTarget(sectionContent, target_name),
				}
			end

			if analysis.valid then
				table.insert(sectionAnalysis, {
					path = pair.path,
					baseName = baseName,
					targetKey = targetKey,
					startLine = pair.StartLine,
					endLine = pair.EndLine,
					analysis = analysis,
				})
			else
				Utils.Notify(string.format("Section error: %s (%s)", analysis.error, pair.path), vim.log.levels.ERROR)
			end
		end

		Cache.write_cache(cache_file, {
			sections = sectionAnalysis,
			vars = vars,
			links = {
				options = { groups = groups, individuals = individuals },
				targets = target_links,
			},
		}, makefile_path, Content)
		return sectionAnalysis
	end

	local function GetSectionsByType(Content, targetType)
		local allSections = AnalyzeAllSections(Content)
		local filteredSections = {}

		for _, section in ipairs(allSections) do
			if section.analysis.type == targetType then
				table.insert(filteredSections, section)
			end
		end

		return filteredSections
	end

	return {
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
