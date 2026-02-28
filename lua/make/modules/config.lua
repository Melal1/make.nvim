---@class MakefileVars
---@field CXX string             -- The C++ compiler command (e.g. "g++" or "clang++")
---@field DEBUGFLAGS string      -- Compiler flags used for debug builds
---@field RELEASEFLAGS string    -- Compiler flags used for release builds
---@field CXXFLAGS string        -- General C++ compiler flags (can refer to DEBUGFLAGS or RELEASEFLAGS)
---@field BUILD_MODE string      -- Build mode (debug/release)
---@field BUILD_DIR string       -- Base build directory name (e.g. build, out, bin)
---@field BUILD_OUT string       -- Combined build output dir (e.g. $(BUILD_DIR)/$(BUILD_MODE))
---@field CC? string             -- (Optional) The C compiler command (e.g. "gcc" or "clang")
---@field CFLAGS? string         -- (Optional) C compiler flags
---@alias MakeCacheFormat "mpack"|"luabytecode"
---@class MakeConfig
---@field SourceExtensions string[]
---@field RootMarkers string[]
---@field MaxSearchLevels integer
---@field CacheUseHash boolean
---@field CacheFormat MakeCacheFormat
---@field CacheDir string
---@field CacheLog boolean
---@field EnableBackup boolean
---@field MakefileVars MakefileVars
---@class make_options
---@field SourceExtensions? string[]
---@field RootMarkers? string[]
---@field MaxSearchLevels? integer
---@field CacheUseHash? boolean
---@field CacheFormat? MakeCacheFormat
---@field CacheDir? string
---@field CacheLog? boolean
---@field EnableBackup? boolean
---@field MakefileVars? MakefileVars
---@class make.Options : make_options
local Config = {}

---@type MakeConfig
Config.DefaultConfig = {
	SourceExtensions = { ".cpp", ".c", ".cc", ".cxx" },
	RootMarkers = { ".git", "src", "include", "build", "Makefile" },
	MaxSearchLevels = 5,
	CacheUseHash = true,
	CacheFormat = "luabytecode", -- "mpack" or "luabytecode"
	CacheDir = ".cache/make.nvim",
	CacheLog = false,
	EnableBackup = false,
	MakefileVars = {
		CXX = "g++",
		DEBUGFLAGS = "-std=c++17 -g -O0",
		RELEASEFLAGS = "-std=c++17 -O3 -DNDEBUG",
		CXXFLAGS = "$(DEBUGFLAGS)",
		BUILD_MODE = "debug",
		BUILD_DIR = "build",
		BUILD_OUT = "$(BUILD_DIR)/$(BUILD_MODE)",
	},
}

return Config
