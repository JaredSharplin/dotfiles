return {
  {
    name = "hidesig",
    dir = vim.fn.stdpath("config"),
    ft = { "ruby" },
    opts = {
      enabled = true,
      opacity = 0.65,
      delay = 100,
      dim_type_alias = true,
    },
    config = function(_, opts)
      require("hidesig").setup(opts)
    end,
    keys = {
      { "<leader>us", "<cmd>HidesigToggle<cr>", desc = "Toggle Sorbet signature dimming" },
    },
  },
}
