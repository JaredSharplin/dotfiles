return {
  "atiladefreitas/dooing",
  cmd = { "Dooing", "DooingLocal", "DooingDue" },
  -- Lazy-load on the entry keys; dooing registers the real maps in setup().
  keys = {
    { "<leader>od", desc = "Dooing: global todos" },
    { "<leader>oD", desc = "Dooing: project todos" },
    { "<leader>oN", desc = "Dooing: due items" },
  },
  opts = {
    -- Remap the global entry-point keys off <leader>t (the test prefix) to a
    -- dedicated <leader>o ("todo") group. In-window keys (i/x/d/e/q/…) are
    -- buffer-local to the dooing float and left at their defaults.
    keymaps = {
      toggle_window = "<leader>od",
      open_project_todo = "<leader>oD",
      show_due_notification = "<leader>oN",
    },
  },
}
