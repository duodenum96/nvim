
vim.pack.add({ 'https://github.com/nvim-mini/mini.nvim' })
require("opts.keybinds")
require("plugins.slime")

vim.lsp.enable('julials')


-- local ok, matugen = pcall(require, 'matugen')
-- if ok then matugen.setup() end
