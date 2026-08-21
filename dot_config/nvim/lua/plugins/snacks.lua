return {
  "folke/snacks.nvim",
  opts = {
    -- Scratch buffers open in a float using the "scratch" window style, whose
    -- window-local options don't set `wrap`, so the float inherits LazyVim's
    -- global `wrap = false`. Enable it (and linebreak, so it breaks at word
    -- boundaries) on the scratch window directly.
    scratch = {
      win = {
        wo = {
          wrap = true,
          linebreak = true,
        },
      },
    },
    -- Enlarge the picker. snacks deep-merges these over the builtin presets,
    -- so only width/height change; the box layout (input/list/preview) stays.
    -- `default` is used on terminals >= 120 cols, `vertical` on narrower ones.
    picker = {
      layouts = {
        default = {
          layout = {
            width = 0.95,
            height = 0.95,
          },
        },
        vertical = {
          layout = {
            width = 0.8,
          },
        },
      },
    },
  },
}
