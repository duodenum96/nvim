-- git integration: gitsigns.nvim (inline hunk signs/staging/blame) +
-- vim-fugitive (full git command wrapper: status, commit, push, etc.)

vim.pack.add({
  "https://github.com/lewis6991/gitsigns.nvim",
  "https://github.com/tpope/vim-fugitive",
})

-- INFO: gitsigns — hunk-level signs, staging, blame, navigation
require("gitsigns").setup({
  on_attach = function(bufnr)
    local gs = package.loaded.gitsigns

    local function map(mode, l, r, desc)
      vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
    end

    -- navigation
    map("n", "]h", function()
      if vim.wo.diff then return "]c" end
      vim.schedule(function() gs.next_hunk() end)
      return "<Ignore>"
    end, "Next [H]unk")

    map("n", "[h", function()
      if vim.wo.diff then return "[c" end
      vim.schedule(function() gs.prev_hunk() end)
      return "<Ignore>"
    end, "Previous [H]unk")

    -- staging
    map("n", "<leader>hs", gs.stage_hunk, "[H]unk [S]tage")
    map("v", "<leader>hs", function()
      gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, "[H]unk [S]tage (selection)")
    map("n", "<leader>hu", gs.undo_stage_hunk, "[H]unk [U]ndo stage")
    map("n", "<leader>hr", gs.reset_hunk, "[H]unk [R]eset")
    map("v", "<leader>hr", function()
      gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, "[H]unk [R]eset (selection)")
    map("n", "<leader>hR", gs.reset_buffer, "[H]unk [R]eset buffer")

    -- inspection
    map("n", "<leader>hp", gs.preview_hunk, "[H]unk [P]review")
    map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, "[H]unk [B]lame line")
    map("n", "<leader>tb", gs.toggle_current_line_blame, "[T]oggle current line [B]lame")
    map("n", "<leader>hd", gs.diffthis, "[H]unk [D]iff this")

    -- text object: `ih` selects a hunk (e.g. dih, yih, vih)
    map({ "o", "x" }, "ih", gs.select_hunk, "select hunk")
  end,
})

-- INFO: fugitive — full git commands
-- no setup() needed, it works purely through :G / :Git commands.
-- inside the :Git status window itself, fugitive has its own builtin
-- keymaps (press `g?` while it's open to see all of them) — e.g. `s`/`u`
-- to stage/unstage under the cursor, `cc` to commit, `dd` to diff, etc.
-- the leader maps below are for triggering common actions from anywhere,
-- without having to open the status window first.

vim.keymap.set("n", "<leader>gs", vim.cmd.Git, { desc = "[G]it [S]tatus" })

vim.keymap.set("n", "<leader>ga", function()
  vim.cmd("Gwrite") -- stage the current file (git add equivalent)
end, { desc = "[G]it [A]dd (current file)" })

vim.keymap.set("n", "<leader>gc", function()
  vim.cmd("Git commit")
end, { desc = "[G]it [C]ommit" })

vim.keymap.set("n", "<leader>gd", function()
  vim.cmd("Gdiffsplit")
end, { desc = "[G]it [D]iff (current file)" })

vim.keymap.set("n", "<leader>gb", function()
  vim.cmd("Git blame")
end, { desc = "[G]it [B]lame" })

vim.keymap.set("n", "<leader>gl", function()
  vim.cmd("Git log")
end, { desc = "[G]it [L]og" })

vim.keymap.set("n", "<leader>gp", function()
  vim.cmd("Git push")
end, { desc = "[G]it [P]ush" })

vim.keymap.set("n", "<leader>gP", function()
  vim.cmd("Git pull")
end, { desc = "[G]it [P]ull" })

vim.keymap.set("n", "<leader>gr", function()
  vim.cmd("Gread") -- discard local changes to current file (checkout from index)
end, { desc = "[G]it [R]ead (discard local changes)" })

-- INFO: which-key groups
-- your init.lua already calls require("which-key").setup({ spec = {...} })
-- for the initial <leader>s group. `.add()` appends more groups the same
-- way — safe to call from any file, any time after which-key is loaded.
require("which-key").add({
  { "<leader>g", group = "[G]it", icon = { icon = "", color = "orange" } },
  { "<leader>h", group = "[H]unk", icon = { icon = "", color = "green" } },
})
