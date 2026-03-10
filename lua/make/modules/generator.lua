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
	local Vars = vim.tbl_deep_extend("force", {}, MakefileVars or {})
	if not Vars.BUILD_OUT or Vars.BUILD_OUT == "" then
		Vars.BUILD_OUT = "$(BUILD_DIR)/$(BUILD_MODE)"
	end

	for VarName, VarValue in pairs(Vars) do
		table.insert(Lines, VarName .. " = " .. VarValue)
	end

	table.insert(Lines, "$(shell mkdir -p $(BUILD_OUT))")
	table.insert(Lines, "")

	return Lines
end

---Generate an object target rule for a single source file.
---@param RelativePath string       Relative path to the source file
---@param MakefileVars MakefileVars Makefile variables table
---@return string[]
function Generator.ObjectTarget(RelativePath, MakefileVars)
	local flat_name = Utils.FlattenRelativePath(RelativePath)
	local ObjName = "$(BUILD_OUT)/" .. flat_name .. ".o"
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
---@param RelativePath string             Relative path to the source file
---@param Dependencies string[]|nil       Optional list of header dependencies
---@param MakefileVars MakefileVars       Makefile variables table
---@param RootPath string                 Root search path for includes
---@param Links string[]|nil              Optional list of linker flags
---@param TargetName string|nil           Optional executable name override (no path separators)
---@return string[] lines_or_missing
---@return boolean success                Whether generation succeeded
function Generator.ExecutableTarget(RelativePath, Dependencies, MakefileVars, RootPath, Links, TargetName)
	Dependencies = Dependencies or {}
	Links = Links or {}
	local flat_name = Utils.FlattenRelativePath(RelativePath)
	local target_key = Utils.SanitizeTargetName(TargetName or "")
	if target_key == "" then
		target_key = flat_name
	end
	local ObjName = "$(BUILD_OUT)/" .. flat_name .. ".o"
	local ExeName = "$(BUILD_OUT)/" .. target_key
	local RunName = "run_" .. target_key
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
		if not Dep:match("%.o%s*$") then
			local IncludePath = Finder.FindHeaderDirectory(vim.fn.fnamemodify(Dep, ":t:r"), RootPath)
			if IncludePath then
				if not InTable(Include, "-I" .. IncludePath) then
					table.insert(Include, "-I" .. IncludePath)
				end
			else
				table.insert(UnFoundIncludePath, Dep)
			end
		end
	end

	if #UnFoundIncludePath > 0 then
		-- return `nil` second value (list of missing includes)
		return UnFoundIncludePath, false
	end

	local IncludeStr = table.concat(Include, " ")
	local LinkDepsStr = table.concat(LinkDeps, " ")
	local LinksStr = table.concat(Links, " ")

	local marker_line = "# marker_start: " .. RelativePath .. " type:full"
	if target_key ~= flat_name then
		marker_line = marker_line .. " name:" .. target_key
	end

	local lines = { "", marker_line, ObjName .. ": " .. RelativePath }
	table.insert(lines, "\t" .. CompilerVar .. " " .. FlagsVar .. " " .. IncludeStr .. " -c $< -o $@")
	table.insert(lines, "")

	if LinksStr ~= "" then
		table.insert(lines, ExeName .. ": LINKS += " .. LinksStr)
	end

	table.insert(lines, ExeName .. ": " .. ObjName .. (LinkDepsStr ~= "" and " " .. LinkDepsStr or ""))
	table.insert(lines, "\t" .. CompilerVar .. " $^ -o $@ $(LINKS)")
	table.insert(lines, "")
	table.insert(lines, RunName .. ": " .. ExeName)
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
	local Vars = vim.tbl_deep_extend("force", {}, MakefileVars or {})
	if not Vars.BUILD_OUT or Vars.BUILD_OUT == "" then
		Vars.BUILD_OUT = "$(BUILD_DIR)/$(BUILD_MODE)"
	end
	if Parser.HasReqVars(Content, Vars) then
		return true
	end

	local VarLines = Generator.GenerateMakefileVariables(Vars)
	local NewContent = table.concat(VarLines, "\n") .. (Content or "")

	local Success, WriteErr = Utils.WriteFile(MakefilePath, NewContent)
	if not Success then
		Utils.Notify("Failed to write Makefile: " .. WriteErr, vim.log.levels.ERROR)
		return nil
	end
	return false
end

return Generator
