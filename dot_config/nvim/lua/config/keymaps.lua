-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Insert debugger statement
vim.keymap.set("n", "<leader>db", ":normal! odebugger<Esc>", { desc = "Insert Debugger" })

-- Copy relative path to clipboard
vim.keymap.set("n", "<leader>fy", ':let @+=expand("%")<CR>', { desc = "File Yank" })

-- GitHub PR keymaps
vim.keymap.set("n", "<leader>gm", function()
  require("snacks").picker.gh_pr({ author = "@me", state = "open" })
end, { desc = "󱥰 My Open Pull Requests" })

vim.keymap.set("n", "<leader>gv", function()
  require("snacks").picker.gh_pr({ search = "involves:@me", state = "open" })
end, { desc = "󱥰 PRs I'm Involved In" })

vim.keymap.set("n", "<leader>go", function()
  local result = vim.fn.system("gh pr view --json number -q .number 2>/dev/null")
  local pr = tonumber(vim.trim(result))
  if pr then
    require("snacks").picker.gh_pr({ search = "#" .. pr })
  else
    vim.notify("No PR found for current branch", vim.log.levels.WARN)
  end
end, { desc = "󱥰 PR Overview" })

vim.keymap.set("n", "<leader>gr", function()
  local result = vim.fn.system("gh pr view --json number -q .number 2>/dev/null")
  local pr = tonumber(vim.trim(result))
  if pr then
    require("snacks").picker.gh_diff({ pr = pr })
  else
    vim.notify("No PR found for current branch", vim.log.levels.WARN)
  end
end, { desc = "󱥰 PR Review Diff" })
