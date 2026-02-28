# init.lua

## M.setup(UserConfig)
Purpose: Merge user configuration into defaults and apply runtime settings.
Inputs:
- `UserConfig` (table|nil): User overrides.
Returns:
- None.
Side effects/notes:
- Updates `M.Config`.
- Sets `Parser.CacheUseHash`, `Parser.CacheFormat`, `Parser.CacheDir`, and `Utils.BackupEnabled` from config.
Example:
```lua
require("make").setup({ EnableBackup = false })
```

## M.SetBuildMode(MakefilePath, Content, Mode)
Purpose: Delegate build-mode changes to the build module.
Inputs:
- `MakefilePath` (string): Makefile path.
- `Content` (string): Makefile content.
- `Mode` (string): `debug` or `release`.
Returns:
- `boolean`: `true` on success.
Example:
```lua
M.SetBuildMode("/p/app/Makefile", content, "debug")
```

## M.CleanBuild(MakefilePath, Content)
Purpose: Delegate cleaning of the current build mode output.
Inputs:
- `MakefilePath` (string): Makefile path.
- `Content` (string): Makefile content.
Returns:
- `boolean`: `true` on success.
Example:
```lua
M.CleanBuild("/p/app/Makefile", content)
```

## M.ManageLinkOptionsInteractive(makefile_path, makefile_content)
Purpose: Open the interactive link manager.
Inputs:
- `makefile_path` (string): Makefile path.
- `makefile_content` (string): Makefile content.
Returns:
- `boolean`: `true` if menu opens.
Example:
```lua
M.ManageLinkOptionsInteractive(path, content)
```

## M.AddToMakefile(MakefilePath, FilePath, RootPath, Content, BypassCheck)
Purpose: Add an object or executable target for the current file.
Inputs:
- `MakefilePath` (string)
- `FilePath` (string)
- `RootPath` (string)
- `Content` (string)
- `BypassCheck` (boolean|nil)
Returns:
- `boolean`: `true` if a target is added.
Example:
```lua
M.AddToMakefile(path, file, root, content)
```

## M.EditTarget(MakefilePath, FilePath, RootPath, Content, Entries, callback)
Purpose: Edit a specific executable target.
Inputs: See `modules/actions.lua` for full parameter semantics.
Returns:
- `boolean`: `true` if edit flow started.
Example:
```lua
M.EditTarget(path, file, root, content)
```

## M.EditAllTargets(MakefilePath, RootPath, Content)
Purpose: Pick any executable target and edit it.
Inputs:
- `MakefilePath` (string)
- `RootPath` (string)
- `Content` (string)
Returns:
- `boolean`: `true` if picker opens.
Example:
```lua
M.EditAllTargets(path, root, content)
```

## M.Remove(MakefilePath, Content)
Purpose: Remove selected marker sections from the Makefile.
Inputs:
- `MakefilePath` (string)
- `Content` (string)
Returns:
- `boolean`: `true` if picker opens.
Example:
```lua
M.Remove(path, content)
```

## M.PickAndAdd(RootPath, Content)
Purpose: Show a picker to add targets for discovered source files.
Inputs:
- `RootPath` (string)
- `Content` (string)
Returns:
- `boolean`: `true` if picker opens.
Side effects/notes:
- Used by `:Make pick-add` to add multiple targets in one flow.
Example:
```lua
M.PickAndAdd(root, content)
```

## M.BuildTarget(MakefilePath, RelativePath, Content)
Purpose: Build the executable for the current file.
Inputs:
- `MakefilePath` (string)
- `RelativePath` (string)
- `Content` (string)
Returns:
- `boolean`: `true` if build launched.
Example:
```lua
M.BuildTarget(path, "./src/main.cpp", content)
```

## M.RunTargetInSpilt(MakefilePath, RelativePath, Content)
Purpose: Run the `run_<name>` target in a split terminal.
Inputs:
- `MakefilePath` (string)
- `RelativePath` (string)
- `Content` (string)
Returns:
- `boolean`: `true` if run launched.
Example:
```lua
M.RunTargetInSpilt(path, "./src/main.cpp", content)
```

## M.PickAndRunTargets(makefile_content)
Purpose: Pick and run multiple Makefile targets.
Inputs:
- `makefile_content` (string)
Returns:
- `boolean`: `true` if picker opens.
Example:
```lua
M.PickAndRunTargets(content)
```

## M.FastRun()
Purpose: Ensure a target exists and run it quickly.
Inputs:
- None (uses `M.Config`).
Returns:
- `boolean`: `true` on success.
Side effects/notes:
- Calls `M.Make({ "run" })` after creating targets if needed.
Example:
```lua
M.FastRun()
```

## M.Make(Fargs)
Purpose: Main command dispatcher for MakeNvim operations.
Inputs:
- `Fargs` (string[]): Command arguments like `{ "add" }`, `{ "run" }`.
Returns:
- `boolean|nil`: `true` on success, `false` on error, `nil` on unrecoverable failures.
Side effects/notes:
- Finds project root, ensures Makefile variables, and routes to command handlers.
- Supports: `add`, `edit`, `run`, `runb`, `build`, `tasks`, `edit_all`, `remove`, `analysis`, `bear`, `bearall`, `mode`, `clean`, `link`, `open`.
Detailed explanation:
- Parse the subcommand (default `run`) and validate argument count.
- Locate the project root using configured root markers.
- Compute `MakefilePath` and set parser cache context.
- Create a Makefile if missing and the user approves.
- Ensure required Makefile variables exist; if inserted, re-run the command.
- Dispatch to the appropriate handler module based on the subcommand.
Example:
```lua
M.Make({ "build" })
```
