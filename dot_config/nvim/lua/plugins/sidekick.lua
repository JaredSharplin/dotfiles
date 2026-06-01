return {
  "folke/sidekick.nvim",
  opts = {
    -- Disable Next Edit Suggestions: it's the only Copilot-dependent feature.
    -- With this false, the LazyVim sidekick extra also skips registering the
    -- copilot LSP server, so there's no "sign in to Copilot" prompt. CLI
    -- integration below works independently and needs no Copilot.
    nes = { enabled = false },
    cli = {
      win = {
        layout = "left",
      },
    },
  },
}
