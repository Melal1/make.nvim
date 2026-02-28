# config.lua

This file defines the default configuration table used by the MakeNvim module.
It has no functions, but the config keys are described below.

## Config.DefaultConfig
Purpose: Provide a single source of default behavior for MakeNvim.
Keys:
- `SourceExtensions` (string[]): Allowed source file extensions.
- `RootMarkers` (string[]): Files/dirs used to detect project root.
- `MaxSearchLevels` (integer): How many parent directories to search for markers.
- `CacheUseHash` (boolean): Whether parser cache uses a content hash.
- `CacheFormat` (string): Cache encoding format (`"mpack"` or `"luabytecode"`). Bytecode is faster to load but not portable across Lua versions and is executable.
- `CacheDir` (string): Cache directory (relative paths are treated as `~/<path>`).
- `CacheLog` (boolean): When true, log cache hit/miss messages.
- `EnableBackup` (boolean): Global default for Makefile backups.
- `MakefileVars` (table): Default Makefile variable values:
  - `CXX`, `CC` (string): Compiler commands.
  - `DEBUGFLAGS`, `RELEASEFLAGS` (string): Debug/release compiler flags.
  - `CXXFLAGS`, `CFLAGS` (string): Active compile flags.
  - `BUILD_MODE` (string): Current build mode.
  - `BUILD_DIR` (string): Base build output directory.
  - `BUILD_OUT` (string): Combined build output directory (e.g. `$(BUILD_DIR)/$(BUILD_MODE)`).

Example:
```lua
require("make").setup({
  EnableBackup = false,
  SourceExtensions = { ".cpp", ".c", ".cc" },
  MakefileVars = {
    CXX = "clang++",
    DEBUGFLAGS = "-std=c++20 -g -O0",
    RELEASEFLAGS = "-std=c++20 -O3 -DNDEBUG",
    CXXFLAGS = "$(DEBUGFLAGS)",
    BUILD_MODE = "debug",
    BUILD_DIR = "build",
    BUILD_OUT = "$(BUILD_DIR)/$(BUILD_MODE)",
  },
})
```
