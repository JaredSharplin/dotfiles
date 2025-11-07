return {
  "nvim-neotest/neotest",
  dependencies = {
    "zidhuss/neotest-minitest",
  },
  opts = {
    adapters = {
      ["neotest-minitest"] = {
        test_cmd = function()
          return {
            "bin/rails",
            "test",
          }
        end,
      },
    },
  },
}
