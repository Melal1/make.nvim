local Utils = require("make.shared.utils")

local M = {}

function M.normalize_lines(content)
	if type(content) == "table" then
		return content
	end
	if not content or content == "" then
		return {}
	end
	return vim.split(content, "\n", { plain = true, trimempty = false })
end

function M.slice_lines(lines, start_line, end_line, return_table)
	local out = {}
	if not lines or #lines == 0 then
		return return_table and out or ""
	end
	for i = start_line + 1, end_line - 1 do
		table.insert(out, lines[i] or "")
	end
	if return_table then
		return out
	end
	return table.concat(out, "\n")
end

---@class MarkerInfo
---@field M_start integer|nil
---@field M_end integer|nil
---@field type string|nil
---@field name string|nil

---@param Content string|table
---@param RelativePath string
---@param CheckStart boolean
---@param CheckEnd boolean
---@return MarkerInfo
function M.FindMarker(Content, RelativePath, CheckStart, CheckEnd)
	local info = { M_start = nil, M_end = nil, type = nil, name = nil }
	local escapedPath = Utils.EscapePattern(RelativePath)
	if not CheckStart then
		info.M_start = -1
	end
	if not CheckEnd then
		info.M_end = -1
	end

	if info.M_start == -1 and info.M_end == -1 then
		return info
	end

	local lines = M.normalize_lines(Content)
	for lineNumber, line in ipairs(lines) do
		local trimmedLine = line:match("^%s*(.-)%s*$")
		if not trimmedLine:match("^%s*#") or trimmedLine == "" then
			goto continue
		end
		if not info.M_start and CheckStart then
			local markerMatch = trimmedLine:match("^%s*#%s*marker_start%s*:%s*" .. escapedPath .. "(.*)$")
			if markerMatch then
				info.M_start = lineNumber
				-- Extract type if present
				local typeAnnotation = markerMatch:match("%s+type:(%S+)")
				if typeAnnotation then
					info.type = typeAnnotation
				end
				local nameAnnotation = markerMatch:match("%s+name:(%S+)")
				if nameAnnotation then
					info.name = nameAnnotation
				end
				if not CheckEnd then
					return info
				end
			end
		end
		if not info.M_end and info.M_start and CheckEnd then
			if trimmedLine:match("^%s*#%s*marker_end%s*:%s*" .. escapedPath) then
				info.M_end = lineNumber
				return info
			end
		end
		::continue::
	end
	return info
end

---@class MarkerPair
---@field path string
---@field StartLine integer
---@field EndLine integer
---@field annotatedType string|nil
---@field name string|nil

---@param Content string|table|nil
---@return MarkerPair[]
function M.FindAllMarkerPairs(Content)
	local allPairs = {}
	local openMarkers = {}
	local lines = M.normalize_lines(Content)
	if #lines == 0 then
		return allPairs
	end
	for lineNumber, line in ipairs(lines) do
		local trimmedLine = line:match("^%s*(.-)%s*$")
		if trimmedLine:match("^%s*#") then
			local startMatch = trimmedLine:match("^%s*#%s*marker_start%s*:%s*(.*)$")
			if startMatch then
				local path = startMatch:match("^(%S+)")
				local typeAnnotation = startMatch:match("%s+type:(%S+)")
				local nameAnnotation = startMatch:match("%s+name:(%S+)")
				openMarkers[path] = { line = lineNumber, type = typeAnnotation, name = nameAnnotation }
			end
			local endPath = trimmedLine:match("^%s*#%s*marker_end%s*:%s*(.*)$")
			if endPath then
				endPath = endPath:match("^(%S+)")
				local markerData = openMarkers[endPath]
				if markerData then
					table.insert(allPairs, {
						path = endPath,
						StartLine = markerData.line,
						EndLine = lineNumber,
						annotatedType = markerData.type,
						name = markerData.name,
					})
					openMarkers[endPath] = nil
				end
			end
		end
	end
	return allPairs
end

---@param Content string
---@param StartLine integer
---@param EndLine integer
---@param ReturnTable boolean?
---@return string|string[]
function M.ReadContentBetweenLines(Content, StartLine, EndLine, ReturnTable)
	ReturnTable = not not ReturnTable
	local lines = M.normalize_lines(Content)
	return M.slice_lines(lines, StartLine, EndLine, ReturnTable)
end

---@param Content string
---@param RelativePath string
---@param ReturnTable boolean?
---@return string|string[]
function M.ReadContentBetweenMarkers(Content, RelativePath, ReturnTable)
	ReturnTable = not not ReturnTable
	local lines = M.normalize_lines(Content)
	local markerInfo = M.FindMarker(lines, RelativePath, true, true)
	local StartLine = markerInfo.M_start
	local EndLine = markerInfo.M_end
	if StartLine == -1 or EndLine == -1 then
		return ""
	end
	return M.slice_lines(lines, StartLine, EndLine, ReturnTable)
end

---@param Content string|nil
---@param RelativePath string
---@return boolean
function M.TargetExists(Content, RelativePath)
	if not Content then
		return false
	end
	local markerInfo = M.FindMarker(Content, RelativePath, true, false)
	return markerInfo.M_start ~= nil
end

return M
