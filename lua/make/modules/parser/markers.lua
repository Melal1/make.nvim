local Utils = require("make.shared.utils") -- shared helpers

local M = {} -- module table

function M.normalize_lines(content) -- normalize content into a line list
	if type(content) == "table" then -- already a list of lines
		return content -- return as-is
	end
	if not content or content == "" then -- handle nil/empty input
		return {} -- return empty list
	end
	return vim.split(content, "\n", { plain = true, trimempty = false }) -- split into lines
end

function M.slice_lines(lines, start_line, end_line, return_table) -- slice lines between markers
	local out = {} -- output container
	if not lines or #lines == 0 then -- nothing to slice
		return return_table and out or "" -- return empty table or string
	end
	for i = start_line + 1, end_line - 1 do -- skip marker lines themselves
		table.insert(out, lines[i] or "") -- append line or empty string
	end
	if return_table then -- return as table if requested
		return out
	end
	return table.concat(out, "\n") -- join into string
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
function M.FindMarker(Content, RelativePath, CheckStart, CheckEnd) -- find marker boundaries for a file
	local info = { M_start = nil, M_end = nil, type = nil, name = nil } -- default result
	local escapedPath = Utils.EscapePattern(RelativePath) -- escape for pattern matching
	if not CheckStart then -- caller does not need start
		info.M_start = -1 -- sentinel for "skip"
	end
	if not CheckEnd then -- caller does not need end
		info.M_end = -1 -- sentinel for "skip"
	end

	if info.M_start == -1 and info.M_end == -1 then -- nothing to search
		return info
	end

	local lines = M.normalize_lines(Content) -- normalize content
	for lineNumber, line in ipairs(lines) do -- iterate lines
		local trimmedLine = line:match("^%s*(.-)%s*$") -- trim whitespace
		if not trimmedLine:match("^%s*#") or trimmedLine == "" then -- skip non-comment/empty
			goto continue
		end
		if not info.M_start and CheckStart then -- start not found yet
			local markerMatch = trimmedLine:match("^%s*#%s*marker_start%s*:%s*" .. escapedPath .. "(.*)$") -- match start
			if markerMatch then
				info.M_start = lineNumber -- record start line
				local typeAnnotation = markerMatch:match("%s+type:(%S+)") -- optional type
				if typeAnnotation then
					info.type = typeAnnotation -- store type
				end
				local nameAnnotation = markerMatch:match("%s+name:(%S+)") -- optional name
				if nameAnnotation then
					info.name = nameAnnotation -- store name
				end
				if not CheckEnd then -- return early if end not needed
					return info
				end
			end
		end
		if not info.M_end and info.M_start and CheckEnd then -- end not found yet
			if trimmedLine:match("^%s*#%s*marker_end%s*:%s*" .. escapedPath) then -- match end
				info.M_end = lineNumber -- record end line
				return info -- return once both found
			end
		end
		::continue:: -- loop continue label
	end
	return info -- return even if incomplete
end

---@class MarkerPair
---@field path string
---@field StartLine integer
---@field EndLine integer
---@field annotatedType string|nil
---@field name string|nil

---@param Content string|table|nil
---@return MarkerPair[]
function M.FindAllMarkerPairs(Content) -- find all marker start/end pairs
	local allPairs = {} -- output list
	local openMarkers = {} -- active start markers
	local lines = M.normalize_lines(Content) -- normalize input
	if #lines == 0 then -- nothing to scan
		return allPairs
	end
	for lineNumber, line in ipairs(lines) do -- iterate lines
		local trimmedLine = line:match("^%s*(.-)%s*$") -- trim whitespace
		if trimmedLine:match("^%s*#") then -- only marker comments matter
			local startMatch = trimmedLine:match("^%s*#%s*marker_start%s*:%s*(.*)$") -- detect start marker
			if startMatch then
				local path = startMatch:match("^(%S+)") -- extract path
				local typeAnnotation = startMatch:match("%s+type:(%S+)") -- optional type
				local nameAnnotation = startMatch:match("%s+name:(%S+)") -- optional name
				openMarkers[path] = { line = lineNumber, type = typeAnnotation, name = nameAnnotation } -- store start
			end
			local endPath = trimmedLine:match("^%s*#%s*marker_end%s*:%s*(.*)$") -- detect end marker
			if endPath then
				endPath = endPath:match("^(%S+)") -- extract path
				local markerData = openMarkers[endPath] -- get matching start
				if markerData then
					table.insert(allPairs, { -- record pair
						path = endPath,
						StartLine = markerData.line,
						EndLine = lineNumber,
						annotatedType = markerData.type,
						name = markerData.name,
					})
					openMarkers[endPath] = nil -- clear open marker
				end
			end
		end
	end
	return allPairs -- return all pairs
end

---@param Content string
---@param StartLine integer
---@param EndLine integer
---@param ReturnTable boolean?
---@return string|string[]
function M.ReadContentBetweenLines(Content, StartLine, EndLine, ReturnTable) -- read between line numbers
	ReturnTable = not not ReturnTable -- normalize to boolean
	local lines = M.normalize_lines(Content) -- normalize content
	return M.slice_lines(lines, StartLine, EndLine, ReturnTable) -- slice lines
end

---@param Content string
---@param RelativePath string
---@param ReturnTable boolean?
---@return string|string[]
function M.ReadContentBetweenMarkers(Content, RelativePath, ReturnTable) -- read between markers
	ReturnTable = not not ReturnTable -- normalize to boolean
	local lines = M.normalize_lines(Content) -- normalize content
	local markerInfo = M.FindMarker(lines, RelativePath, true, true) -- find marker positions
	local StartLine = markerInfo.M_start -- start line
	local EndLine = markerInfo.M_end -- end line
	if StartLine == -1 or EndLine == -1 then -- marker missing
		return "" -- return empty string
	end
	return M.slice_lines(lines, StartLine, EndLine, ReturnTable) -- slice between markers
end

---@param Content string|nil
---@param RelativePath string
---@return boolean
function M.TargetExists(Content, RelativePath) -- check if a marker exists
	if not Content then -- nothing to scan
		return false
	end
	local markerInfo = M.FindMarker(Content, RelativePath, true, false) -- find start marker only
	return markerInfo.M_start ~= nil -- true if found
end

return M -- export module
