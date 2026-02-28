# generator.lua

## Generator.GenerateMakefileVariables(MakefileVars)
Purpose: Build the default Makefile variable block and ensure the build directory exists.
Inputs:
- `MakefileVars` (table): Variable name/value pairs.
Returns:
- `string[]`: Lines to prepend to a Makefile.
Side effects/notes:
- Adds `$(shell mkdir -p $(BUILD_DIR)/$(BUILD_MODE))` to auto-create build dirs.
Example:
```lua
local lines = Generator.GenerateMakefileVariables(cfg.MakefileVars)
```

## Generator.ObjectTarget(Basename, RelativePath, MakefileVars)
Purpose: Generate a Makefile section for compiling a single source file into an object.
Inputs:
- `Basename` (string): File base name without extension.
- `RelativePath` (string): `./`-relative source path.
- `MakefileVars` (table): Makefile variable values.
Returns:
- `string[]`: Lines that define marker block and object rule.
Side effects/notes:
- Chooses `CC`/`CFLAGS` when present, otherwise `CXX`/`CXXFLAGS`.
Example:
```lua
local lines = Generator.ObjectTarget("main", "./src/main.cpp", cfg.MakefileVars)
```

## Generator.ExecutableTarget(Basename, RelativePath, Dependencies, MakefileVars, RootPath, Links)
Purpose: Generate object, executable, and run targets for a source file.
Inputs:
- `Basename` (string): Base name without extension.
- `RelativePath` (string): `./`-relative source path.
- `Dependencies` (string[]|nil): Header dependencies (optional).
- `MakefileVars` (table): Makefile variable values.
- `RootPath` (string): Project root, used to resolve include paths.
- `Links` (string[]|nil): Linker flags (optional).
Returns:
- `string[]|string[]`: On success, lines to append; on failure, list of missing includes.
- `boolean`: `true` on success, `false` if includes are missing.
Side effects/notes:
- Resolves header include paths and generates `-I` flags.
- Adds optional `LINKS` assignment if provided.
Detailed explanation:
- Build object/executable target names under `$(BUILD_DIR)/$(BUILD_MODE)`.
- Choose `CC`/`CFLAGS` vs `CXX`/`CXXFLAGS` based on provided vars.
- For each dependency, locate its header directory and collect unique `-I` flags.
- If any headers are missing, return the missing list and `false`.
- Emit marker start, object rule, optional `LINKS`, executable rule, and `run` rule.
Example:
```lua
local lines, ok = Generator.ExecutableTarget(
  "main",
  "./src/main.cpp",
  { "./include/utils.h" },
  cfg.MakefileVars,
  "/p/app",
  { "-lm" }
)
```

## Generator.EnsureMakefileVariables(MakefilePath, Content, MakefileVars)
Purpose: Ensure required Makefile variables exist by prepending defaults if missing.
Inputs:
- `MakefilePath` (string): Path to Makefile.
- `Content` (string|nil): Current Makefile content.
- `MakefileVars` (table): Required variables and defaults.
Returns:
- `boolean|nil`: `true` if already present, `false` if inserted, `nil` on write failure.
Side effects/notes:
- Writes updated content to disk if variables are missing.
Detailed explanation:
- Use `Parser.HasReqVars` to check for required variable definitions.
- If missing, generate the default variable block and prepend it to the file.
- Write the updated content back to disk and report success/failure.
Example:
```lua
local ok = Generator.EnsureMakefileVariables("/p/app/Makefile", content, cfg.MakefileVars)
```
