-- ┌───────────────────┐
-- │ AI CLI (sidekick) │
-- └───────────────────┘
--
-- 'folke/sidekick.nvim' runs AI CLI tools (Claude, Gemini, Codex, ...) in a
-- terminal split and sends them context from the editor: file, selection,
-- cursor position, diagnostics. Files edited by the tool are reloaded.
--
-- Next Edit Suggestions (Copilot powered AI completion) are disabled, so only
-- the CLI part is used and no Copilot language server is needed.
--
-- See also:
-- - `:h sidekick`
-- - `:checkhealth sidekick`
Config.later(function()
  vim.pack.add({ 'https://github.com/folke/sidekick.nvim' })

  require('sidekick').setup({
    nes = { enabled = false },
    cli = {
      win = {
        -- layout = 'left',
        keys = {
          -- Use `<C-j>` to go back to code (previous window) instead of
          -- navigating to the window below
          nav_down = false,
          blur_ctrl_j = { '<c-j>', 'blur', mode = 'nt', desc = 'Jump back to code' },
        },
      },
      -- Run CLI tools inside tmux sessions so they survive quitting Neovim
      mux = { backend = 'tmux', enabled = true },
      -- Claude Code draws in fullscreen mode (alternate screen), so tmux keeps
      -- no history for sidekick's scrollback buffer to show. Let Claude scroll
      -- by itself instead: mouse wheel, `PgUp`/`PgDn`, `<C-o>` for transcript.
      tools = { claude = { native_scroll = true } },
    },
  })

  -- Claude gets mouse wheel events only if tmux mouse mode is on. Enable it
  -- just for sidekick's tmux sessions. Session is created asynchronously after
  -- attach, so retry for a bit.
  local set_tmux_mouse
  set_tmux_mouse = function(session_name, tries)
    local cmd = { 'tmux', 'set-option', '-t', '=' .. session_name, 'mouse', 'on' }
    vim.system(cmd, {}, function(res)
      if res.code == 0 or tries <= 1 then return end
      vim.defer_fn(function() set_tmux_mouse(session_name, tries - 1) end, 100)
    end)
  end
  local on_attach = function(ev)
    local session = require('sidekick.cli.session').attached()[ev.data.id]
    if session and session.mux_backend == 'tmux' then set_tmux_mouse(session.mux_session, 20) end
  end
  Config.new_autocmd('User', 'SidekickCliAttach', on_attach, 'Enable tmux mouse for sidekick')

  local map = function(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { desc = desc }) end
  local cli = function(method, opts)
    return function() require('sidekick.cli')[method](opts) end
  end

  -- stylua: ignore start
  map({ 'n', 't', 'i', 'x' }, '<C-.>', cli('focus'), 'Sidekick focus')

  map('n',          '<Leader>aa', cli('toggle'),                                 'Toggle CLI')
  map('n',          '<Leader>ac', cli('toggle', { name = 'claude', focus = true }), 'Toggle Claude')
  map('n',          '<Leader>ad', cli('close'),                                  'Detach CLI session')
  map('n',          '<Leader>af', cli('send', { msg = '{file}' }),               'Send file')
  map({ 'n', 'x' }, '<Leader>ap', cli('prompt'),                                 'Select prompt')
  map('n',          '<Leader>as', cli('select', { filter = { installed = true } }), 'Select CLI')
  map({ 'n', 'x' }, '<Leader>at', cli('send', { msg = '{this}' }),               'Send this')
  map('x',          '<Leader>av', cli('send', { msg = '{selection}' }),          'Send selection')
  -- stylua: ignore end

  -- Show attached CLI tools (like "<robot> claude") before the file info
  -- section of 'mini.statusline'. Wrapping keeps the rest of it as is.
  local icon = vim.fn.nr2char(0xee0d)
  local section_fileinfo = MiniStatusline.section_fileinfo
  MiniStatusline.section_fileinfo = function(...)
    local fileinfo = section_fileinfo(...)
    local tools = vim.tbl_map(function(s) return s.tool end, require('sidekick.status').cli())
    if #tools == 0 then return fileinfo end
    local res = '%#Special#' .. icon .. ' ' .. table.concat(tools, ',') .. '%#MiniStatuslineFileinfo#'
    return fileinfo == '' and res or (res .. ' ' .. fileinfo)
  end
end)
