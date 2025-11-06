-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Insert debugger statement
vim.keymap.set("n", "<leader>db", ":normal! odebugger<Esc>", { desc = "Insert ruby debugger" })

-- Copy relative path to clipboard
vim.keymap.set("n", "<leader>np", ':let @+=expand("%")<CR>', { desc = "Copy nearest path to clipboard" })

-- Copy the nearest Minitest test line number to the clipboard
vim.keymap.set("n", "<leader>nt", function()
  local file_path = vim.fn.fnamemodify(vim.fn.expand("%"), ":.")
  local line_num = vim.fn.line(".")

  -- Find the nearest test line by searching backward
  local current_line = line_num
  local test_pattern = "^%s*test%s+['\"]"
  local test_line = line_num

  while current_line > 0 do
    local line_content = vim.fn.getline(current_line)
    if line_content:match(test_pattern) then
      test_line = current_line
      break
    end
    current_line = current_line - 1
  end

  local command = "bundle exec bin/rails test " .. file_path .. ":" .. test_line
  vim.fn.setreg("+", command)
  print("Copied to clipboard: " .. command)
end, { desc = "Copy nearest test to clipboard" })

-- Copy the whole current test file command to the clipboard
vim.keymap.set("n", "<leader>nf", function()
  local file_path = vim.fn.fnamemodify(vim.fn.expand("%"), ":.")
  local command = "bundle exec bin/rails test " .. file_path
  vim.fn.setreg("+", command)
  print("Copied to clipboard: " .. command)
end, { desc = "Copy nearest test file to clipboard" })

-- GitHub PR keymaps
vim.keymap.set("n", "<leader>gm", function()
  require("snacks").picker.gh_pr({ author = "@me", state = "open" })
end, { desc = "󱥰 My Open Pull Requests" })
