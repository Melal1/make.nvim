# finder.lua

## Finder.FindRoot(StartingPoint, MaxSearchLevels, RootMarkers)
Purpose: Walk upward from a starting directory to locate a project root using marker files or directories.
Inputs:
- `StartingPoint` (string|nil): Directory to start from. Defaults to current buffer directory.
- `MaxSearchLevels` (integer|nil): Maximum parent levels to traverse. Default is 5.
- `RootMarkers` (string[]|nil): Marker names like `.git`, `Makefile`, `src`.
Returns:
- `RootInfo` (table|nil): `{ Path, Marker, Level }` when found.
- `err` (string|nil): Error text when not found.
Side effects/notes:
- Uses `vim.loop.fs_stat` to detect markers.
- Stops when reaching filesystem root or max levels.
Detailed explanation:
- Validate the starting directory and normalize defaults.
- For each level, check each marker name under the current path.
- If a marker exists, return the current path + marker info.
- Otherwise, move to the parent directory and continue until limits are reached.
Example:
```lua
local Finder = require("make.shared.finder")
local root, err = Finder.FindRoot(nil, 6, { ".git", "Makefile" })
if root then
  print(root.Path)
else
  print(err)
end
```

## Finder.FindHeaderDirectory(Basename, RootPath)
Purpose: Find the directory containing a header file named `<Basename>.h`.
Inputs:
- `Basename` (string): Header base name without extension.
- `RootPath` (string): Root directory to search.
Returns:
- `string|nil`: Directory containing the header, relative to root when possible.
Side effects/notes:
- Uses a cached header index built per project root for faster lookups.
- Index is built once using `vim.fs.find` and reused across queries.
- Returns only the first match in the index for a given basename.
Detailed explanation:
- Build or reuse a cached index of `<Basename> -> directory` for the project root.
- If no entry exists for `Basename`, return `nil`.
- Prefer a root-relative directory when possible; fall back to absolute.
Example:
```lua
local dir = Finder.FindHeaderDirectory("utils", "/p/app")
-- Possible result: "./include" or "/p/app/include"
```

## Finder.BuildHeaderIndex(RootPath)
Purpose: Build or return the cached header index for a project root.
Inputs:
- `RootPath` (string): Root directory to index.
Returns:
- `table<string,string>`: Map of header basenames to directories.
Side effects/notes:
- Uses `vim.fs.find` to scan for `*.h` once per root.
Example:
```lua
local index = Finder.BuildHeaderIndex("/p/app")
```

## Finder.ClearHeaderIndex(RootPath)
Purpose: Clear cached header index entries.
Inputs:
- `RootPath` (string|nil): Root to clear, or `nil` to clear all.
Example:
```lua
Finder.ClearHeaderIndex("/p/app")
```
