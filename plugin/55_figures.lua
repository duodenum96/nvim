-- ┌─────────────┐
-- │ Figure pane │
-- └─────────────┘
--
-- MATLAB-like layout for REPL from 'plugin/60_slime.lua': code on the left,
-- figures on top right, REPL on bottom right.
--
-- REPLs are started with environment which makes them save plots as PNG files
-- into a temporary directory (see 'repl/' directory):
-- - Python: matplotlib backend. Like in MATLAB, `plt.show()` is not needed, and
--   figures of default size are resized to fill the pane. Also dark themes
--   matching color schemes (see 'repl/nvim_fig/__init__.py' how to switch).
-- - Julia: display for anything that can be shown as PNG (Plots.jl, Makie,
--   images, etc.). Loaded with `julia -L`.
--
-- Neovim watches that directory and shows new figures with image viewer from
-- 'snacks.nvim'. It needs a terminal with kitty graphics protocol (kitty,
-- ghostty, wezterm). Previous figures are kept and can be cycled through.
--
-- Mappings:
-- - `rf` - toggle figure pane.
-- - `r[` / `r]` - show previous / next figure.

Config.later(function() vim.pack.add({ 'https://github.com/folke/snacks.nvim' }) end)

local M = {}
Config.figures = M

local repl_dir = vim.fn.stdpath('config') .. '/repl'

-- Inside Neovim's temporary directory, which is deleted on exit
M.dir = vim.fn.tempname()
vim.fn.mkdir(M.dir, 'p')

-- Matplotlib themes in 'repl/nvim_fig/' for color schemes. Other dark color
-- schemes use the first one, light ones use default matplotlib theme.
local mpl_themes = {
  catppuccin = 'catppuccin-mocha',
  ['catppuccin-mocha'] = 'catppuccin-mocha',
  ayu = 'ayu-dark',
  ['ayu-dark'] = 'ayu-dark',
  miniwinter = 'miniwinter',
}

-- Environment for REPL processes. Theme is for the color scheme at REPL start.
local pythonpath = vim.env.PYTHONPATH or ''
M.env = function()
  local theme = vim.o.background == 'dark' and (mpl_themes[vim.g.colors_name] or 'catppuccin-mocha')
  return {
    NVIM_FIG_DIR = M.dir,
    MPLBACKEND = 'module://nvim_fig',
    MATPLOTLIBRC = theme and string.format('%s/nvim_fig/%s.mplstyle', repl_dir, theme) or nil,
    PYTHONPATH = pythonpath == '' and repl_dir or (repl_dir .. ':' .. pythonpath),
  }
end

-- File to load with `julia -L`
M.julia_file = repl_dir .. '/nvim_fig.jl'

-- Terminal buffer of the REPL. Figure pane is opened above its window.
M.repl_buf = nil

-- Width of the right column with figure pane and REPL
M.column_width = function() return math.floor(0.4 * vim.o.columns) end

-- Figures from oldest to newest. Only the latest version of each is kept.
local figures, current, max_figures = {}, 0, 50

local buf
local get_buf = function()
  if buf and vim.api.nvim_buf_is_valid(buf) then return buf end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  return buf
end

local find_win = function(b)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == b then return win end
  end
end

M.win = function() return buf and find_win(buf) end

-- Tell REPL the pane size in pixels, so that figures can fill it. DPI is chosen
-- so that text in figures is scaled like text in terminal.
local pane_size
local write_pane_size = function()
  local win = M.win()
  if not win then return end
  local term = Snacks.image.terminal.size()
  local size = string.format(
    '%d %d %d',
    math.floor(vim.api.nvim_win_get_width(win) * term.cell_width),
    math.floor(vim.api.nvim_win_get_height(win) * term.cell_height),
    math.floor(96 * term.scale)
  )
  if size == pane_size then return end
  pane_size = size
  -- Write atomically, so that REPL never reads a partial file
  local tmp = M.dir .. '/.pane'
  vim.fn.writefile({ size }, tmp)
  vim.uv.fs_rename(tmp, M.dir .. '/pane')
end

local show = function(i)
  current = i
  if not M.win() then
    local repl_win = M.repl_buf and find_win(M.repl_buf)
    local config = repl_win and { split = 'above', win = repl_win }
      or { split = 'right', win = -1, width = M.column_width() }
    vim.wo[vim.api.nvim_open_win(get_buf(), false, config)].winfixwidth = true
  end
  write_pane_size()
  Snacks.image.buf.attach(get_buf(), { src = figures[i].file })
end

local add_figure = function(name)
  local id = name:match('^nvimfig%-(%w+)%-%d+%.png$')
  local file = M.dir .. '/' .. name
  if not (id and vim.uv.fs_stat(file)) then return end

  -- New version of a figure replaces the old one
  local old
  for i, fig in ipairs(figures) do
    -- Same file can be reported more than once
    if fig.file == file then return end
    if fig.id == id then old = table.remove(figures, i) break end
  end
  if #figures >= max_figures then old = table.remove(figures, 1) end

  table.insert(figures, { id = id, file = file })
  show(#figures)
  if old then vim.uv.fs_unlink(old.file) end
end

local watcher = assert(vim.uv.new_fs_event())
watcher:start(M.dir, {}, function(err, name)
  if err or not name then return end
  vim.schedule(function() add_figure(name) end)
end)

M.toggle = function()
  local win = M.win()
  if win then return vim.api.nvim_win_hide(win) end
  if #figures > 0 then show(current) end
end

M.cycle = function(direction)
  local n = #figures
  if n == 0 then return end
  show((current - 1 + direction) % n + 1)
  vim.api.nvim_echo({ { string.format('Figure %d/%d', current, n) } }, false, {})
end

Config.new_autocmd({ 'WinResized', 'VimResized' }, '*', write_pane_size, 'Send figure pane size to REPL')

-- 'snacks.nvim' caches info about every shown image
Config.new_autocmd('VimLeavePre', '*', function()
  if not _G.Snacks then return end
  local cached = vim.fn.glob(Snacks.image.config.cache .. '/*-nvimfig-*', false, true)
  for _, file in ipairs(cached) do
    vim.uv.fs_unlink(file)
  end
end, 'Clean cache of figures')

vim.keymap.set('n', 'rf', M.toggle, { desc = 'Toggle figure pane' })
vim.keymap.set('n', 'r[', function() M.cycle(-1) end, { desc = 'Previous figure' })
vim.keymap.set('n', 'r]', function() M.cycle(1) end, { desc = 'Next figure' })
