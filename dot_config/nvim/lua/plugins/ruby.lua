return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ruby_lsp = {
          mason = false,
          -- Use mise shim to use project's Ruby version and bundled gems
          cmd = { vim.fn.expand("~/.local/share/mise/shims/ruby-lsp") },
        },
        -- Disable rubocop LSP server since ruby-lsp provides rubocop integration
        rubocop = {
          enabled = false,
        },
      },
    },
  },
}
