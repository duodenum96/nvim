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
}
