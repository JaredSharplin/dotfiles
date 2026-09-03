local M = {}

local ns = vim.api.nvim_create_namespace("hidesig")
local hl_cache = {}
local attached_buffers = {}
local cached_query = nil

local defaults = {
  enabled = true,
  opacity = 0.25,
  delay = 100,
  dim_type_alias = true,
  filetypes = { "ruby" },
}

M.options = vim.deepcopy(defaults)

local base_sig_query = [[
(
  call
    method: (identifier) @sig_keyword
    block: [(block) (do_block)]
  (#eq? @sig_keyword "sig")
) @sig_def
]]

local type_alias_query = [[
(
  assignment
    left: (constant)
    right: (
      call
        receiver: (constant)
        method: (identifier) @alias_identifier
        (#eq? @alias_identifier "type_alias")
    )
) @sig_def
]]

function M.get_query()
  if cached_query then
    return cached_query
  end

  local query_str = base_sig_query
  if M.options.dim_type_alias then
    query_str = query_str .. "\n" .. type_alias_query
  end

  local ok, parsed = pcall(vim.treesitter.query.parse, "ruby", query_str)
  if ok and parsed then
    cached_query = parsed
    return cached_query
  end
  return nil
end

local function get_bg_color()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  if normal and normal.bg then
    return normal.bg
  end
  return vim.o.background == "light" and 0xffffff or 0x282828
end

local function get_hl_color(hl_group)
  local hl = vim.api.nvim_get_hl(0, { name = hl_group, link = false })
  if hl and hl.fg then
    return hl.fg
  end
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  return normal.fg or (vim.o.background == "light" and 0x000000 or 0xebdbb2)
end

local function blend(fg, bg, alpha)
  local fg_r = bit.band(bit.rshift(fg, 16), 0xff)
  local fg_g = bit.band(bit.rshift(fg, 8), 0xff)
  local fg_b = bit.band(fg, 0xff)

  local bg_r = bit.band(bit.rshift(bg, 16), 0xff)
  local bg_g = bit.band(bit.rshift(bg, 8), 0xff)
  local bg_b = bit.band(bg, 0xff)

  local r = math.floor(alpha * fg_r + (1 - alpha) * bg_r + 0.5)
  local g = math.floor(alpha * fg_g + (1 - alpha) * bg_g + 0.5)
  local b = math.floor(alpha * fg_b + (1 - alpha) * bg_b + 0.5)

  return bit.bor(bit.lshift(r, 16), bit.lshift(g, 8), b)
end

local function get_or_create_hl(hl_group, opacity)
  local key = hl_group .. "_" .. opacity
  if hl_cache[key] then
    return hl_cache[key]
  end

  local fg = get_hl_color(hl_group)
  local bg = get_bg_color()
  local dimmed = blend(fg, bg, opacity)
  local new_group = "Hidesig_" .. hl_group:gsub("[^%w_]", "_")

  vim.api.nvim_set_hl(0, new_group, { fg = dimmed, default = false })
  hl_cache[key] = new_group
  return new_group
end

local function collect_leaves(node, leaves)
  if node:child_count() == 0 then
    local srow, scol, erow, ecol = node:range()
    if srow ~= erow or scol ~= ecol then
      table.insert(leaves, node)
    end
  else
    for child in node:iter_children() do
      collect_leaves(child, leaves)
    end
  end
end

function M.update_range(bufnr, start_row, end_row)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if not M.options.enabled then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, start_row, end_row)
    return
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "ruby")
  if not ok or not parser then
    return
  end

  if not vim.treesitter.highlighter.active[bufnr] then
    vim.treesitter.start(bufnr, "ruby")
  end

  local tree = parser:parse()[1]
  if not tree then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, start_row, end_row)

  local q = M.get_query()
  if not q then
    return
  end

  for _, match, _ in q:iter_matches(tree:root(), bufnr, start_row, end_row) do
    local sig_nodes = match[2]
    local sig_node = type(sig_nodes) == "table" and sig_nodes[1] or sig_nodes
    if sig_node and not sig_node:has_error() then
      local leaves = {}
      collect_leaves(sig_node, leaves)

      for _, leaf in ipairs(leaves) do
        local srow, scol, erow, ecol = leaf:range()
        local caps = vim.treesitter.get_captures_at_pos(bufnr, srow, scol)
        local hl_group = #caps > 0 and ("@" .. caps[#caps].capture) or "Normal"
        local dimmed_hl = get_or_create_hl(hl_group, M.options.opacity)

        vim.api.nvim_buf_set_extmark(bufnr, ns, srow, scol, {
          end_row = erow,
          end_col = ecol,
          hl_group = dimmed_hl,
          priority = 130,
        })
      end
    end
  end
end

function M.update_visible(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end
  local start_row = math.max(0, vim.fn.line("w0", win) - 1)
  local end_row = vim.fn.line("w$", win)
  M.update_range(bufnr, start_row, end_row)
end

function M.clear_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end
end

function M.refresh_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(M.options.filetypes, vim.bo[bufnr].filetype) then
      M.update_range(bufnr, 0, -1)
    end
  end
end

function M.toggle()
  M.options.enabled = not M.options.enabled
  if M.options.enabled then
    M.refresh_all()
    vim.notify("Hidesig: enabled", vim.log.levels.INFO)
  else
    M.clear_all()
    vim.notify("Hidesig: disabled", vim.log.levels.INFO)
  end
end

function M.enable()
  if not M.options.enabled then
    M.options.enabled = true
    M.refresh_all()
  end
end

function M.disable()
  if M.options.enabled then
    M.options.enabled = false
    M.clear_all()
  end
end

function M.attach(bufnr)
  if attached_buffers[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  attached_buffers[bufnr] = true

  local timer = nil
  local function debounced_update()
    if timer then
      timer:stop()
    end
    timer = vim.defer_fn(function()
      M.update_visible(bufnr)
    end, M.options.delay)
  end

  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) and M.options.enabled then
      M.update_range(bufnr, 0, -1)
    end
  end)

  local group = vim.api.nvim_create_augroup(string.format("HidesigBuf_%d", bufnr), { clear = true })

  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "WinScrolled" }, {
    group = group,
    buffer = bufnr,
    callback = debounced_update,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      attached_buffers[bufnr] = nil
      if timer then
        timer:stop()
      end
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      pcall(vim.api.nvim_del_augroup_by_name, string.format("HidesigBuf_%d", bufnr))
    end,
  })
end

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
  cached_query = nil
  hl_cache = {}

  local group = vim.api.nvim_create_augroup("HidesigGlobal", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = M.options.filetypes,
    callback = function(args)
      M.attach(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      hl_cache = {}
      if M.options.enabled then
        M.refresh_all()
      end
    end,
  })

  vim.api.nvim_create_user_command("HidesigToggle", function()
    M.toggle()
  end, { desc = "Toggle Sorbet signature dimming" })

  vim.api.nvim_create_user_command("HidesigEnable", function()
    M.enable()
  end, { desc = "Enable Sorbet signature dimming" })

  vim.api.nvim_create_user_command("HidesigDisable", function()
    M.disable()
  end, { desc = "Disable Sorbet signature dimming" })

  vim.api.nvim_create_user_command("HidesigInfo", function()
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local info = {
      string.format("Status: %s", M.options.enabled and "enabled" or "disabled"),
      string.format("Opacity: %s", tostring(M.options.opacity)),
      string.format("Dim type aliases: %s", tostring(M.options.dim_type_alias)),
      string.format("Background: #%06x", normal.bg or 0),
    }
    vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Hidesig" })
  end, { desc = "Show Hidesig status and configuration" })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(M.options.filetypes, vim.bo[bufnr].filetype) then
      M.attach(bufnr)
    end
  end
end

return M
