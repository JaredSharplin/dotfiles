-- Both hosts GitHub serves attachments from; mirrored from gh-pr-shots' ATTACHMENT_URL.
local ATTACHMENT = "^https://github%.com/user%-attachments/assets/[^%s\"'>%)%]]+$"
local ATTACHMENT_LEGACY = "^https://[%w%-]*user%-images%.githubusercontent%.com/[^%s\"'>%)%]]+$"

local token
local downloads = {}
local inflight = {}

-- Downloads land after the render pass that asked for them, so nudge every buffer snacks
-- is rendering into; BufWinEnter is one of the events its inline renderer redraws on, and
-- that redraw is debounced, so a burst of finished downloads costs one pass.
local function rerender()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.b[buf].snacks_image_attached then
      vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf })
    end
  end
end

-- Private-repo attachments 404 for the anonymous curl snacks fetches with, so download
-- them here instead and hand back a file. Returning nil leaves every other src to snacks,
-- which keeps the token off non-GitHub hosts.
local function resolve_attachment(_, src)
  if not (src:match(ATTACHMENT) or src:match(ATTACHMENT_LEGACY)) then
    return nil
  end
  if downloads[src] and vim.fn.filereadable(downloads[src]) == 1 then
    return downloads[src]
  end
  if inflight[src] then
    return nil
  end

  if not token then
    local ok, out = pcall(vim.fn.system, { "gh", "auth", "token" })
    if not ok or vim.v.shell_error ~= 0 then
      vim.notify("gh auth token failed; PR images will not load", vim.log.levels.WARN)
      return nil
    end
    token = vim.trim(out)
  end

  -- Fetch off the main loop: blocking here freezes the buffer once per image.
  -- -f so a 404 body is never cached as an image; --config - keeps the token out of ps.
  local file = vim.fn.tempname() .. ".png"
  inflight[src] = true
  local ok = pcall(
    vim.system,
    { "curl", "-fsSL", "--max-time", "15", "--config", "-", "-o", file, src },
    { stdin = 'header = "Authorization: Bearer ' .. token .. '"\n' },
    function(res)
      inflight[src] = nil
      if res.code == 0 then
        downloads[src] = file
      end
      vim.schedule(function()
        if res.code ~= 0 then
          vim.notify("Could not fetch PR image: " .. src, vim.log.levels.WARN)
        end
        rerender()
      end)
    end
  )
  if not ok then
    inflight[src] = nil
  end
  return nil
end

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
    image = { resolve = resolve_attachment },
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
