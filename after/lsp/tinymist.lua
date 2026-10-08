-- Config of 'tinymist' language server for Typst.
-- Source: https://myriad-dreamin.github.io/tinymist/frontend/neovim.html
--
-- Installed with Mason. See also 'after/ftplugin/typst.lua' to open the PDF.
return {
  settings = {
    -- Export PDF next to the file on every save (or 'onType')
    exportPdf = 'onSave',
  },
}
