# parser.lua

## Parser.SetCacheRoot(root_path, makefile_path)
Purpose: Set the cache context for parsing operations.
Inputs:
- `root_path` (string|nil): Project root path.
- `makefile_path` (string|nil): Makefile path.
Returns:
- None.
Side effects/notes:
- Updates `Parser.CacheRoot` and `Parser.CacheMakefilePath` when non-empty.
Example:
```lua
Parser.SetCacheRoot("/p/app", "/p/app/Makefile")
```

## cache_key_for(root_path)
Purpose: Convert a path into a filesystem-safe cache key.
Inputs:
- `root_path` (string|nil): Root path.
Returns:
- `string`: Normalized key used for cache filename.
Side effects/notes:
- Replaces separators and drive letters with safe characters.
Example:
```lua
local key = cache_key_for("/p/app")
```

## cache_file_for(root_path)
Purpose: Build the cache filename for a given root.
Inputs:
- `root_path` (string|nil): Root path.
Returns:
- `string`: Full path to cache file in `~/.cache/make.nvim/` (or `CacheDir` if set).
Example:
```lua
local path = cache_file_for("/p/app")
```

## log_cache(message)
Purpose: Emit a debug notification when cache logging is enabled.
Inputs:
- `message` (string): Message to show.
Returns:
- None.
Side effects/notes:
- Honors `Parser.CacheLog` flag.
Example:
```lua
log_cache("Cache miss")
```

## is_links_assignment_line(line)
Purpose: Detect lines assigning `LINKS` on a target.
Inputs:
- `line` (string): Line to test.
Returns:
- `boolean`: `true` when the line matches a `LINKS` assignment.
Example:
```lua
local ok = is_links_assignment_line("app: LINKS += -lm")
```

## search_flags_for(annotatedType)
Purpose: Determine which target types to search for based on a marker annotation.
Inputs:
- `annotatedType` (string|nil): `full`, `executable`, `obj`, or `run`.
Returns:
- `table`: Flags for `obj`, `executable`, and `run` searches.
Example:
```lua
local flags = search_flags_for("executable")
```

## read_makefile_content(makefile_path)
Purpose: Read Makefile content from disk if a path is provided.
Inputs:
- `makefile_path` (string|nil): Makefile path.
Returns:
- `string|nil`: Content or `nil` if missing.
Example:
```lua
local content = read_makefile_content("/p/app/Makefile")
```

## try_load_cache(root_path, makefile_path, content)
Purpose: Load cached parse payload when valid.
Inputs:
- `root_path` (string|nil): Root used for cache naming.
- `makefile_path` (string|nil): Makefile path for stat/hash validation.
- `content` (string|nil): Optional Makefile content for hashing.
Returns:
- `table|nil`: Cached payload `{ sections, vars, links }`, or `nil` if cache miss.
- `string|nil`: Computed hash (when applicable).
- `string`: Cache file path used.
Side effects/notes:
- Uses mtime/size checks first, then optional SHA256 hash.
Detailed explanation:
- Build the cache filename from `root_path` (or cwd) and exit early if the cache file is missing.
- Read raw bytes and decode based on `CacheFormat` into a payload with `sections` (and optional `vars`/`links`).
- If `makefile_path` is provided, compare cached mtime/size with the file on disk for a fast hit.
- If metadata changed and hash checks are disabled, treat it as a cache miss.
- If hashing is enabled, compute SHA256 from `content` (or read the Makefile), then compare to cached hash.
- On hash match, optionally refresh cache metadata and return the payload + hash; on mismatch, return `nil` and the computed hash.
Example:
```lua
local payload, hash, cache_file = try_load_cache("/p/app", "/p/app/Makefile", content)
```

## write_cache(cache_file, payload, makefile_path, content)
Purpose: Write cached parse payload to disk.
Inputs:
- `cache_file` (string): Cache path.
- `sections` (table): Parsed section analysis (or payload table `{ sections, vars, links }`).
- `makefile_path` (string|nil): Makefile path for metadata.
- `content` (string|nil): Makefile content for hashing.
Returns:
- None.
Side effects/notes:
- Creates `CacheDir` (default `~/.cache/make.nvim`) if needed.
Detailed explanation:
- Normalize the incoming payload so it always has a `sections` table (and optionally `vars`/`links`).
- Capture current Makefile mtime/size when a file path is provided.
- If hashing is enabled, compute SHA256 from content (or read it) and store it in the payload.
- Encode the payload as MsgPack and write it to the cache file in binary mode.
Example:
```lua
write_cache(cache_file, payload, "/p/app/Makefile", content)
```

## Parser.ParseVariables(Content, opts)
Purpose: Parse simple Makefile variable assignments into a table (uses cache when available).
Inputs:
- `Content` (string|nil): Makefile content.
- `opts` (table|string|nil): Cache context overrides; set `cache_log = true` to emit cache hit/miss logs.
Returns:
- `table<string,string>`: Map of variable name to value.
Side effects/notes:
- Skips comments and empty lines.
- Supports `=` and `:=` assignments.
Detailed explanation:
- Resolve cache context from `opts` or the global parser cache.
- Try to load the cached payload and return `vars` when present.
- Otherwise, scan each non-comment line for `NAME = VALUE` / `NAME := VALUE` assignments.
- If a cache payload exists, write it back with the freshly parsed `vars`.
Example:
```lua
local vars = Parser.ParseVariables("CXX = g++\nBUILD_MODE := debug\n")
```

## Parser.ParseLinkOptions(Content, opts)
Purpose: Parse the `# links_start` / `# links_end` block in a Makefile (uses cache when available).
Inputs:
- `Content` (string|nil): Makefile content.
- `opts` (table|string|nil): Cache context overrides; set `cache_log = true` to emit cache hit/miss logs.
Returns:
- `groups` (table[]): List of `{ name, flags }`.
- `individuals` (string[]): Link flags not part of groups.
Detailed explanation:
- Resolve cache context from `opts` or the global parser cache.
- Try to load cached link options and return them when available.
- Otherwise, parse the `# links_start` / `# links_end` block for groups and individuals.
- If a cache payload exists, write it back with the parsed link options.
Example:
```lua
local groups, individuals = Parser.ParseLinkOptions(content)
```

## Parser.GetCachedTargetLinks(Content, RelativePath, opts)
Purpose: Load cached executable link flags for a marker section if available.
Inputs:
- `Content` (string|nil): Makefile content.
- `RelativePath` (string): Marker path.
- `opts` (table|string|nil): Cache context overrides; set `cache_log = true` to emit cache hit/miss logs.
Returns:
- `string[]|nil`: Cached link flags, or `nil` when missing.
Example:
```lua
local flags = Parser.GetCachedTargetLinks(content, "./src/main.cpp")
```

## Parser.FindMarker(Content, RelativePath, CheckStart, CheckEnd)
Purpose: Find marker start/end line numbers for a given file path.
Inputs:
- `Content` (string|string[]): Makefile content (string or pre-split lines).
- `RelativePath` (string): Marker path.
- `CheckStart` (boolean): Whether to search for start marker.
- `CheckEnd` (boolean): Whether to search for end marker.
Returns:
- `MarkerInfo`: `{ M_start, M_end, type }`.
Side effects/notes:
- Reads line by line and extracts optional `type:` annotation.
Detailed explanation:
- Normalize `Content` into a list of lines so line indices match Makefile line numbers.
- Scan only comment lines to find `# marker_start: <path>` for the requested `RelativePath`.
- When a start marker is found, capture its line number and optional `type:` annotation.
- If `CheckEnd` is enabled, continue scanning until `# marker_end: <path>` is found.
- Return the gathered start/end line numbers (or `-1` for disabled checks).
Example:
```lua
local info = Parser.FindMarker(content, "./src/main.cpp", true, true)
```

## Parser.FindAllMarkerPairs(Content)
Purpose: Find all `marker_start`/`marker_end` pairs in the Makefile.
Inputs:
- `Content` (string|string[]|nil): Makefile content (string or pre-split lines).
Returns:
- `MarkerPair[]`: Array of `{ path, StartLine, EndLine, annotatedType }`.
Detailed explanation:
- Normalize `Content` into lines and iterate once from top to bottom.
- When a `marker_start` is found, record its line and optional `type:` in a map keyed by path.
- When a `marker_end` is found, look up the matching start and emit a pair.
- Remove matched starts to keep the map small and avoid duplicate pairs.
Example:
```lua
local pairs = Parser.FindAllMarkerPairs(content)
```

## Parser.ReadContentBetweenLines(Content, StartLine, EndLine, ReturnTable)
Purpose: Extract content between two line numbers.
Inputs:
- `Content` (string|string[]): Makefile content (string or pre-split lines).
- `StartLine` (integer): Start line (exclusive).
- `EndLine` (integer): End line (exclusive).
- `ReturnTable` (boolean|nil): Return a table of lines if `true`.
Returns:
- `string|string[]`: Extracted content.
Detailed explanation:
- Normalize `Content` into lines so indexes match line numbers.
- Slice the line list between `StartLine` and `EndLine` (exclusive).
- Return the slice as a table when `ReturnTable` is `true`, otherwise join with `\n`.
Example:
```lua
local block = Parser.ReadContentBetweenLines(content, 10, 20, false)
```

## Parser.ReadContentBetweenMarkers(Content, RelativePath, ReturnTable)
Purpose: Extract content between marker start/end for a specific path.
Inputs:
- `Content` (string|string[]): Makefile content (string or pre-split lines).
- `RelativePath` (string): Marker path.
- `ReturnTable` (boolean|nil): Return table of lines if `true`.
Returns:
- `string|string[]`: Extracted section content.
Detailed explanation:
- Resolve marker start/end line numbers for `RelativePath`.
- If either marker is missing, return an empty string/table.
- Slice the normalized line list between the marker lines.
- Return the slice as a table or joined string depending on `ReturnTable`.
Example:
```lua
local section = Parser.ReadContentBetweenMarkers(content, "./src/main.cpp")
```

## Parser.TargetExists(Content, RelativePath)
Purpose: Check whether a section exists for a given path.
Inputs:
- `Content` (string|nil): Makefile content.
- `RelativePath` (string): Marker path.
Returns:
- `boolean`: `true` if marker start exists.
Example:
```lua
if Parser.TargetExists(content, "./src/main.cpp") then ... end
```

## Parser.ParseDependencies(targetLine)
Purpose: Parse dependency tokens from a Makefile target line.
Inputs:
- `targetLine` (string): Line like `target: dep1 dep2`.
Returns:
- `string[]`: Dependency list.
Example:
```lua
local deps = Parser.ParseDependencies("app: main.o utils.o")
```

## Parser.FindExecutableTargetName(sectionContent, baseName)
Purpose: Find the best executable target name in a section.
Inputs:
- `sectionContent` (string): Section content.
- `baseName` (string|nil): Base name hint for matching.
Returns:
- `string|nil`: Target name or `nil` if not found.
Side effects/notes:
- Skips `LINKS` assignment lines and `.o` targets.
Detailed explanation:
- Walk each non-empty, non-comment line in the section.
- Ignore `LINKS` assignment lines to avoid confusing target detection.
- Extract the target name before the colon.
- Prefer a target that matches `baseName` (or its BUILD_DIR/BUILD_MODE forms).
- Fall back to the first non-`.o`/`run` target if no exact match is found.
Example:
```lua
local name = Parser.FindExecutableTargetName(section, "main")
```

## Parser.GetLinksForTarget(sectionContent, targetName)
Purpose: Extract `LINKS` flags for a specific target.
Inputs:
- `sectionContent` (string): Section content.
- `targetName` (string): Target name.
Returns:
- `string[]`: Link flags.
Example:
```lua
local links = Parser.GetLinksForTarget(section, "build/debug/main")
```

## Parser.ParseTarget(sectionContent, targetName)
Purpose: Parse a target block into dependencies and recipe lines.
Inputs:
- `sectionContent` (string): Section content.
- `targetName` (string): Target to parse.
Returns:
- `TargetInfo`: `{ name, dependencies, recipe, found }`.
Detailed explanation:
- Split the section into lines and scan for the exact `targetName:` header.
- Skip `LINKS` assignment lines that reuse the target name.
- When the target header is found, parse its dependency list.
- Collect subsequent indented lines as the recipe until a non-indented line appears.
Example:
```lua
local info = Parser.ParseTarget(section, "main")
```

## Parser.DetectTargetTypes(sectionContent, baseName, annotatedType)
Purpose: Detect whether a section contains obj, executable, and run targets.
Inputs:
- `sectionContent` (string): Section content.
- `baseName` (string|nil): Base name hint.
- `annotatedType` (string|nil): Expected type annotation.
Returns:
- `boolean hasObj`, `boolean hasExecutable`, `boolean hasRun`.
Example:
```lua
local hasObj, hasExe, hasRun = Parser.DetectTargetTypes(section, "main")
```

## Parser.AnalyzeSection(sectionContent, baseName, annotatedType)
Purpose: Analyze a single section and validate expected target types.
Inputs:
- `sectionContent` (string): Section content.
- `baseName` (string|nil): Base name hint.
- `annotatedType` (string|nil): Marker annotation type.
Returns:
- `SectionAnalysis`: Detailed target and type info.
Side effects/notes:
- Marks invalid sections and provides error messages.
Detailed explanation:
- Normalize `baseName` if missing by inferring it from a `.cpp` path in the section.
- Scan each non-comment line for targets and build a unique target list.
- Track presence of `.o`, executable, and `run` targets based on naming patterns.
- Parse dependencies and recipes for each target to populate `targets[]`.
- Infer the overall section type (`full`, `executable`, `obj`, `run`, `unknown`).
- If `annotatedType` is present, validate required targets and set `valid`/`error`.
Example:
```lua
local analysis = Parser.AnalyzeSection(section, "main", "full")
```

## Parser.AnalyzeAllSections(Content, opts)
Purpose: Analyze all marker sections and optionally use cached results.
Inputs:
- `Content` (string): Makefile content.
- `opts` (table|string|nil): Root and Makefile path hints.
Returns:
- `table[]`: Section analysis list.
Side effects/notes:
- Writes cache on successful parse (sections, Makefile vars, and link options/targets).
Detailed explanation:
- Resolve cache context (root and Makefile path) and attempt to load cached analysis.
- On cache miss, split the Makefile into lines and collect all marker pairs.
- For each marker pair, slice its section, analyze targets, and record metadata.
- Capture executable link flags per section and parse global link options.
- Parse Makefile variables once and write the full payload back to cache.
Example:
```lua
local sections = Parser.AnalyzeAllSections(content, { root = "/p/app" })
```

## Parser.GetSectionsByType(Content, targetType)
Purpose: Filter analyzed sections by a target type.
Inputs:
- `Content` (string): Makefile content.
- `targetType` (string): `obj`, `executable`, `run`, or `full`.
Returns:
- `table[]`: Filtered sections.
Example:
```lua
local runSections = Parser.GetSectionsByType(content, "run")
```

## Parser.PrintAnalysisSummary(Content)
Purpose: Emit a human-readable summary of all sections via notifications.
Inputs:
- `Content` (string): Makefile content.
Returns:
- None.
Side effects/notes:
- Uses multiple `vim.notify` calls with summary lines.
Detailed explanation:
- Analyze all sections (uses cache when available).
- For each section, slice its content and derive the executable target + links.
- Print a structured summary: path, type, target list, dependencies, recipes, and links.
Example:
```lua
Parser.PrintAnalysisSummary(content)
```

## Parser.HasReqVars(Content, MakefileVars)
Purpose: Check whether all required Makefile variables are present.
Inputs:
- `Content` (string|nil): Makefile content.
- `MakefileVars` (table): Required variable names.
Returns:
- `boolean`: `true` if all exist.
Example:
```lua
local ok = Parser.HasReqVars(content, cfg.MakefileVars)
```
