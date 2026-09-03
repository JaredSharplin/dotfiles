return {
  {
    name = "hidesig",
    dir = vim.fn.stdpath("config"),
    ft = { "ruby" },
    -- Configure options here or in lua/hidesig.lua defaults (e.g. opacity = 0.35)
    opts = {},
    config = function(_, opts)
      require("hidesig").setup(opts)
    end,
    keys = {
      { "<leader>us", "<cmd>HidesigToggle<cr>", desc = "Toggle Sorbet signature dimming" },
    },
  },
}
