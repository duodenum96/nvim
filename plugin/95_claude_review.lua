-- ┌────────────────────────┐
-- │ Review Claude's edits  │
-- └────────────────────────┘
--
-- Show changes which Claude Code (started with 'sidekick.nvim') made to files
-- as 'mini.diff' hunks, and accept or reject them one by one. No Git involved.
--
-- How it works: right before Claude edits a file, a Claude Code hook saves
-- a snapshot of it (see 'scripts/claude_review_snapshot.py'). The snapshot is
-- used as 'mini.diff' reference text, so hunks show exactly what Claude changed.
-- Accepting a hunk adds it to the snapshot, rejecting reverts it in the file.
-- When a file has no hunks left, its review is done and the snapshot is deleted.
--
-- Usage:
-- - `<Leader>ar` - list all changes to review in quickfix list (`]q` / `[q`)
-- - `]h` / `[h`  - go to next / previous hunk in file
-- - `<Leader>ay` - accept hunk under cursor (or hunks in selection)
-- - `<Leader>an` - reject hunk under cursor (or hunks in selection)
-- - `<Leader>aY` / `<Leader>aN` - accept / reject all hunks in file
--
-- After accepting or rejecting, cursor moves to the next hunk. Rejected hunks
-- are written to disk right away, so that Claude sees them.
--
-- Notes:
-- - Only edits done with Claude's `Edit` and `Write` tools are tracked, not
--   files changed with shell commands.
-- - Claude sessions started before this was set up don't have the hook.
--   Restart them to review their edits.

local root = vim.fn.stdpath('state') .. '/claude-review'

-- Reviews of buffers which have Claude's changes to review
local reviews = {}

local read = function(path)
  local file = io.open(path, 'rb')
  if file == nil then return nil end
  local text = file:read('*a')
  file:close()
  return text
end

local write = function(path, text)
  local file = assert(io.open(path, 'wb'))
  file:write(text)
  file:close()
end

-- Snapshot of a file from before Claude's edits. Its name is file's path with
-- '/' replaced by '%'. It is in 'files/' if file existed before, in 'new/' if
-- Claude created the file.
local find_snapshot = function(path)
  local name = path:gsub('/', '%%')
  for _, kind in ipairs({ 'files', 'new' }) do
    local snapshot = root .. '/' .. kind .. '/' .. name
    if vim.uv.fs_stat(snapshot) ~= nil then return snapshot, kind == 'new' end
  end
end

local get_buf_path = function(buf)
  if vim.bo[buf].buftype ~= '' then return nil end
  return vim.uv.fs_realpath(vim.api.nvim_buf_get_name(buf))
end

-- File has changes to review if it differs from its snapshot. If they are
-- the same, Claude's edit didn't happen (yet): it can wait for permission or
-- it failed. Keep snapshot then, as it is still the "before" version.
local get_review = function(buf)
  local path = get_buf_path(buf)
  if path == nil then return nil end
  local snapshot, is_new = find_snapshot(path)
  if snapshot == nil then return nil end
  local before = read(snapshot)
  if before == read(path) then return nil end
  return { path = path, snapshot = snapshot, is_new = is_new, before = before }
end

-- Accept hunks: make them part of the snapshot (reference text)
local accept_hunks = function(buf, hunks)
  local review = reviews[buf]
  local ref_lines = vim.split(MiniDiff.get_buf_data(buf).ref_text or '', '\n')
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Go from bottom to top to keep reference lines of other hunks in place
  table.sort(hunks, function(a, b) return a.ref_start > b.ref_start end)
  for _, h in ipairs(hunks) do
    -- Lines of "add" hunk go after its reference line
    local at = h.ref_count == 0 and (h.ref_start + 1) or h.ref_start
    for _ = 1, h.ref_count do
      table.remove(ref_lines, at)
    end
    for i = h.buf_start + h.buf_count - 1, h.buf_start, -1 do
      table.insert(ref_lines, at, buf_lines[i])
    end
  end

  local text = table.concat(ref_lines, '\n')
  write(review.snapshot, text)
  MiniDiff.set_ref_text(buf, text)
end

-- 'mini.diff' source which is used for buffers with Claude's changes to review.
-- Other buffers fall back to Git source (see 'plugin/30_mini.lua').
Config.claude_review_source = {
  name = 'claude',
  attach = function(buf)
    local review = get_review(buf)
    if review == nil then return false end
    reviews[buf] = review
    MiniDiff.set_ref_text(buf, review.before)

    -- Show deleted lines and changed words inline
    vim.schedule(function()
      local data = MiniDiff.get_buf_data(buf)
      if reviews[buf] ~= nil and data ~= nil and not data.overlay then MiniDiff.toggle_overlay(buf) end
    end)
  end,
  detach = function(buf) reviews[buf] = nil end,
  apply_hunks = accept_hunks,
}

-- Claude Code settings which add the hook saving snapshots. Claude is started
-- with them in 'plugin/90_sidekick.lua'.
Config.claude_review_settings = root .. '/settings.json'

Config.later(function()
  vim.fn.mkdir(root .. '/files', 'p')
  vim.fn.mkdir(root .. '/new', 'p')

  local script = vim.fn.stdpath('config') .. '/scripts/claude_review_snapshot.py'
  local command = 'python3 ' .. vim.fn.shellescape(script) .. ' ' .. vim.fn.shellescape(root)
  local hook = { matcher = 'Edit|Write', hooks = { { type = 'command', command = command } } }
  vim.fn.writefile({ vim.json.encode({ hooks = { PreToolUse = { hook } } }) }, Config.claude_review_settings)

  -- All changes to review as quickfix items, one per hunk
  local get_changes = function()
    local items = {}
    for _, kind in ipairs({ 'files', 'new' }) do
      for name in vim.fs.dir(root .. '/' .. kind) do
        local path = name:gsub('%%', '/')
        local before, after = read(root .. '/' .. kind .. '/' .. name), read(path)
        if after ~= nil and before ~= after then
          for _, h in ipairs(vim.text.diff(before, after, { result_type = 'indices' })) do
            local text = string.format('Claude: +%d -%d lines', h[4], h[2])
            table.insert(items, { filename = path, lnum = math.max(h[3], 1), text = text })
          end
        end
      end
    end
    return items
  end

  local list_changes = function()
    local items = get_changes()
    if #items == 0 then return vim.notify('No changes by Claude to review', vim.log.levels.INFO) end
    vim.fn.setqflist({}, ' ', { title = 'Claude changes', items = items })
    vim.cmd('cfirst')
  end

  -- Start review in a buffer which already shows Git changes. Like after
  -- Claude edited a file which is open.
  local start = function(buf)
    if reviews[buf] ~= nil or not vim.api.nvim_buf_is_valid(buf) then return end
    if get_review(buf) == nil then return end
    MiniDiff.disable(buf)
    MiniDiff.enable(buf)
  end

  -- Finish review: delete snapshot and show Git changes again
  local finish = function(buf)
    local review = reviews[buf]
    if review == nil then return end
    os.remove(review.snapshot)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if review.is_new and #lines == 1 and lines[1] == '' then
      -- The whole file created by Claude is rejected
      os.remove(review.path)
      MiniBufremove.wipeout(buf, true)
    else
      MiniDiff.disable(buf)
      MiniDiff.enable(buf)
    end

    local files = {}
    for _, item in ipairs(get_changes()) do
      files[item.filename] = true
    end
    local n_files = vim.tbl_count(files)
    local left = n_files == 0 and 'All done' or (n_files .. ' more file(s), `<Leader>ar` to list them')
    vim.notify('Reviewed ' .. vim.fn.fnamemodify(review.path, ':~:.') .. '. ' .. left, vim.log.levels.INFO)
  end

  -- Accept ("apply") or reject ("reset") hunks in current buffer. Scope is one
  -- of "hunk" (under cursor), "selection", "all".
  local act = function(action, scope)
    return function()
      local buf = vim.api.nvim_get_current_buf()
      local review = reviews[buf]
      if review == nil then return vim.notify('No changes by Claude to review here', vim.log.levels.WARN) end

      local from, to = 1, vim.api.nvim_buf_line_count(buf)
      if scope == 'selection' then
        from, to = vim.fn.line('v'), vim.fn.line('.')
        if from > to then from, to = to, from end
        vim.cmd('normal! \27')
      elseif scope == 'hunk' then
        from = nil
        local line = vim.fn.line('.')
        for _, h in ipairs(MiniDiff.get_buf_data(buf).hunks) do
          -- "Delete" hunks are shown on the line above the deleted lines
          local h_from = math.max(h.buf_start, 1)
          local h_to = math.max(h.buf_start + h.buf_count - 1, h_from)
          if h_from <= line and line <= h_to then
            from, to = from or h_from, h_to
          end
        end
        if from == nil then return vim.notify('No hunk under cursor. Go to one with `]h`', vim.log.levels.WARN) end
      end

      review.acted = true
      MiniDiff.do_hunks(buf, action, { line_start = from, line_end = to })
      -- Write rejected changes to disk right away, so that Claude sees them
      if action == 'reset' then vim.cmd('silent update') end
    end
  end

  -- After accepting or rejecting, go to next hunk or finish if none are left
  local continue_review = function()
    local buf = vim.api.nvim_get_current_buf()
    local review = reviews[buf]
    if review == nil or not review.acted then return end
    review.acted = false

    local n_hunks = #MiniDiff.get_buf_data(buf).hunks
    vim.schedule(function()
      if n_hunks == 0 then return finish(buf) end
      if vim.api.nvim_get_current_buf() == buf then MiniDiff.goto_hunk('next', { wrap = true }) end
    end)
  end

  -- Saving a file which Claude didn't change (its edit was denied or failed)
  -- makes its snapshot outdated
  local remove_outdated = function(ev)
    local path = get_buf_path(ev.buf)
    if reviews[ev.buf] ~= nil or path == nil then return end
    local snapshot = find_snapshot(path)
    if snapshot ~= nil and read(snapshot) == read(path) then os.remove(snapshot) end
  end

  local start_later = function(ev)
    vim.schedule(function() start(ev.buf) end)
  end
  Config.new_autocmd({ 'BufEnter', 'FileChangedShellPost' }, '*', start_later, 'Start Claude review')
  Config.new_autocmd('User', 'MiniDiffUpdated', continue_review, 'Continue Claude review')
  Config.new_autocmd('BufWritePre', '*', remove_outdated, 'Remove outdated Claude snapshot')

  local nmap_leader = function(suffix, rhs, desc)
    vim.keymap.set('n', '<Leader>' .. suffix, rhs, { desc = desc })
  end
  local xmap_leader = function(suffix, rhs, desc)
    vim.keymap.set('x', '<Leader>' .. suffix, rhs, { desc = desc })
  end

  -- stylua: ignore start
  nmap_leader('ar', list_changes,               'Review changes (list)')
  nmap_leader('ay', act('apply', 'hunk'),       'Accept hunk')
  nmap_leader('an', act('reset', 'hunk'),       'Reject hunk')
  nmap_leader('aY', act('apply', 'all'),        'Accept all in file')
  nmap_leader('aN', act('reset', 'all'),        'Reject all in file')

  xmap_leader('ay', act('apply', 'selection'), 'Accept hunks in selection')
  xmap_leader('an', act('reset', 'selection'), 'Reject hunks in selection')
  -- stylua: ignore end
end)
