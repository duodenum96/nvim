-- kiyoon/treesitter-indent-object.nvim
-- context-aware indent text object powered by treesitter.
-- selects a contiguous block of lines at the same (or deeper) indent level
-- as the cursor, expanding to include the containing line where the indent
-- starts (e.g. the `if`/`def`/`function` line above a body).
--
-- `ai` / `ii` -> charwise-ish select around/inside the indent block
-- `aI` / `iI` -> linewise variants (grab whole lines, useful for things
--                like python where you want entire lines, not partial ones)

vim.pack.add({
  "https://github.com/kiyoon/treesitter-indent-object.nvim",
})

-- no setup() call is required by the plugin, but calling it is recommended
-- (keeps behaviour consistent if you later add indent-blankline, which this
-- plugin can pick pattern-matching options from)
require("treesitter_indent_object").setup()

vim.keymap.set({ "x", "o" }, "ai", function()
  require("treesitter_indent_object.textobj").select_indent_outer()
end, { desc = "Select context-aware indent (outer)" })

vim.keymap.set({ "x", "o" }, "ii", function()
  require("treesitter_indent_object.textobj").select_indent_inner()
end, { desc = "Select context-aware indent (inner, partial range)" })

vim.keymap.set({ "x", "o" }, "aI", function()
  require("treesitter_indent_object.textobj").select_indent_outer(true, "V")
  require("treesitter_indent_object.refiner").include_surrounding_empty_lines()
end, { desc = "Select context-aware indent (outer, linewise)" })

vim.keymap.set({ "x", "o" }, "iI", function()
  require("treesitter_indent_object.textobj").select_indent_inner(true, "V")
end, { desc = "Select context-aware indent (inner, linewise, entire range)" })
