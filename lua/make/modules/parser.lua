---@module "make.modules.parser"
local Parser = {}

Parser.CacheRoot = nil
Parser.CacheMakefilePath = nil
Parser.CacheLog = false
Parser.CacheUseHash = true
Parser.CacheFormat = "mpack"
Parser.CacheDir = ".cache/make.nvim"

local Cache = require("make.modules.parser.cache").setup(Parser)
local Markers = require("make.modules.parser.markers")
local Analysis = require("make.modules.parser.analysis").build({
	cache = Cache,
	markers = Markers,
})
local Report = require("make.modules.parser.report").build({
	analysis = Analysis,
	markers = Markers,
})

Parser.SetCacheRoot = Cache.SetCacheRoot
Parser.ParseVariables = Cache.ParseVariables
Parser.ParseLinkOptions = Cache.ParseLinkOptions
Parser.GetCachedTargetLinks = Cache.GetCachedTargetLinks

Parser.FindMarker = Markers.FindMarker
Parser.FindAllMarkerPairs = Markers.FindAllMarkerPairs
Parser.ReadContentBetweenLines = Markers.ReadContentBetweenLines
Parser.ReadContentBetweenMarkers = Markers.ReadContentBetweenMarkers
Parser.TargetExists = Markers.TargetExists

Parser.ParseDependencies = Analysis.ParseDependencies
Parser.ParseTarget = Analysis.ParseTarget
Parser.FindExecutableTargetName = Analysis.FindExecutableTargetName
Parser.GetLinksForTarget = Analysis.GetLinksForTarget
Parser.DetectTargetTypes = Analysis.DetectTargetTypes
Parser.AnalyzeSection = Analysis.AnalyzeSection
Parser.AnalyzeAllSections = Analysis.AnalyzeAllSections
Parser.GetSectionsByType = Analysis.GetSectionsByType
Parser.ScanTargets = Analysis.ScanTargets
Parser.TargetKind = Analysis.TargetKind
Parser.IsObjectTargetName = Analysis.IsObjectTargetName

Parser.PrintAnalysisSummary = Report.PrintAnalysisSummary

---@param Content string|nil
---@param MakefileVars MakefileVars
---@return boolean
function Parser.HasReqVars(Content, MakefileVars)
	if not Content then
		return false
	end
	local Variables = Parser.ParseVariables(Content)
	for VarName, _ in pairs(MakefileVars) do
		if not Variables[VarName] then
			return false
		end
	end
	return true
end

return Parser
