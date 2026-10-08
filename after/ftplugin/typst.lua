-- Typst files. PDF is exported on save by 'tinymist' (see 'after/lsp/tinymist.lua').

-- Open exported PDF in zathura, which reloads it after every save
local open_pdf = function()
  local pdf = vim.api.nvim_buf_get_name(0):gsub('%.typ$', '.pdf')
  if vim.fn.filereadable(pdf) == 0 then
    return vim.notify('No PDF yet, save the file to export it', vim.log.levels.WARN)
  end
  vim.system({ 'zathura', pdf }, { detach = true })
end

vim.api.nvim_buf_create_user_command(0, 'OpenPdf', open_pdf, { desc = 'Open exported PDF' })
vim.keymap.set('n', '<Leader>lp', open_pdf, { buffer = 0, desc = 'Open PDF' })
