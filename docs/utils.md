# utils.lua

## Utils.BackupEnabled
Purpose: Global default that controls whether `Utils.WriteFile` creates a `.bak` backup when `EnableBackup` is not explicitly passed.
Notes: Defaults to `true` and is typically set from config during `M.setup`.
Example:
```lua
local Utils = require("make.shared.utils")
Utils.BackupEnabled = false
```

## Utils.ReadFile(FilePath)
Purpose: Read the entire content of a file into a string.
Inputs:
- `FilePath` (string): Path to the file to read.
Returns:
- `content` (string|nil): File content on success, `nil` on failure.
- `err` (string|nil): Error message when failed to open/read.
Side effects/notes:
- Uses `io.open` and closes the file handle.
- Does not create directories or files.
Example:
```lua
local content, err = Utils.ReadFile("/tmp/Makefile")
if not content then
  Utils.Notify(err, vim.log.levels.ERROR)
end
```

## Utils.WriteFile(FilePath, Content, EnableBackup)
Purpose: Write content to a file, optionally creating a `.bak` backup of the previous content.
Inputs:
- `FilePath` (string): Path to write.
- `Content` (string): New content.
- `EnableBackup` (boolean|nil): When `nil`, uses `Utils.BackupEnabled`. When `true`, creates `.bak` if the file exists.
Returns:
- `success` (boolean): `true` on success.
- `err` (string|nil): Error message on failure.
Side effects/notes:
- Reads original file to create a backup when enabled.
- Overwrites existing file content.
Example:
```lua
local ok, err = Utils.WriteFile("Makefile", "CXX = g++\n", false)
if not ok then
  Utils.Notify(err, vim.log.levels.ERROR)
end
```

## Utils.AppendToFile(FilePath, Lines)
Purpose: Append multiple lines to a file.
Inputs:
- `FilePath` (string): Path to append to.
- `Lines` (string[]): Lines to append; each line gets a trailing `\n`.
Returns:
- `success` (boolean): `true` on success.
- `err` (string|nil): Error message on failure.
Side effects/notes:
- Opens file in append mode and writes sequentially.
Example:
```lua
Utils.AppendToFile("Makefile", { "", "target: deps", "\t@echo ok" })
```

## Utils.IsValidSourceFile(FilePath, SourceExtensions)
Purpose: Check whether a file path ends with one of the allowed source extensions.
Inputs:
- `FilePath` (string): File path to test.
- `SourceExtensions` (string[]): Allowed extensions including the dot, e.g. `{ ".cpp", ".c" }`.
Returns:
- `boolean`: `true` if the extension matches.
Side effects/notes:
- Uses `vim.fn.fnamemodify(FilePath, ":e")` for extension.
Example:
```lua
if not Utils.IsValidSourceFile("main.cpp", { ".cpp" }) then
  Utils.Notify("Not a C++ file", vim.log.levels.WARN)
end
```

## Utils.EscapePattern(Str)
Purpose: Escape Lua pattern magic characters in a string.
Inputs:
- `Str` (string): Input string.
Returns:
- `escaped` (string): Escaped string safe for `string.match` patterns.
- `count` (integer): Number of replacements performed.
Side effects/notes:
- Useful for building search patterns from file paths.
Example:
```lua
local escaped = Utils.EscapePattern("a/b.c")
local ok = ("a/b.c"):match(escaped) ~= nil
```

## Utils.GetRelativePath(FilePath, RootPath)
Purpose: Convert an absolute file path into a `./`-relative path from a root.
Inputs:
- `FilePath` (string): File path (absolute or relative).
- `RootPath` (string): Root directory.
Returns:
- `relativePath` (string): `./`-relative path if inside root, otherwise an error string.
- `okay` (boolean): `true` when inside root.
Side effects/notes:
- Normalizes both paths to absolute and ensures root ends with `/`.
Detailed explanation:
- Normalize the file path and root path to absolute, comparable forms.
- Ensure the root path ends with a `/` so prefix checks are consistent.
- If the file path starts with the root prefix, return a `./`-relative path.
- Otherwise, return an error message and `false`.
Example:
```lua
local rel, ok = Utils.GetRelativePath("/p/app/src/main.cpp", "/p/app")
-- rel == "./src/main.cpp", ok == true
```

## Utils.Notify(Message, Level, Opts)
Purpose: Send a standardized notification prefixed with `MakeNvim:`.
Inputs:
- `Message` (string): Text to show.
- `Level` (integer|nil): `vim.log.levels.*` value.
- `Opts` (table|nil): Extra notify options (e.g. title).
Returns:
- None.
Side effects/notes:
- Trims empty messages and avoids duplicate prefixing.
Example:
```lua
Utils.Notify("Build succeeded", vim.log.levels.INFO, { title = "Make" })
```

## Utils.GetBuildOutputDir(Vars)
Purpose: Compute the actual build output directory from `BUILD_DIR` and `BUILD_MODE` variables.
Inputs:
- `Vars` (table|nil): Parsed Makefile variables.
Returns:
- `string`: Output directory path, with `BUILD_MODE` appended if set.
Side effects/notes:
- If `BUILD_DIR` already ends with `/BUILD_MODE`, it is returned as-is.
Detailed explanation:
- Read `BUILD_DIR` (default `build`) and `BUILD_MODE` (default empty).
- If a mode is set and `BUILD_DIR` already ends with that mode, return it unchanged.
- Otherwise, append `/<mode>` to `BUILD_DIR`.
Example:
```lua
local out = Utils.GetBuildOutputDir({ BUILD_DIR = "build", BUILD_MODE = "debug" })
-- out == "build/debug"
```
