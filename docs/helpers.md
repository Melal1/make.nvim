# helpers.lua

## M.GetPickerOrWarn(message)
Purpose: Return the picker module if available, otherwise show an error.
Inputs:
- `message` (string|nil): Error message to display when picker is missing.
Returns:
- `picker` (table|nil): Picker module or `nil` if unavailable.
Side effects/notes:
- Uses `vim.notify` through `Utils.Notify` when missing.
Example:
```lua
local picker = M.GetPickerOrWarn("Picker required")
if not picker then return end
```

## M.GetRelativeOrWarn(file_path, root_path)
Purpose: Convert an absolute file path to a root-relative path, or warn if invalid.
Inputs:
- `file_path` (string): Absolute file path.
- `root_path` (string): Root directory path.
Returns:
- `string|nil`: Relative path on success, `nil` on failure.
Side effects/notes:
- Calls `Utils.Notify` if the file is outside the root.
Example:
```lua
local rel = M.GetRelativeOrWarn("/p/app/src/main.cpp", "/p/app")
```

## M.GetSectionsByTypes(content, types)
Purpose: Filter analyzed Makefile sections by type.
Inputs:
- `content` (string): Makefile content.
- `types` (table): Map of types to include, e.g. `{ full = true }`.
Returns:
- `table[]`: Filtered section list.
Side effects/notes:
- Uses `Parser.AnalyzeAllSections` internally.
Example:
```lua
local sections = M.GetSectionsByTypes(content, { obj = true, full = true })
```

## M.FindSectionByPath(sections, relative_path)
Purpose: Find a section entry by its marker path.
Inputs:
- `sections` (table[]): Section list.
- `relative_path` (string): Marker path to search for.
Returns:
- `table|nil`: Matching section entry or `nil`.
Example:
```lua
local ent = M.FindSectionByPath(sections, "./src/main.cpp")
```

## M.TargetTypeLabel(target_name)
Purpose: Return a human-readable label for a Makefile target.
Inputs:
- `target_name` (string): Target name.
Returns:
- `string`: `(obj)`, `(run)`, or `(exe)`.
Example:
```lua
local label = M.TargetTypeLabel("runmain")
```
