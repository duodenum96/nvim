-- Map <leader>w + key to the equivalent <C-w> + key
local wincmds = {
  h = "h", j = "j", k = "k", l = "l",   -- move focus
  w = "w", W = "W",                     -- cycle windows
  s = "s", v = "v",                     -- split horizontal/vertical
  c = "c", q = "q",                     -- close/quit window
  o = "o",                              -- close all other windows
  ["="] = "=",                          -- equalize sizes
  x = "x",                              -- swap windows
  r = "r", R = "R",                     -- rotate windows
  T = "T",                              -- move window to new tab
  p = "p",                              -- go to previous window
}

for lhs, rhs in pairs(wincmds) do
  vim.keymap.set("n", "<leader>w" .. lhs, "<C-w>" .. rhs, { desc = "Window: " .. rhs })
end

vim.keymap.set("n", "<leader>w+", "<C-w>+", { desc = "Increase height" })
vim.keymap.set("n", "<leader>w-", "<C-w>-", { desc = "Decrease height" })
vim.keymap.set("n", "<leader>w<", "<C-w><", { desc = "Decrease width" })
vim.keymap.set("n", "<leader>w>", "<C-w>>", { desc = "Increase width" })

vim.keymap.set("n", "<leader>bb", "<C-^>", { desc = "Previous buffer" })

-- visual + r, do this to get back to where you finished the visual selection
vim.keymap.set('n', '<C-p>', '<C-o>}', { noremap = true, silent = true }) 
