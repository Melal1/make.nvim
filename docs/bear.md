# bear.lua

## run_bear_async(cmd, success_msg, Callback)
Purpose: Run a Bear command asynchronously and report success/failure.
Inputs:
- `cmd` (string[]): Command argument array to execute.
- `success_msg` (string|nil): Message to show on success.
- `Callback` (function|nil): Invoked on success.
Returns:
- None.
Side effects/notes:
- Writes errors to `/tmp/Bearerr` on failure.
Example:
```lua
run_bear_async({ "bear", "--append", "--", "make", "-B", "main.o" }, "Bear finished")
```

## resolve_target_name(target, vars)
Purpose: Resolve a Makefile target name by substituting build variables.
Inputs:
- `target` (string): Target name (may contain `$(BUILD_OUT)`).
- `vars` (table): Parsed Makefile variables.
Returns:
- `string`: Resolved target name.
How it works (step-by-step):
1) Reads `BUILD_DIR` and `BUILD_MODE` from `vars` (defaults to `build` and `debug`).
2) Computes `build_out` via `Utils.GetBuildOutputDir`, which appends the mode if needed.
3) Replaces `$(BUILD_OUT)` with `build_out`.
5) Trims surrounding whitespace and returns the final string.
Edge cases:
- If `BUILD_MODE` is empty, the `build_out` resolves to just `BUILD_DIR`.
- If the target does not include either placeholder, it is returned unchanged (aside from trimming).
Example:
```lua
local t = resolve_target_name("$(BUILD_OUT)/main.o", vars)
```

## M.CurrentFile(Content, Rootdir, RelativePath, Callback)
Purpose: Run Bear for the object target corresponding to the current file.
Inputs:
- `Content` (string): Makefile content.
- `Rootdir` (string): Project root directory.
- `RelativePath` (string|nil): `./`-relative path of current file.
- `Callback` (function|nil): Called on success.
Returns:
- `boolean`: `true` if a Bear command was launched.
Side effects/notes:
- Scans sections for an object target matching the file.
Detailed explanation:
- Parse Makefile variables to resolve build paths.
- Determine the relative path to the current file (if not provided).
- Analyze all sections and find the one matching the file path.
- Locate its object target and resolve `$(BUILD_OUT)`.
- Run `bear --append -- make -B <target>` in the project root.
Example:
```lua
M.CurrentFile(content, "/p/app", "./src/main.cpp")
```

## M.Target(Lines, Rootdir, BuildDir)
Purpose: Run Bear for a target found in a list of Makefile lines.
Inputs:
- `Lines` (string[]): Makefile lines.
- `Rootdir` (string): Project root.
- `BuildDir` (string): Build output directory.
Returns:
- `boolean`: `true` if a Bear command was launched.
Side effects/notes:
- Looks for object targets using `$(BUILD_OUT)` placeholders.
How it works (step-by-step):
1) Scans each line for a target name (`^([^:]+):`).
2) Checks for object targets that start with `$(BUILD_OUT)` and end with `.o`.
3) Resolves the target by replacing `$(BUILD_OUT)` with `BuildDir`.
4) Runs `bear --append -- make -B <resolved_target>` from `Rootdir`.
5) Returns `true` after launching the first matching Bear command.
Edge cases:
- If no object target matches the pattern, it returns `false`.
- If `BuildDir` does not match the Makefile’s actual build layout, Bear may build the wrong path.
Example:
```lua
M.Target(lines, "/p/app", "build/debug")
```

## M.SelectTarget(Content, Rootdir)
Purpose: Let the user select targets and run Bear for them.
Inputs:
- `Content` (string): Makefile content.
- `Rootdir` (string): Project root.
Returns:
- `boolean`: `true` if picker opens, `false` on error.
Side effects/notes:
- Uses picker with previews to select sections.
Detailed explanation:
- Parse Makefile variables and analyze all sections.
- Build a picker list of sections that contain object targets.
- For each selected section, pick the first object target and resolve it.
- Run a single Bear command that builds all selected targets.
Example:
```lua
M.SelectTarget(content, "/p/app")
```
