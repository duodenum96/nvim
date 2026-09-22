vim.filetype.add({ extension = { cu = 'cuda', cuh = 'cuda' } })
vim.treesitter.language.register('cpp', 'cuda')

vim.lsp.config('clangd', {
  cmd = {
    'clangd',
    '--background-index',
    '--query-driver=/usr/local/cuda*/bin/nvcc,/usr/bin/gcc-15,/usr/bin/g++-15',
  },
  filetypes = { 'c', 'cpp', 'cuda', 'objc', 'objcpp' },
})
vim.lsp.enable({ 'clangd' })

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'cuda', 'cpp', 'c' },
  callback = function()
    vim.opt_local.makeprg = 'bear -- make'
  end,
})

vim.keymap.set('n', '<leader>m', function()
  local dir = vim.fn.expand('%:p:h')
  vim.cmd('lcd ' .. dir)   -- so :make and bear run against this lab's Makefile
  vim.cmd('make')
end, { desc = 'Build current CUDA lab' })

vim.keymap.set('n', '<leader>co', ':copen<CR>', { desc = 'Open quickfix' })
