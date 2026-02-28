local ok, make = pcall(require, "make")
if not ok then
	return
end

local subcommands = {
	"add",
	"edit",
	"run",
	"runb",
	"build",
	"tasks",
	"edit_all",
	"remove",
	"analysis",
	"bear",
	"bearall",
	"mode",
	"clean",
	"link",
	"open",
}

vim.api.nvim_create_user_command("Make", function(opts)
	make.Make(opts.fargs)
end, {
	nargs = "*",
	complete = function(arg_lead, cmd_line)
		local function starts_with(list, lead)
			local out = {}
			local pattern = "^" .. vim.pesc(lead or "")
			for _, item in ipairs(list) do
				if item:match(pattern) then
					table.insert(out, item)
				end
			end
			return out
		end

		local args = {}
		for token in cmd_line:gmatch("%S+") do
			table.insert(args, token)
		end
		if #args > 0 then
			table.remove(args, 1)
		end

		local arg_index = #args
		if arg_lead == "" then
			arg_index = arg_index + 1
		end

		if arg_index == 1 then
			return starts_with(subcommands, arg_lead)
		end

		if arg_index == 2 and args[1] == "mode" then
			return starts_with({ "debug", "release" }, arg_lead)
		end

		return {}
	end,
})
