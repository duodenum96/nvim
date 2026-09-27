-- ┌────────────────────┐
-- │ Gutter and tabline │
-- └────────────────────┘
--
-- Give gutter and tabline their own shades so that they look like surfaces
-- around the buffer: gutter is slightly raised, tabline is a recessed tray with
-- the current buffer raised out of it.
--
-- Shades are derived from the current color scheme's `Normal` highlight, so it
-- works with any of them. Reapplied after every `:colorscheme`.

-- Mix two colors (as returned by `nvim_get_hl()`) with `t` from 0 to 1
local blend = function(c1, c2, t)
  local res = {}
  for _, shift in ipairs({ 16, 8, 0 }) do
    local x1, x2 = math.floor(c1 / 2 ^ shift) % 256, math.floor(c2 / 2 ^ shift) % 256
    table.insert(res, math.floor(x1 + (x2 - x1) * t + 0.5))
  end
  return string.format('#%02x%02x%02x', unpack(res))
end

local get_hl = function(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end

-- Set some attributes while keeping the rest of the highlight group as is
local update_hl = function(name, opts)
  vim.api.nvim_set_hl(0, name, vim.tbl_extend('force', get_hl(name), opts))
end

local apply_shades = function()
  local normal = get_hl('Normal')
  -- Transparent color schemes have no background to derive shades from
  if normal.bg == nil then return end

  local is_dark = vim.o.background == 'dark'
  local bg = normal.bg
  local fg = normal.fg or (is_dark and 0xffffff or 0x000000)

  -- stylua: ignore start
  -- "Raised" goes towards foreground, "recessed" goes towards black
  local raised       = blend(bg, fg, 0.06)
  local raised_more  = blend(bg, fg, 0.12)
  local recessed     = blend(bg, 0x000000, is_dark and 0.35 or 0.12)
  local recessed_mid = blend(bg, 0x000000, is_dark and 0.18 or 0.06)
  local dim_fg       = blend(fg, bg, 0.45)
  local number_fg    = blend(fg, bg, 0.40)
  local accent       = get_hl('DiagnosticWarn').fg or fg

  -- Gutter. Current line part is lifted a bit more. Line numbers get explicit
  -- color because color schemes often make them barely visible.
  for _, name in ipairs({ 'LineNr', 'LineNrAbove', 'LineNrBelow' }) do
    update_hl(name, { fg = number_fg, bg = raised })
  end
  for _, name in ipairs({ 'SignColumn', 'FoldColumn' }) do
    update_hl(name, { bg = raised })
  end
  for _, name in ipairs({ 'CursorLineNr', 'CursorLineSign', 'CursorLineFold' }) do
    update_hl(name, { bg = raised_more })
  end

  -- Tabline ('mini.tabline')
  local hl = function(name, opts) vim.api.nvim_set_hl(0, name, opts) end
  hl('MiniTablineFill',            { bg = recessed })
  hl('MiniTablineHidden',          { fg = dim_fg, bg = recessed_mid })
  hl('MiniTablineVisible',         { fg = fg,     bg = recessed_mid })
  hl('MiniTablineCurrent',         { fg = fg,     bg = raised_more, bold = true })
  hl('MiniTablineModifiedHidden',  { fg = accent, bg = recessed_mid, italic = true })
  hl('MiniTablineModifiedVisible', { fg = accent, bg = recessed_mid, italic = true })
  hl('MiniTablineModifiedCurrent', { fg = accent, bg = raised_more, bold = true, italic = true })

  -- Built-in tabline (used if 'mini.tabline' is not active)
  hl('TabLineFill', { link = 'MiniTablineFill' })
  hl('TabLine',     { link = 'MiniTablineHidden' })
  hl('TabLineSel',  { link = 'MiniTablineCurrent' })
  -- stylua: ignore end
end

apply_shades()
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('custom-ui-shades', {}),
  callback = apply_shades,
  desc = 'Shade gutter and tabline',
})
