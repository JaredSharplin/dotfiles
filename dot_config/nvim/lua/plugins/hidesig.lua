return {
  {
    name = "hidesig",
    dir = vim.fn.stdpath("config"),
    ft = { "ruby" },
    opts = {
      opacity = 0.25,
    },
    config = function(_, opts)
      require("hidesig").setup(opts)
    end,
    keys = {
      { "<leader>us", "<cmd>HidesigToggle<cr>", desc = "Toggle Sorbet signature dimming" },
    },
  },
}
