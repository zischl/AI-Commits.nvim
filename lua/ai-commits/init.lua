local M = {}

local defaults = {
	model = "gemini-2.5-flash",
	temperature = 0.2,
	include_history = true,
	history_count = 3,
	prompt = [[
You are an expert developer. Generate a clean, conventional git commit message based on the staged changes.
If recent commit messages are provided below, analyze them to see if this commit is related and match the repository's writing style, scope conventions, and tone.
Strictly adhere to this format:
1. The first line must be a concise, single-line summary prefixing a dash and a space.
2. Followed by exactly one blank line.
3. Followed by a detailed dash plus space prefixed list explaining the specific changes.

Generate only the commit message text.
]],
}

M.options = vim.deepcopy(defaults)

--- @param opts table|nil
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

--- For now just for gemini, will add others later
--- @param opts table|nil
function M.generate_commit_msg(opts)
	local config = vim.tbl_deep_extend("force", M.options, opts or {})

	local api_key = os.getenv("GEMINI_API_KEY")
	if not api_key or api_key == "" then
		vim.notify("GEMINI_API_KEY environment variable is not set", vim.log.levels.ERROR)
		return
	end

	local diff = vim.fn.system("git diff --staged")
	if vim.v.shell_error ~= 0 or diff == "" or diff:match("^fatal:") then
		vim.notify("No staged changes found or not a git repository", vim.log.levels.WARN)
		return
	end

	local history_text = ""
	if config.include_history then
		local count = config.history_count or 10
		local history = vim.fn.system(string.format('git log -n %d --format="- %%s"', count))
		if vim.v.shell_error == 0 and history and history ~= "" and not history:match("^fatal:") then
			history_text = "\nRecent commit messages for context and style reference:\n" .. history .. "\n"
		end
	end

	local prompt = config.prompt .. history_text .. "\nDiff:\n" .. diff

	local payload = {
		contents = {
			{
				parts = {
					{ text = prompt },
				},
			},
		},
		generationConfig = {
			temperature = config.temperature,
		},
	}

	local payload_json = vim.fn.json_encode(payload)

	local temp_file = vim.fn.tempname() .. ".json"
	local f = io.open(temp_file, "w")
	if not f then
		vim.notify("Failed to create temporary file for Gemini payload", vim.log.levels.ERROR)
		return
	end
	f:write(payload_json)
	f:close()

	local url = string.format(
		"https://generativelanguage.googleapis.com/v1beta/models/%s:streamGenerateContent?alt=sse&key=%s",
		config.model,
		api_key
	)

	local cmd = {
		"curl",
		"-s",
		"-N",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-d",
		"@" .. temp_file,
		url,
	}

	local bufnr = vim.api.nvim_get_current_buf()
	if not vim.bo[bufnr].modifiable or vim.bo[bufnr].filetype ~= "gitcommit" then
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(b) and vim.bo[b].modifiable and vim.bo[b].filetype == "gitcommit" then
				bufnr = b
				break
			end
		end
	end

	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.bo[bufnr].modifiable then
		vim.notify("Cannot generate commit message: active buffer is not modifiable", vim.log.levels.ERROR)
		os.remove(temp_file)
		return
	end

	local current_line = 0
	local current_col = 0

	vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })

	vim.notify("Generating commit message (" .. config.model .. ")...", vim.log.levels.INFO)

	vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line:match("^data: ") then
					local json_str = line:sub(7)
					if json_str ~= "" and json_str ~= "[DONE]" then
						local ok, chunk = pcall(vim.fn.json_decode, json_str)
						if
							ok
							and chunk.candidates
							and chunk.candidates[1].content
							and chunk.candidates[1].content.parts
						then
							local text = chunk.candidates[1].content.parts[1].text
							if text then
								vim.schedule(function()
									if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modifiable then
										local lines = vim.split(text, "\n", { plain = true })
										for i, l in ipairs(lines) do
											if i == 1 then
												local existing_line = vim.api.nvim_buf_get_lines(
													bufnr,
													current_line,
													current_line + 1,
													false
												)[1] or ""
												local new_line = existing_line:sub(1, current_col)
													.. l
													.. existing_line:sub(current_col + 1)
												pcall(
													vim.api.nvim_buf_set_lines,
													bufnr,
													current_line,
													current_line + 1,
													false,
													{ new_line }
												)
												current_col = current_col + #l
											else
												current_line = current_line + 1
												pcall(
													vim.api.nvim_buf_set_lines,
													bufnr,
													current_line,
													current_line,
													false,
													{ l }
												)
												current_col = #l
											end
										end
									end
								end)
							end
						end
					end
				end
			end
		end,
		on_exit = function(_, exit_code)
			os.remove(temp_file)
			vim.schedule(function()
				if exit_code == 0 then
					vim.notify("Commit message generated!", vim.log.levels.INFO)
				else
					vim.notify("Error generating commit message (Exit Code: " .. exit_code .. ")", vim.log.levels.ERROR)
				end
			end)
		end,
	})
end

return M
