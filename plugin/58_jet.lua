-- ┌──────────────────────┐
-- │ JET analyses (Julia) │
-- └──────────────────────┘
--
-- Run JET.jl on the call under cursor in the REPL from 'plugin/60_slime.lua',
-- where globals defined by the script exist. JET reports are shown in the REPL
-- and are also put into quickfix list and diagnostics. The language server
-- (JETLS) shows type errors on save, but not type instabilities.
--
-- Code to analyze is visual selection, otherwise the innermost call under
-- cursor, otherwise right hand side of assignment or the whole line.
-- Arguments of the call are evaluated in the REPL (like JET's `@report_opt`
-- does), so they have to be defined there.
--
-- The REPL loads 'repl/nvim_jet.jl' with `julia -L`, which writes reports into
-- a temporary directory watched by Neovim (like figures in 'plugin/55_figures.lua').
-- JET should be installed into the global environment:
-- julia --project=@v1.12 -e 'using Pkg; Pkg.add("JET")'
--
-- Mappings in Julia buffers (also in Visual mode for analyzing selection):
-- - `<Leader>ljo` - type instabilities of call (`@report_opt`)
-- - `<Leader>ljc` - type errors of call (`@report_call`)
-- - `<Leader>ljf` - errors in the whole file (`report_file`, Normal mode only)
-- - `<Leader>ljw` - inferred types of call (`@code_warntype`), shown in REPL
-- - `<Leader>ljb` - benchmark call (`@btime`), shown in REPL
-- - `<Leader>ljj` - repeat the last one, like after sending fixed function
-- - `<Leader>ljx` - clear JET quickfix list and diagnostics
--
-- Functions sent to REPL with slime are defined at `REPL[n]` locations. Reports
-- for them are shown at definition of function with the same name in script
-- where analysis was started (or in other open Julia buffers).

local M = {}
Config.jet = M

-- Inside Neovim's temporary directory, which is deleted on exit
M.dir = vim.fn.tempname()
vim.fn.mkdir(M.dir, 'p')

-- File to load with `julia -L` and environment for REPL processes
M.julia_file = vim.fn.stdpath('config') .. '/repl/nvim_jet.jl'
M.env = function() return { NVIM_JET_DIR = M.dir } end

local ns = vim.api.nvim_create_namespace('jet')

-- Last request sent to REPL (for repeating) and last JET analysis (results
-- arrive later and belong to it)
local last, last_analysis

local notify = function(msg, level) vim.notify('JET: ' .. msg, level or vim.log.levels.INFO) end

-- Code to analyze ============================================================
local get_code = function()
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then
    local lines = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = mode })
    vim.cmd('normal! \27')
    return vim.trim(table.concat(lines, '\n'))
  end

  local ok, node = pcall(vim.treesitter.get_node)
  local assignment
  while ok and node do
    local type = node:type()
    if type == 'call_expression' or type == 'broadcast_call_expression' then
      return vim.treesitter.get_node_text(node, 0)
    end
    assignment = assignment or (type == 'assignment' and node or nil)
    node = node:parent()
  end

  if assignment then
    local rhs = assignment:named_child(assignment:named_child_count() - 1)
    return vim.treesitter.get_node_text(rhs, 0)
  end
  return vim.trim(vim.api.nvim_get_current_line())
end

-- Julia string literal
local julia_string = function(s) return '"' .. s:gsub('[\\"$]', '\\%0') .. '"' end

-- Sending to REPL ============================================================
local analysis_kinds = { report_opt = true, report_call = true, report_file = true }

local send = function(request)
  if not Config.repl_send(request.command) then return end
  last = request
  if analysis_kinds[request.kind] then last_analysis = request end
end

local commands = {
  report_opt = 'NvimJET.@report_opt ',
  report_call = 'NvimJET.@report_call ',
  warntype = '@code_warntype ',
  bench = 'NvimJET.@bench ',
}

local on_call = function(kind)
  return function()
    local code = get_code()
    if code == '' then return end
    local buf = vim.api.nvim_get_current_buf()
    send({ kind = kind, command = commands[kind] .. code, label = code, buf = buf })
  end
end

local on_file = function()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == '' then return notify('Buffer has no file', vim.log.levels.WARN) end
  -- JET reads the file from disk
  vim.cmd('silent update')
  local command = 'NvimJET.report_file(' .. julia_string(path) .. ')'
  send({ kind = 'report_file', command = command, label = vim.fn.fnamemodify(path, ':~:.'), buf = buf })
end

local repeat_last = function()
  if last == nil then return notify('Nothing to repeat', vim.log.levels.WARN) end
  if last.kind == 'report_file' and vim.api.nvim_buf_is_valid(last.buf) then
    vim.api.nvim_buf_call(last.buf, function() vim.cmd('silent update') end)
  end
  send(last)
end

-- Locations of `REPL[n]` =====================================================
-- Name of function defined by a definition node: in `function f(x) ... end`
-- or in short form `f(x) = ...`. Signature can be inside `where` and `::`.
local get_def_name = function(def, buf)
  local sig
  if def:type() == 'function_definition' then
    for child in def:iter_children() do
      if child:type() == 'signature' then sig = child end
    end
  else
    sig = def:named_child(0)
  end

  local find_call
  find_call = function(node)
    if node:type() == 'call_expression' then return node end
    if not (node:type() == 'signature' or node:type() == 'where_expression' or node:type() == 'typed_expression') then
      return nil
    end
    return node:named_child(0) and find_call(node:named_child(0))
  end
  local call = sig and find_call(sig)
  if call == nil or call:named_child(0) == nil then return nil end

  -- Use `f` from `Module.f`
  local name = vim.treesitter.get_node_text(call:named_child(0), buf):match('([^%.]+)$')
  return name, vim.treesitter.get_node_text(sig, buf)
end

local def_query

-- Line where function `name` is defined in buffer. With several methods, use
-- the one with all argument names in its signature.
local find_definition = function(buf, name, argnames)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'julia')
  if not ok or parser == nil then return nil end
  def_query = def_query or vim.treesitter.query.parse('julia', '[(function_definition) (assignment)] @def')
  local args = vim.split(argnames, ',', { trimempty = true })

  local first
  for _, def in def_query:iter_captures(parser:parse()[1]:root(), buf) do
    local def_name, sig = get_def_name(def, buf)
    if def_name == name then
      local row = def:range()
      local has_args = true
      for _, arg in ipairs(args) do
        has_args = has_args and sig:find('%f[%w_]' .. vim.pesc(arg) .. '%f[^%w_]') ~= nil
      end
      if has_args then return row + 1 end
      first = first or row + 1
    end
  end
  return first
end

-- Buffer and line of `REPL[n]` location: in buffer where analysis was started,
-- then in other loaded Julia buffers
local resolve_repl_location = function(lnum, name, def_line, argnames)
  if name == '' then return nil end
  local source = last_analysis and last_analysis.buf
  local bufs = { source }
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= source and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'julia' then
      table.insert(bufs, buf)
    end
  end

  for _, buf in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      local def_start = find_definition(buf, name, argnames)
      if def_start then return buf, def_start + lnum - def_line end
    end
  end
end

-- Showing results ============================================================
local to_item = function(line)
  local file, lnum, name, def_line, argnames, text = unpack(vim.split(line, '\t', { plain = true }))
  if text == nil then return nil end
  lnum, def_line = tonumber(lnum) or 0, tonumber(def_line) or 0

  if file:find('^REPL%[') then
    local buf, target = resolve_repl_location(lnum, name, def_line, argnames)
    if buf then return { bufnr = buf, lnum = target, text = text, type = 'W' } end
  elseif file ~= '' and vim.uv.fs_stat(file) then
    return { filename = file, lnum = lnum, text = text, type = 'W' }
  end
  -- Location which can't be shown: keep it in text
  return { text = (file ~= '' and (file .. ':' .. lnum .. ': ') or '') .. text }
end

local show_result = function(lines)
  local analysis = last_analysis or { kind = 'analysis', label = '' }
  if lines[1] and vim.startswith(lines[1], 'error\t') then
    return notify(lines[1]:sub(7), vim.log.levels.ERROR)
  end

  local items, diagnostics = {}, {}
  for _, line in ipairs(lines) do
    local item = to_item(line)
    if item then table.insert(items, item) end
    local buf = item and (item.bufnr or (item.filename and vim.fn.bufadd(item.filename)))
    if buf then
      diagnostics[buf] = diagnostics[buf] or {}
      local diagnostic = { lnum = math.max(item.lnum - 1, 0), col = 0, message = item.text, source = 'JET' }
      diagnostic.severity = vim.diagnostic.severity.WARN
      table.insert(diagnostics[buf], diagnostic)
    end
  end

  vim.diagnostic.reset(ns)
  for buf, buf_diagnostics in pairs(diagnostics) do
    vim.diagnostic.set(ns, buf, buf_diagnostics)
  end

  local label = analysis.label:gsub('%s*\n.*', ' …')
  vim.fn.setqflist({}, ' ', { title = 'JET ' .. analysis.kind .. ': ' .. label, items = items })
  if #items == 0 then return notify(analysis.kind .. ': no problems found') end
  notify(string.format('%s: %d possible problem(s)', analysis.kind, #items), vim.log.levels.WARN)
  vim.cmd('botright cwindow')
end

local read_result = function(name)
  if not name:find('^jet%-%d+%.tsv$') then return end
  local file = M.dir .. '/' .. name
  -- Same file can be reported more than once
  if not vim.uv.fs_stat(file) then return end
  local lines = vim.fn.readfile(file)
  vim.uv.fs_unlink(file)
  show_result(lines)
end

local watcher = assert(vim.uv.new_fs_event())
watcher:start(M.dir, {}, function(err, name)
  if err or not name then return end
  vim.schedule(function() read_result(name) end)
end)

M.clear = function()
  vim.diagnostic.reset(ns)
  if vim.startswith(vim.fn.getqflist({ title = 0 }).title, 'JET ') then
    vim.fn.setqflist({}, 'r', { title = 'JET (cleared)', items = {} })
    vim.cmd('cclose')
  end
end

-- Mappings ===================================================================
local set_mappings = function(ev)
  local map = function(mode, suffix, rhs, desc)
    vim.keymap.set(mode, '<Leader>lj' .. suffix, rhs, { buffer = ev.buf, desc = desc })
  end
  map({ 'n', 'x' }, 'o', on_call('report_opt'), 'Type instabilities (report_opt)')
  map({ 'n', 'x' }, 'c', on_call('report_call'), 'Type errors (report_call)')
  map('n', 'f', on_file, 'Errors in file (report_file)')
  map({ 'n', 'x' }, 'w', on_call('warntype'), 'Inferred types (code_warntype)')
  map({ 'n', 'x' }, 'b', on_call('bench'), 'Benchmark (btime)')
  map('n', 'j', repeat_last, 'Repeat last')
  map('n', 'x', M.clear, 'Clear results')
end
Config.new_autocmd('FileType', 'julia', set_mappings, 'Set JET mappings')
