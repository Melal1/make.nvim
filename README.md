# make.nvim

Makefile helper utilities for Neovim (targets, links, build/run, cache)

## Install (lazy.nvim)

- lazy.nvim :
```lua
	{
    "Melal1/make.nvim",
		dependencies = {
			"nvim-telescope/telescope.nvim",
		},
		ft = { "cpp" },
		opts = {
            -- default options :
			SourceExtensions = { ".cpp", ".c", ".cc", ".cxx" },
			RootMarkers = { ".git", "src", "include", "build", "Makefile" },
			MaxSearchLevels = 5,
			CacheUseHash = true,
			CacheFormat = "luabytecode", -- or "mpack"
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
			},
		},
	},

```


## Usage

- `:Make` (main command)
- Examples:
  - `:Make add`
  - `:Make edit`
  - `:Make run`
  - `:Make build`
  - `:Make clean`
  - `:Make link`

## Dependencies

- `nvim-telescope/telescope.nvim` (optional; highly recommended ! richer picker UI). Falls back to `vim.ui.select` if not installed.

