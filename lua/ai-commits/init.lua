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

function M.open_commit_floater_win()
	if M.float_bufnr and vim.api.nvim_buf_is_valid(M.float_bufnr) then
		local win = vim.fn.bufwinid(M.float_bufnr)
		if win and win ~= -1 then
			vim.api.nvim_set_current_win(win)
			return M.float_bufnr
		else
			pcall(vim.api.nvim_buf_delete, M.float_bufnr, { force = true })
			M.float_bufnr = nil
		end
	end

	local width = math.floor(vim.o.columns * 0.75)
	local height = math.floor(vim.o.lines * 0.6)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local temp_commit_file = vim.fn.tempname() .. "_COMMIT_EDITMSG"
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(bufnr, temp_commit_file)
	vim.bo[bufnr].filetype = "gitcommit"
	vim.bo[bufnr].bufhidden = "wipe"

	M.float_bufnr = bufnr

	-- No one will notice..
	local status_output = vim.fn.system("git status")
	local initial_lines = {
		"",
		"",
		"# Please enter the commit message for your changes. Lines starting",
		"# with '#' will be ignored, and an empty message aborts the commit.",
		"#",
	}
	if vim.v.shell_error == 0 and status_output and status_output ~= "" then
		for line in status_output:gmatch("[^\r\n]+") do
			table.insert(initial_lines, "# " .. line)
		end
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)

	local opts = {
		relative = "editor",
		width = math.max(width, 40),
		height = math.max(height, 10),
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " COMMIT_EDITMSG ",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(bufnr, true, opts)
	vim.wo[win].number = true
	vim.wo[win].wrap = true

	-- Keymaps
	local close_opts = { buffer = bufnr, silent = true, desc = "Close AI Commit Window" }
	vim.keymap.set("n", "q", "<cmd>close<cr>", close_opts)
	vim.keymap.set("n", "Q", "<cmd>close<cr>", close_opts)
	vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", close_opts)

	-- Commit if saved..
	local commit_on_close = false
	local group = vim.api.nvim_create_augroup("AICommitFloat_" .. bufnr, { clear = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		buffer = bufnr,
		callback = function()
			commit_on_close = true
		end,
	})

	-- On buffer wipeout/close: commit if saved, else abort
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		buffer = bufnr,
		callback = function()
			if M.float_bufnr == bufnr then
				M.float_bufnr = nil
			end
			if commit_on_close then
				local output = vim.fn.system({ "git", "commit", "-F", temp_commit_file })
				local exit_code = vim.v.shell_error
				os.remove(temp_commit_file)

				vim.schedule(function()
					if exit_code == 0 then
						vim.notify("Git commit successful!\n" .. output, vim.log.levels.INFO)
					else
						vim.notify("Git commit failed:\n" .. output, vim.log.levels.ERROR)
					end
				end)
			else
				os.remove(temp_commit_file)
				vim.schedule(function()
					vim.notify("Git commit aborted (buffer was not saved).", vim.log.levels.WARN)
				end)
			end
		end,
	})

	return bufnr
end

--- Check if a buffer is a git commit buffer
--- @param bufnr number|nil Buffer number (defaults to current buffer if nil or 0)
--- @return boolean
function M.commit_buf_check(bufnr)
	if not bufnr or bufnr == 0 then
		bufnr = vim.api.nvim_get_current_buf()
	end
	if not (bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modifiable) then
		return false
	end
	if vim.bo[bufnr].filetype == "gitcommit" then
		return true
	end
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if
		bufname:match("COMMIT_EDITMSG$")
		or bufname:match("MERGE_MSG$")
		or bufname:match("TAG_EDITMSG$")
		or bufname:match("EDITMSG$")
	then
		return true
	end
	return false
end

--- @param opts table|nil
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

--- Generate AI commit message from staged changes
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

	local current_buf = vim.api.nvim_get_current_buf()
	local bufnr = nil
	local target_floater = false

	if M.commit_buf_check(current_buf) then
		bufnr = current_buf
		target_floater = (current_buf == M.float_bufnr)
	else
		bufnr = M.open_commit_floater_win()
		target_floater = true
	end

	local current_line = 0
	local current_col = 0

	if not target_floater then
		vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })
	end

	vim.notify("Generating commit message (" .. config.model .. ")...", vim.log.levels.INFO)

	local partial_line = ""
	local generated_text = false
	local api_error_msg = nil

	local function process_sse_line(line)
		line = line:gsub("\r$", "")
		if line:match("^{") then
			local ok, err_chunk = pcall(vim.fn.json_decode, line)
			if ok and err_chunk and err_chunk.error and err_chunk.error.message then
				api_error_msg = err_chunk.error.message
				return
			end
		end

		if line:match("^data: ") then
			local json_str = line:sub(7)
			if json_str ~= "" and json_str ~= "[DONE]" then
				local ok, chunk = pcall(vim.fn.json_decode, json_str)
				if
					ok
					and chunk
					and chunk.candidates
					and chunk.candidates[1]
					and chunk.candidates[1].content
					and chunk.candidates[1].content.parts
				then
					for _, part in ipairs(chunk.candidates[1].content.parts) do
						if part.text then
							generated_text = true
							local text = part.text:gsub("\r", "")
							vim.schedule(function()
								if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modifiable then
									local lines = vim.split(text, "\n", { plain = true })
									for idx, l in ipairs(lines) do
										if idx == 1 then
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
				elseif ok and chunk and chunk.error and chunk.error.message then
					api_error_msg = chunk.error.message
				end
			end
		end
	end

	vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			if not data then
				return
			end

			data[1] = partial_line .. data[1]
			partial_line = data[#data]

			for i = 1, #data - 1 do
				process_sse_line(data[i])
			end
		end,
		on_exit = function(_, exit_code)
			if partial_line ~= "" then
				process_sse_line(partial_line)
			end
			os.remove(temp_file)
			vim.schedule(function()
				if exit_code == 0 and generated_text then
					vim.notify("Commit message generated!", vim.log.levels.INFO)
				elseif api_error_msg then
					vim.notify("Gemini API Error: " .. api_error_msg, vim.log.levels.ERROR)
				elseif exit_code == 0 then
					vim.notify("Failed to generate commit message (Empty response or API error)", vim.log.levels.ERROR)
				else
					vim.notify("Error generating commit message (Exit Code: " .. exit_code .. ")", vim.log.levels.ERROR)
				end
			end)
		end,
	})
end

return M
