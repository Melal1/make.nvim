---@class TelescopeEntry
---@field value any
---@field display? string
---@field ordinal? string|number
---@field preview_text? string|string[]

---@class TelescopePickerOpts
---@field prompt_title? string
---@field theme? string
---@field initial_mode? string
---@field entry_maker? fun(entry: TelescopeEntry): table
---@field sorter_opts? table
---@field previewer? table
---@field mappings? table<string, table<string, fun(bufnr: number)>>
---@field show_hints? boolean
---@field allow_single_fallback? boolean
---@field preselected_items? any[]
---@field selection_strategy? "replace"|"toggle"

---@class TelescopePickerModule
---@field available boolean
---@field backend? string
local M = {}

local DEFAULT_OPTS = {
	prompt_title = "Select entries",
	theme = "dropdown",
	initial_mode = "normal",
}

---@param entries any
---@return TelescopeEntry[]|nil, string|nil
local function normalize_entries(entries)
	if type(entries) ~= "table" then
		return nil, "Entries must be a table"
	end

	if #entries == 0 then
		return nil, "Entries table is empty"
	end

	local normalized_entries = {}
	for i, entry in ipairs(entries) do
		if type(entry) == "string" then
			table.insert(normalized_entries, { value = entry, display = entry, ordinal = entry })
		elseif type(entry) == "table" and entry.value ~= nil then
			local normalized = {}
			for k, v in pairs(entry) do
				normalized[k] = v
			end
			if normalized.display == nil then
				normalized.display = normalized.value
			end
			if normalized.ordinal == nil then
				normalized.ordinal = normalized.display
			end
			table.insert(normalized_entries, normalized)
		else
			return nil, string.format("Invalid entry at index %d", i)
		end
	end

	return normalized_entries, nil
end

local function format_entry(entry)
	if type(entry) == "table" then
		return entry.display or entry.value or ""
	end
	return tostring(entry)
end

local function entry_value(entry)
	if type(entry) == "table" then
		return entry.value
	end
	return entry
end

local function split_preselected(entries, preselected_items)
	local preselected_map = {}
	for _, item in ipairs(preselected_items or {}) do
		preselected_map[item] = true
	end

	local preselected_list = {}
	local remaining_list = {}
	for _, entry in ipairs(entries) do
		if preselected_map[entry.value] then
			table.insert(preselected_list, entry)
		else
			table.insert(remaining_list, entry)
		end
	end

	return preselected_list, remaining_list, preselected_map
end

local has_telescope, pickers = pcall(require, "telescope.pickers")
if not has_telescope then
	M.available = true
	M.backend = "vimui"

	function M.text_per_entry_previewer()
		return nil
	end

	---@param entries any
	---@param callback fun(selection: any|nil)
	---@param opts TelescopePickerOpts|nil
	---@return boolean, string|nil
	function M.pick_single(entries, callback, opts)
		local normalized_entries, err = normalize_entries(entries)
		if not normalized_entries then
			if callback then
				callback(nil)
			end
			return false, err
		end

		opts = vim.tbl_deep_extend("force", DEFAULT_OPTS, opts or {})
		local prompt = opts.prompt_title or DEFAULT_OPTS.prompt_title

		if vim.ui and vim.ui.select then
			vim.ui.select(normalized_entries, {
				prompt = prompt,
				format_item = format_entry,
			}, function(choice)
				if callback then
					callback(choice and entry_value(choice) or nil)
				end
			end)
			return true, "Single-select picker opened successfully"
		end

		local lines = { prompt }
		for i, entry in ipairs(normalized_entries) do
			table.insert(lines, string.format("%d: %s", i, format_entry(entry)))
		end
		local idx = vim.fn.inputlist(lines)
		if idx < 1 or idx > #normalized_entries then
			if callback then
				callback(nil)
			end
			return false, "Selection cancelled"
		end
		if callback then
			callback(entry_value(normalized_entries[idx]))
		end
		return true, "Single-select picker opened successfully"
	end

	---@param entries any
	---@param callback fun(selections: any[])
	---@param opts TelescopePickerOpts|nil
	---@return boolean, string|nil
	function M.pick_multi(entries, callback, opts)
		local normalized_entries, err = normalize_entries(entries)
		if not normalized_entries then
			if callback then
				callback({})
			end
			return false, err
		end

		opts = vim.tbl_deep_extend("force", DEFAULT_OPTS, opts or {})
		local prompt_title = opts.prompt_title or DEFAULT_OPTS.prompt_title
		local preselected_list, remaining_list = split_preselected(normalized_entries, opts.preselected_items)

		local selected = {}
		local selected_map = {}
		for _, entry in ipairs(preselected_list) do
			selected_map[entry.value] = true
			table.insert(selected, entry.value)
		end

		if #remaining_list == 0 then
			if callback then
				callback(selected)
			end
			return true, "Multi-select picker opened successfully"
		end

		if vim.ui and vim.ui.select then
			local function done()
				if callback then
					callback(selected)
				end
			end

			local function step()
				local items = {}
				table.insert(items, { value = "__DONE__", display = "(Done)" })
				if #remaining_list > 0 then
					table.insert(items, { value = "__ALL__", display = "(All remaining)" })
				end
				for _, entry in ipairs(remaining_list) do
					table.insert(items, entry)
				end

				local prompt = prompt_title
				if #selected > 0 then
					prompt = string.format("%s (%d selected)", prompt_title, #selected)
				end

				vim.ui.select(items, {
					prompt = prompt,
					format_item = format_entry,
				}, function(choice)
					if not choice or choice.value == "__DONE__" then
						return done()
					end

					if choice.value == "__ALL__" then
						for _, entry in ipairs(remaining_list) do
							if not selected_map[entry.value] then
								selected_map[entry.value] = true
								table.insert(selected, entry.value)
							end
						end
						return done()
					end

					local value = entry_value(choice)
					if value ~= nil and not selected_map[value] then
						selected_map[value] = true
						table.insert(selected, value)
						for i, entry in ipairs(remaining_list) do
							if entry.value == value then
								table.remove(remaining_list, i)
								break
							end
						end
					end

					if #remaining_list == 0 then
						return done()
					end
					step()
				end)
			end

			step()
			return true, "Multi-select picker opened successfully"
		end

		local lines = { prompt_title, "Enter numbers separated by space or comma:" }
		for i, entry in ipairs(normalized_entries) do
			table.insert(lines, string.format("%d: %s", i, format_entry(entry)))
		end
		local input = vim.fn.input(table.concat(lines, "\n") .. "\n> ")
		input = vim.trim(input or "")
		if input == "" then
			if callback then
				callback(selected)
			end
			return true, "Multi-select picker opened successfully"
		end

		local chosen = {}
		for token in input:gmatch("[^,%s]+") do
			local idx = tonumber(token)
			if idx and normalized_entries[idx] then
				local value = entry_value(normalized_entries[idx])
				if value ~= nil and not chosen[value] then
					chosen[value] = true
					table.insert(selected, value)
				end
			end
		end

		if callback then
			callback(selected)
		end
		return true, "Multi-select picker opened successfully"
	end

	---@param entries any
	---@param callback fun(selection: any|nil)
	function M.pick_single_simple(entries, callback)
		return M.pick_single(entries, callback, {
			theme = "dropdown",
			initial_mode = "normal",
		})
	end

	---@param entries any
	---@param callback fun(selections: any[])
	function M.pick_multi_simple(entries, callback)
		return M.pick_multi(entries, callback, {
			theme = "dropdown",
			initial_mode = "normal",
			show_hints = true,
			allow_single_fallback = false,
		})
	end

	---@param entries any
	---@param callback fun(selection: any|nil)
	---@param opts TelescopePickerOpts|nil
	function M.pick_single_with_preview(entries, callback, opts)
		return M.pick_single(entries, callback, opts)
	end

	---@param entries any
	---@param callback fun(selections: any[])
	---@param opts TelescopePickerOpts|nil
	function M.pick_multi_with_preview(entries, callback, opts)
		return M.pick_multi(entries, callback, opts)
	end

	---@param entries any
	---@param callback fun(selections: any[])
	---@param opts TelescopePickerOpts|nil
	function M.pick_entries(entries, callback, opts)
		return M.pick_multi(entries, callback, opts)
	end

	---@param options any
	---@param callback fun(selection: any|nil)
	---@param opts TelescopePickerOpts|nil
	function M.pick_option(options, callback, opts)
		opts = opts or {}
		opts.prompt_title = opts.prompt_title or "Select option"
		return M.pick_single(options, callback, opts)
	end

	---@param menu_items any
	---@param callback fun(selection: any|nil)
	---@param opts TelescopePickerOpts|nil
	function M.pick_menu(menu_items, callback, opts)
		opts = opts or {}
		opts.prompt_title = opts.prompt_title or "Select action"
		return M.pick_single(menu_items, callback, opts)
	end

	---@param items any
	---@param callback fun(selections: any[])
	---@param opts TelescopePickerOpts|nil
	function M.pick_checklist(items, callback, opts)
		opts = opts or {}
		opts.prompt_title = opts.prompt_title or "Select items"
		opts.show_hints = opts.show_hints ~= false
		return M.pick_multi(items, callback, opts)
	end

	return M
end

M.available = true
M.backend = "telescope"

local previewers = require("telescope.previewers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local themes = require("telescope.themes")

---@param theme_name string
---@param theme_opts table|nil
---@return table
local function get_theme_config(theme_name, theme_opts)
	local theme_func = themes["get_" .. theme_name]
	if not theme_func then
		theme_func = themes.get_dropdown
	end
	return theme_func(theme_opts or {})
end

---@param custom_maker fun(entry: TelescopeEntry): table|nil
---@return fun(entry: TelescopeEntry): table
local function create_entry_maker(custom_maker)
	if custom_maker then
		return custom_maker
	end

	return function(entry)
		return {
			value = entry.value or entry,
			display = entry.display or entry.value or entry,
			ordinal = entry.ordinal or entry.display or entry.value or entry,
		}
	end
end

---@param lang string|nil
---@return table
function M.text_per_entry_previewer(lang)
	return previewers.new_buffer_previewer({
		define_preview = function(self, entry)
			local lines = {}

			if entry.preview_text then
				if type(entry.preview_text) == "table" then
					for _, line in ipairs(entry.preview_text) do
						table.insert(lines, tostring(line))
					end
				elseif type(entry.preview_text) == "string" then
					for line in entry.preview_text:gmatch("([^\n]*)\n?") do
						table.insert(lines, line)
					end
				else
					table.insert(lines, "Invalid preview_text type")
				end
			else
				table.insert(lines, "No preview available")
			end

			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
			vim.api.nvim_set_option_value("filetype", lang or "lua", { buf = self.state.bufnr })
		end,
	})
end

---@param entries any
---@param callback fun(selection: any|nil)
---@param opts TelescopePickerOpts|nil
---@return boolean, string|nil
function M.pick_single(entries, callback, opts)
	local normalized_entries, err = normalize_entries(entries)
	if not normalized_entries then
		if callback then
			callback(nil)
		end
		return false, err
	end

	opts = vim.tbl_deep_extend("force", DEFAULT_OPTS, opts or {})

	local picker_opts = {
		prompt_title = opts.prompt_title,
		finder = finders.new_table({
			results = normalized_entries,
			entry_maker = create_entry_maker(opts.entry_maker),
		}),
		sorter = conf.generic_sorter(opts.sorter_opts or {}),
		previewer = opts.previewer,
		attach_mappings = function(prompt_bufnr, map)
			if opts.mappings then
				for mode, mode_mappings in pairs(opts.mappings) do
					for key, action in pairs(mode_mappings) do
						map(mode, key, action)
					end
				end
			end

			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)

				local result = selection and selection.value or nil

				if callback then
					callback(result)
				end
			end)

			return true
		end,
	}

	local theme_config = get_theme_config(opts.theme, { initial_mode = opts.initial_mode })
	pickers.new(theme_config, picker_opts):find()

	return true, "Single-select picker opened successfully"
end

---@param entries any
---@param callback fun(selections: any[])
---@param opts TelescopePickerOpts|nil
---@return boolean, string|nil
function M.pick_multi(entries, callback, opts)
	local normalized_entries, err = normalize_entries(entries)
	if not normalized_entries then
		if callback then
			callback({})
		end
		return false, err
	end

	opts = vim.tbl_deep_extend("force", DEFAULT_OPTS, opts or {})

	local prompt_title = opts.show_hints ~= false
		and string.format("%s (<Tab> toggle, <C-a> toggle all)", opts.prompt_title)
		or opts.prompt_title

	local function toggle_all(prompt_bufnr)
		local picker = action_state.get_current_picker(prompt_bufnr)
		local manager = picker.manager
		local selections = picker:get_multi_selection()

		if #selections == #manager.entries then
			for i = 1, #manager.entries do
				picker:remove_selection(i)
			end
		else
			for i = 1, #manager.entries do
				picker:add_selection(i)
			end
		end
		picker:refresh_previewer()
	end

	local preselected_list, remaining_list, preselected_map = split_preselected(normalized_entries, opts.preselected_items)
	local sorted_entries = vim.list_extend(preselected_list, remaining_list)

	local sorter
	if opts.preselected_items and #opts.preselected_items > 0 then
		sorter = false
	else
		sorter = conf.generic_sorter(opts.sorter_opts or {})
	end

	local picker_opts = {
		prompt_title = prompt_title,
		finder = finders.new_table({
			results = sorted_entries,
			entry_maker = create_entry_maker(opts.entry_maker),
		}),
		sorter = sorter,
		previewer = opts.previewer,
		attach_mappings = function(prompt_bufnr, map)
			map("n", "<Tab>", actions.toggle_selection)
			map("i", "<Tab>", actions.toggle_selection)
			map("n", "<C-a>", toggle_all)
			map("i", "<C-a>", toggle_all)

			if opts.selection_strategy == "replace" then
				map("n", "<C-t>", actions.toggle_selection)
				map("i", "<C-t>", actions.toggle_selection)
			end

			if opts.mappings then
				for mode, mode_mappings in pairs(opts.mappings) do
					for key, action in pairs(mode_mappings) do
						map(mode, key, action)
					end
				end
			end

			actions.select_default:replace(function()
				local picker = action_state.get_current_picker(prompt_bufnr)
				local selections = picker:get_multi_selection()
				local current_selection = action_state.get_selected_entry()

				actions.close(prompt_bufnr)

				local result = {}

				if #selections == 0 and current_selection and opts.allow_single_fallback then
					table.insert(result, current_selection.value)
				else
					for _, selection in ipairs(selections) do
						table.insert(result, selection.value)
					end
				end

				if callback then
					callback(result)
				end
			end)

			return true
		end,
	}

	local theme_config = get_theme_config(opts.theme, { initial_mode = opts.initial_mode })
	local picker = pickers.new(theme_config, picker_opts)

	picker:register_completion_callback(function()
		for idx, entry in ipairs(sorted_entries) do
			if preselected_map[entry.value] then
				picker:add_selection(idx - 1)
			end
		end
	end)

	picker:find()
	return true, "Multi-select picker opened successfully"
end

---@param entries any
---@param callback fun(selection: any|nil)
---@return boolean, string|nil
function M.pick_single_simple(entries, callback)
	return M.pick_single(entries, callback, {
		theme = "dropdown",
		initial_mode = "normal",
	})
end

---@param entries any
---@param callback fun(selections: any[])
---@return boolean, string|nil
function M.pick_multi_simple(entries, callback)
	return M.pick_multi(entries, callback, {
		theme = "dropdown",
		initial_mode = "normal",
		show_hints = true,
		allow_single_fallback = false,
	})
end

---@param entries any
---@param callback fun(selection: any|nil)
---@param opts TelescopePickerOpts|nil
---@return boolean, string|nil
function M.pick_single_with_preview(entries, callback, opts)
	opts = opts or {}
	opts.previewer = opts.previewer or conf.file_previewer(opts)
	return M.pick_single(entries, callback, opts)
end

---@param entries any
---@param callback fun(selections: any[])
---@param opts TelescopePickerOpts|nil
---@return boolean, string|nil
function M.pick_multi_with_preview(entries, callback, opts)
	opts = opts or {}
	opts.previewer = opts.previewer or conf.file_previewer(opts)
	opts.entry_maker = opts.entry_maker or function(entry)
		return {
			value = entry.value,
			display = entry.display or entry.value,
			ordinal = entry.display or entry.value,
			preview_text = entry.preview_text,
		}
	end
	return M.pick_multi(entries, callback, opts)
end

---@param entries any
---@param callback fun(selections: any[])
---@param opts TelescopePickerOpts|nil
function M.pick_entries(entries, callback, opts)
	return M.pick_multi(entries, callback, opts)
end

---@param options any
---@param callback fun(selection: any|nil)
---@param opts TelescopePickerOpts|nil
function M.pick_option(options, callback, opts)
	opts = opts or {}
	opts.prompt_title = opts.prompt_title or "Select option"
	return M.pick_single(options, callback, opts)
end

---@param menu_items any
---@param callback fun(selection: any|nil)
---@param opts TelescopePickerOpts|nil
function M.pick_menu(menu_items, callback, opts)
	opts = opts or {}
	opts.prompt_title = opts.prompt_title or "Select action"
	return M.pick_single(menu_items, callback, opts)
end

---@param items any
---@param callback fun(selections: any[])
---@param opts TelescopePickerOpts|nil
function M.pick_checklist(items, callback, opts)
	opts = opts or {}
	opts.prompt_title = opts.prompt_title or "Select items"
	opts.show_hints = opts.show_hints ~= false
	return M.pick_multi(items, callback, opts)
end

return M
