vim.pack.add({
  { src = "https://github.com/NeogitOrg/neogit" },
  { src = "https://github.com/nvim-mini/mini.pick" }, -- you already have this
  {src  = "https://github.com/m00qek/baleia.nvim"},            -- optional
})

vim.keymap.set("n", "<leader>gg", "<cmd>Neogit<cr>", { desc = "Show Neogit UI" })
