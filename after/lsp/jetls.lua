-- Config of 'jetls' language server for Julia (JETLS.jl).
-- Source: https://aviatesk.github.io/JETLS.jl/dev/#Neovim
--
-- It is not in 'nvim-lspconfig', so this is a full config. Install the server:
-- julia -e 'using Pkg; Pkg.Apps.add(; url="https://github.com/aviatesk/JETLS.jl", rev="release")'
-- Re-run it after upgrading Julia, as the server is tied to Julia's version.
--
-- The server is installed to '~/.julia/bin', used directly if not on PATH.
local jetls = vim.fn.exepath('jetls')
if jetls == '' then jetls = vim.fn.expand('~/.julia/bin/jetls') end

-- JETLS can send diagnostics which start after they end, which makes Neovim
-- throw an error. This happens with "Method definition ... overwritten" warning
-- when JETLS can't find lines of the definition in the file (like for code from
-- macros, for example `@time`). Drop such diagnostics, as they point nowhere.
local drop_invalid = function(diagnostics)
  return vim.tbl_filter(function(d)
    return d.range.start.line <= d.range['end'].line
  end, diagnostics or {})
end

local handlers = {
  -- Diagnostics which the server sends by itself (like after save)
  ['textDocument/publishDiagnostics'] = function(err, params, ctx)
    params.diagnostics = drop_invalid(params.diagnostics)
    vim.lsp.diagnostic.on_publish_diagnostics(err, params, ctx)
  end,
  -- Diagnostics which Neovim requests from the server (like when typing)
  ['textDocument/diagnostic'] = function(err, result, ctx)
    if result ~= nil and result.kind == 'full' then
      result.items = drop_invalid(result.items)
    end
    for _, related in pairs((result or {}).relatedDocuments or {}) do
      if related.kind == 'full' then related.items = drop_invalid(related.items) end
    end
    vim.lsp.diagnostic.on_diagnostic(err, result, ctx)
  end,
}

return {
  cmd = { jetls, 'serve' },
  filetypes = { 'julia' },
  root_markers = { 'Project.toml' },
  -- Start type analysis sooner after save (default: 1 second)
  settings = { jetls = { full_analysis = { debounce = 0.2 } } },
  -- Reuse Julia's own (precompiled) inference results for code of packages
  -- instead of analyzing it again. Can make analysis of scripts which use big
  -- packages several times faster. Experimental in JETLS; remove if diagnostics
  -- look wrong.
  init_options = { reuse_native_inference = true },
  handlers = handlers,
}
