---@module "make.modules.generator"

local Utils = require("make.shared.utils")
local Parser = require("make.modules.parser")
local Finder = require("make.shared.finder")

local Generator = {}

---Generate lines for required Makefile variables.
---@param MakefileVars MakefileVars
---@return string[]
function Generator.GenerateMakefileVariables(MakefileVars)
	local Lines = {}

	for VarName, VarValue in pairs(MakefileVars) do
		table.insert(Lines, VarName .. " = " .. VarValue)
	end

	table.insert(Lines, "$(shell mkdir -p $(BUILD_DIR)/$(BUILD_MODE))")
	table.insert(Lines, "")

	return Lines
end

---Generate an object target rule for a single source file.
---@param Basename string           Basename without extension
---@param RelativePath string       Relative path to the source file
---@param MakefileVars MakefileVars Makefile variables table
---@return string[]
function Generator.ObjectTarget(Basename, RelativePath, MakefileVars)
	local ObjName = "$(BUILD_DIR)/$(BUILD_MODE)/" .. Basename .. ".o"
	local CompilerVar = MakefileVars.CC and "$(CC)" or "$(CXX)"
	local FlagsVar = MakefileVars.CFLAGS and "$(CFLAGS)" or "$(CXXFLAGS)"

	return {
		"",
		"# marker_start: " .. RelativePath .. " type:obj",
		ObjName .. ": " .. RelativePath,
		"\t" .. CompilerVar .. " " .. FlagsVar .. " -c $< -o $@",
		"# marker_end: " .. RelativePath,
	}
end

---Generate full compilation & linking rule for an executable target.
---@param Basename string                 Basename of the source file
---@param RelativePath string             Relative path to the source file
---@param Dependencies string[]|nil       Optional list of header dependencies
---@param MakefileVars MakefileVars       Makefile variables table
---@param RootPath string                 Root search path for includes
---@param Links string[]|nil              Optional list of linker flags
---@return string[] lines_or_missing
---@return boolean success                Whether generation succeeded
function Generator.ExecutableTarget(Basename, RelativePath, Dependencies, MakefileVars, RootPath, Links)
	Dependencies = Dependencies or {}
	Links = Links or {}
	local ObjName = "$(BUILD_DIR)/$(BUILD_MODE)/" .. Basename .. ".o"
	local ExeName = "$(BUILD_DIR)/$(BUILD_MODE)/" .. Basename
	local CompilerVar = MakefileVars.CC and "$(CC)" or "$(CXX)"
	local FlagsVar = MakefileVars.CFLAGS and "$(CFLAGS)" or "$(CXXFLAGS)"

	local LinkDeps = {}
	local Include = {}
	local UnFoundIncludePath = {}
	---@param Table string[]
	---@param Target string
	---@return boolean found
	local function InTable(Table, Target)
		for _, Ent in ipairs(Table) do
			if Ent == Target then
				return true
			end
		end
		return false
	end

	for _, Dep in ipairs(Dependencies) do
		table.insert(LinkDeps, Dep)
		local IncludePath = Finder.FindHeaderDirectory(vim.fn.fnamemodify(Dep, ":t:r"), RootPath)
		if IncludePath then
			if not InTable(Include, "-I" .. IncludePath) then
				table.insert(Include, "-I" .. IncludePath)
			end
		else
			table.insert(UnFoundIncludePath, Dep)
		end
	end

	if #UnFoundIncludePath > 0 then
		-- return `nil` second value (list of missing includes)
		return UnFoundIncludePath, false
	end

	local IncludeStr = table.concat(Include, " ")
	local LinkDepsStr = table.concat(LinkDeps, " ")
	local LinksStr = table.concat(Links, " ")

	local lines = {
		"",
		"# marker_start: " .. RelativePath .. " type:full",
		ObjName .. ": " .. RelativePath,
		"\t" .. CompilerVar .. " " .. FlagsVar .. " " .. IncludeStr .. " -c $< -o $@",
		"",
	}

	if LinksStr ~= "" then
		table.insert(lines, ExeName .. ": LINKS += " .. LinksStr)
	end

	table.insert(lines, ExeName .. ": " .. ObjName .. (LinkDepsStr ~= "" and " " .. LinkDepsStr or ""))
	table.insert(lines, "\t" .. CompilerVar .. " $^ -o $@ $(LINKS)")
	table.insert(lines, "")
	table.insert(lines, "run" .. Basename .. ": " .. ExeName)
	table.insert(lines, "\t" .. ExeName)
	table.insert(lines, "# marker_end: " .. RelativePath)

	return lines,
		true
end

---Ensure the required Makefile variables are present in the file content will return true if it there false if it's not nil for failing
---@param MakefilePath string
---@param Content string|nil
---@param MakefileVars MakefileVars
---@return boolean|nil success
function Generator.EnsureMakefileVariables(MakefilePath, Content, MakefileVars)
	if Parser.HasReqVars(Content, MakefileVars) then
		return true
	end

	local VarLines = Generator.GenerateMakefileVariables(MakefileVars)
	local NewContent = table.concat(VarLines, "\n") .. (Content or "")

	local Success, WriteErr = Utils.WriteFile(MakefilePath, NewContent)
	if not Success then
		Utils.Notify("Failed to write Makefile: " .. WriteErr, vim.log.levels.ERROR)
		return nil
	end
	return false
end

return Generator
