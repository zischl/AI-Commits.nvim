if vim.g.loaded_ai_commits == 1 then
	return
end
vim.g.loaded_ai_commits = 1

vim.api.nvim_create_user_command("AICommit", function()
	require("ai-commits").generate_commit_msg()
end, {
	desc = "Generate AI git commit message from staged changes",
})

vim.api.nvim_create_user_command("GitAICommit", function()
	require("ai-commits").generate_commit_msg()
end, {
	desc = "Generate AI git commit message from staged changes (alias)",
})
