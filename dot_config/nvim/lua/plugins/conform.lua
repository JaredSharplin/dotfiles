return {
  "stevearc/conform.nvim",
  opts = {
    formatters = {
      rubocop = {
        -- Use bundle exec to match project's bundled RuboCop version
        command = "bundle",
        args = { "exec", "rubocop", "--server", "-a", "-f", "quiet", "--stderr", "--stdin", "$FILENAME" },
      },
    },
  },
}
