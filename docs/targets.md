# targets.lua

## M.GetObjectTargetsForPicker(Content)
Purpose: Collect object targets for display in a picker.
Inputs:
- `Content` (string): Makefile content.
Returns:
- `table[]`: Items with `value` (target name) and `display` (basename.o).
Side effects/notes:
- Includes object targets from `obj` sections only.
Example:
```lua
local items = M.GetObjectTargetsForPicker(content)
```

## M.GetExeTables(Content)
Purpose: Return section entries that represent executable targets.
Inputs:
- `Content` (string): Makefile content.
Returns:
- `table[]`: Sections with analysis type `full` or `executable`.
Example:
```lua
local exes = M.GetExeTables(content)
```

## M.GetExecutableTarget(entry)
Purpose: Return the executable target table for a section entry.
Inputs:
- `entry` (table): Section entry (from `AnalyzeAllSections` or `GetExeTables`).
Returns:
- `table|nil`: Target table (with `name`, `dependencies`, `recipe`, `kind`) or `nil`.
Side effects/notes:
- Uses target matching based on type, not positional ordering.
Example:
```lua
local target = M.GetExecutableTarget(entry)
```

## M.GetAllTargetsForDisplay(Content)
Purpose: Build a list of all targets with display labels.
Inputs:
- `Content` (string): Makefile content.
Returns:
- `table[]`: Items with `name`, `display`, and `type`.
Side effects/notes:
- Uses `Helpers.TargetTypeLabel` to label obj/run/exe.
Example:
```lua
local targets = M.GetAllTargetsForDisplay(content)
```
