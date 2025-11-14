return {
  "Wansmer/treesj",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  keys = {
    { "<leader>m", "<cmd>TSJToggle<cr>", desc = "Toggle Split/Join" },
    { "<leader>j", "<cmd>TSJJoin<cr>", desc = "Join Node" },
    { "<leader>J", "<cmd>TSJSplit<cr>", desc = "Split Node" },
  },
  opts = {
    use_default_keymaps = false,
  },
}
