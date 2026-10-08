-- Config of 'r_language_server' language server (R package 'languageserver').
-- Source: https://github.com/REditorSupport/languageserver
--
-- Installed with Mason, which has its own R library with the package. Install
-- with `USE_BUNDLED_LIBUV=1` environment variable, unless 'libuv-devel' system
-- package is installed (needed by 'fs' R package).
--
-- Used together with 'air', which is responsible for formatting.
return {
  cmd = { 'r-languageserver' },
  on_attach = function(client, buf_id)
    -- Let 'air' handle formatting
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
    client.server_capabilities.documentOnTypeFormattingProvider = nil
  end,
}
