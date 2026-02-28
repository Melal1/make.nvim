# runner.lua

## M.BuildTarget(MakefilePath, RelativePath, Content)
Purpose: Build the executable target corresponding to the given file.
Inputs:
- `MakefilePath` (string): Path to Makefile.
- `RelativePath` (string): `./`-relative path for the file.
- `Content` (string): Makefile content.
Returns:
- `boolean`: `true` if the build command was launched, `false` on error.
Side effects/notes:
- Resolves the actual build target using `BUILD_DIR` and `BUILD_MODE`.
- Runs `make <target>` via `vim.system`.
- Writes build errors to `/tmp/<bin>.err`.
How it works (step-by-step):
1) Finds the executable section that matches `RelativePath`.
2) Reads Makefile variables and derives `base_dir`, `build_mode`, and `build_out` (`BUILD_DIR/BUILD_MODE`).
3) Resolves the target name:
   - If the target contains `$(BUILD_MODE)`, it replaces `$(BUILD_DIR)/$(BUILD_MODE)` with `build_out`,
     then replaces any remaining `$(BUILD_MODE)` and `$(BUILD_DIR)` placeholders.
   - Otherwise, it only replaces `$(BUILD_DIR)` with `base_dir`.
4) Strips a leading `./` from the resolved target for a clean `make` argument.
5) Runs `make <resolved_target>` in the Makefile directory and reports success/error.
Edge cases:
- If no executable targets exist, it warns and returns `false`.
- If the path does not map to a known executable section, it warns and returns `false`.
- If `make` fails, stderr is written to `/tmp/<bin>.err`.
Example:
```lua
M.BuildTarget("/p/app/Makefile", "./src/main.cpp", content)
```

## M.RunTargetInSpilt(MakefilePath, RelativePath, Content)
Purpose: Run the `run<name>` Makefile target in a terminal split.
Inputs:
- `MakefilePath` (string): Path to Makefile.
- `RelativePath` (string): `./`-relative path for the file.
- `Content` (string): Makefile content.
Returns:
- `boolean`: `true` if a run command was sent, `false` on error.
Side effects/notes:
- Uses `make.terminal` (built-in).
Example:
```lua
M.RunTargetInSpilt("/p/app/Makefile", "./src/main.cpp", content)
```

## M.PickAndRunTargets(makefile_content)
Purpose: Let the user select and run one or more Makefile targets.
Inputs:
- `makefile_content` (string): Makefile content.
Returns:
- `boolean`: `true` if picker opens, `false` on error.
Side effects/notes:
- Runs `make <targets...>` in a terminal.
Detailed explanation:
- Collect all targets from analyzed sections and sort them for display.
- Present a checklist picker so multiple targets can be selected.
- Map display labels back to real target names.
- Execute `make` with the selected targets in a terminal buffer.
Example:
```lua
M.PickAndRunTargets(content)
```

## M.FastRun(Config, on_run)
Purpose: Quickly run a file by ensuring its target exists, then calling `on_run`.
Inputs:
- `Config` (table|nil): Config containing `MakefileVars`.
- `on_run` (function|nil): Callback to run after ensuring the target exists.
Returns:
- `boolean`: `true` on success, `false` on error.
Side effects/notes:
- If no target exists, it generates a new executable section and appends it.
- Uses link selection UI if link options are present.
Detailed explanation:
- Resolve the Makefile path from the current buffer and set parser cache context.
- Compute the current file’s relative path to the Makefile directory.
- If a matching marker exists, immediately invoke `on_run`.
- Otherwise, ensure required Makefile variables exist, then generate a new executable target.
- Append the new target to the Makefile and invoke `on_run`.
Example:
```lua
M.FastRun(cfg, function() print("ready to run") end)
```
