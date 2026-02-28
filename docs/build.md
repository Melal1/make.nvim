# build.lua

## normalize_build_mode(mode)
Purpose: Normalize and validate a build mode string.
Inputs:
- `mode` (string|nil): User-provided mode string.
Returns:
- `string|nil`: `"debug"` or `"release"` if valid, otherwise `nil`.
Side effects/notes:
- Lowercases the input.
Example:
```lua
local m = normalize_build_mode("Release")
-- m == "release"
```

## update_makefile_var(lines, var_name, value)
Purpose: Update a Makefile variable assignment in a list of lines.
Inputs:
- `lines` (string[]): Makefile lines.
- `var_name` (string): Variable name to update.
- `value` (string): New value to assign.
Returns:
- `boolean`: `true` if updated, `false` if not found.
Side effects/notes:
- Preserves existing `=` vs `:=` operator.
- Preserves indentation prefix.
Example:
```lua
local ok = update_makefile_var({"CXX = g++"}, "CXX", "clang++")
```

## insert_makefile_var(lines, var_name, value)
Purpose: Insert a Makefile variable assignment near the top of the file.
Inputs:
- `lines` (string[]): Makefile lines.
- `var_name` (string): Variable name.
- `value` (string): Value to assign.
Returns:
- None.
Side effects/notes:
- Inserts after existing variable block / blank lines.
Example:
```lua
insert_makefile_var({"CXX = g++", ""}, "BUILD_MODE", "debug")
```

## resolve_build_path(makefile_path, build_out)
Purpose: Resolve a build output path relative to the Makefile directory.
Inputs:
- `makefile_path` (string): Path to the Makefile.
- `build_out` (string): Build output directory (possibly relative).
Returns:
- `string|nil`: Resolved absolute path or `nil` if input is invalid.
Side effects/notes:
- If `build_out` is absolute, it is returned unchanged.
Example:
```lua
local abs = resolve_build_path("/p/app/Makefile", "build/debug")
```

## normalize_clean_path(path)
Purpose: Normalize and validate a path before deletion.
Inputs:
- `path` (string|nil): Path to clean.
Returns:
- `string|nil`: Normalized absolute path, or `nil` if unsafe.
Side effects/notes:
- Refuses to return `/` or empty paths.
Example:
```lua
local safe = normalize_clean_path("/tmp/build")
```

## M.SetBuildMode(MakefilePath, Content, Mode)
Purpose: Update Makefile variables to switch between debug and release modes.
Inputs:
- `MakefilePath` (string): Makefile path.
- `Content` (string): Current Makefile content.
- `Mode` (string): `debug` or `release` (case-insensitive).
Returns:
- `boolean`: `true` on success, `false` on failure.
Side effects/notes:
- Updates `CXXFLAGS`, `BUILD_DIR`, `BUILD_MODE`, and `BUILD_OUT`.
- Normalizes `BUILD_DIR` by removing trailing `/debug` or `/release`.
- Writes the updated content back to disk.
Detailed explanation:
- Normalize the requested mode to `debug`/`release` and reject invalid input.
- Update (or insert) `CXXFLAGS` to point at `$(DEBUGFLAGS)` or `$(RELEASEFLAGS)`.
- Parse existing `BUILD_DIR`, strip a trailing mode segment, and reinsert it cleanly.
- Update (or insert) `BUILD_MODE` to the normalized mode.
- Join the lines and write the file back to disk.
Example:
```lua
local ok = M.SetBuildMode("/p/app/Makefile", content, "release")
```

## M.CleanBuild(MakefilePath, Content)
Purpose: Remove the build output directory for the current build mode.
Inputs:
- `MakefilePath` (string): Makefile path.
- `Content` (string): Current Makefile content.
Returns:
- `boolean`: `true` if clean succeeded or nothing to clean, `false` on error.
Side effects/notes:
- Deletes the resolved `BUILD_DIR/BUILD_MODE` directory using `vim.fn.delete(..., "rf")`.
- Refuses to clean unsafe paths like `/`.
Detailed explanation:
- Parse variables to compute the effective build output directory.
- Resolve relative build paths against the Makefile directory.
- Normalize and validate the deletion path to avoid unsafe deletions.
- If the path does not exist, report a no-op; otherwise delete recursively.
Example:
```lua
local ok = M.CleanBuild("/p/app/Makefile", content)
```
