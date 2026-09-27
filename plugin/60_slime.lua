vim.pack.add({
    { src = "https://github.com/jpalardy/vim-slime" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
})


vim.g.slime_target = "neovim"
vim.g.slime_dont_ask_default = 1
vim.g.slime_preserve_curpos = 0
vim.g.slime_no_mappings = 1
vim.g.slime_neovim_ignore_unlisted = 1
vim.b.slime_bracketed_paste = 1
vim.g.slime_bracketed_paste = 1
-- vim.g.slime_python_ipython = 1
-- vim.g.slime_paste_file = vim.fn.tempname()

vim.g.slime_default_config = {
    jobid = vim.v.null,
}

-- REPL configuration per filetype
local repl_commands = {
    -- python = "mamba activate aj_int && python",
    python = 'eval "$(mamba shell hook --shell zsh)" && mamba activate numpyro && python',
    -- `-L` file shows plots in figure pane (see 'plugin/55_figures.lua')
    julia = "julia --project=. --threads=20 -L " .. vim.fn.shellescape(Config.figures.julia_file),
    -- julia = "julia --project=. --threads=20 --sysimage=./sys.so",
}

-- Store terminal jobid globally
local terminal_jobid = nil
local terminal_bufnr = nil

-- Open window for REPL buffer in the right column: below figure pane (see
-- 'plugin/55_figures.lua') if it is shown, otherwise as the whole column
local function open_repl_win(buf)
    local fig_win = Config.figures.win()
    local config = fig_win and { split = "below", win = fig_win }
        or { split = "right", win = -1, width = Config.figures.column_width() }
    local win = vim.api.nvim_open_win(buf, false, config)
    vim.wo[win].winfixwidth = true
    return win
end

-- Fixed width windows (like REPL column) keep their width when a window next to
-- them is closed. Otherwise closing 'sidekick.nvim' window (to the right of REPL
-- column) gives all its space to REPL column instead of code.
Config.new_autocmd("WinClosed", "*", function(ev)
    local closed = tonumber(ev.match)
    if vim.api.nvim_win_get_config(closed).relative ~= "" then
        return
    end

    local widths = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(closed))) do
        if win ~= closed and vim.wo[win].winfixwidth then
            widths[win] = vim.api.nvim_win_get_width(win)
        end
    end

    -- Restore after the window is actually closed
    vim.schedule(function()
        for win, width in pairs(widths) do
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_set_width(win, width)
            end
        end
    end)
end, "Keep width of fixed width windows")

local function start_repl_for_filetype()
    local ft = vim.bo.filetype
    local cmd = repl_commands[ft]

    if not cmd then
        print("No REPL configured for filetype: " .. ft)
        return nil
    end

    if terminal_jobid and terminal_bufnr then
        if vim.api.nvim_buf_is_valid(terminal_bufnr) then
            return terminal_jobid
        end
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_call(open_repl_win(buf), function()
        -- Environment makes REPL send plots to figure pane
        terminal_jobid = vim.fn.jobstart(cmd, { term = true, env = Config.figures.env() })
    end)
    terminal_bufnr = buf
    Config.figures.repl_buf = buf

    return terminal_jobid
end

local function scroll_terminal_to_bottom()
    if terminal_bufnr and vim.api.nvim_buf_is_valid(terminal_bufnr) then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == terminal_bufnr then
                local current_win = vim.api.nvim_get_current_win()
                vim.api.nvim_set_current_win(win)
                vim.cmd("normal! G")
                vim.api.nvim_set_current_win(current_win)
                break
            end
        end
    end
end

-- Treesitter helpers using native API
local function get_current_node()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor[1] - 1, cursor[2] -- Convert to 0-indexed

    local parser = vim.treesitter.get_parser(0)
    if not parser then
        return nil
    end

    local tree = parser:parse()[1]
    if not tree then
        return nil
    end

    return tree:root():named_descendant_for_range(row, col, row, col)
end

local function get_top_level_node()
    local node = get_current_node()
    if not node then
        return nil
    end

    local top_level_types = {
        "function_definition",
        "class_definition",
        "decorated_definition",
        "expression_statement",
        "assignment",
        "if_statement",
        "for_statement",
        "while_statement",
        "with_statement",
        "try_statement",
        "import_statement",
        "import_from_statement",
    }

    while node do
        local node_type = node:type()

        for _, type in ipairs(top_level_types) do
            if node_type == type then
                local parent = node:parent()
                if parent and parent:type() == "module" then
                    return node
                end
            end
        end

        node = node:parent()
    end

    return nil
end

local function send_node_range(node)
    if not node then
        return false
    end

    local start_row, _, end_row, _ = node:range()
    vim.fn["slime#send_range"](start_row + 1, end_row + 1)
    return true
end

local function move_to_next_node()
    local current_node = get_top_level_node()
    if not current_node then
        return
    end

    local _, _, end_row, _ = current_node:range()
    vim.api.nvim_win_set_cursor(0, { end_row + 2, 0 })
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "python" },
    callback = function()
        -- Optionally auto-start
        -- start_repl_for_filetype()
    end,
})

vim.api.nvim_create_user_command("ReplStart", start_repl_for_filetype, {})

local function ensure_slime_config()
    if not terminal_jobid then
        terminal_jobid = start_repl_for_filetype()
    end

    if terminal_jobid then
        local current_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_var(current_buf, "slime_config", {
            jobid = terminal_jobid,
            target_pane = "",
        })
        return true
    end
    return false
end

local function send_and_execute(start_line, end_line)
    -- Get the lines to send
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

    if terminal_jobid and #lines > 0 then
        -- Join lines and add double newline at end to ensure execution
        local text = table.concat(lines, "\n") .. "\n\n"
        vim.api.nvim_chan_send(terminal_jobid, text)
    end
end

-- Key mappings
local opts = { noremap = true, silent = true }
vim.keymap.set("n", "r", "<Nop>")

-- Send Enter/newline to terminal
vim.keymap.set("n", "<CR>", function()
    if terminal_jobid then
        vim.api.nvim_chan_send(terminal_jobid, "\n")
        scroll_terminal_to_bottom()
    end
end, { noremap = true, silent = true, desc = "Execute in REPL" })

-- vim.keymap.set("n", "rp", "<Plug>SlimeParagraphSend))<CR>", opts)
vim.keymap.set("n", "rp", function()
    -- Execute the Slime command
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Plug>SlimeParagraphSend))", true, false, true))

    -- Then send newline to terminal
    vim.schedule(function()
        if terminal_jobid then
            vim.api.nvim_chan_send(terminal_jobid, "\n")
            scroll_terminal_to_bottom()
        end
    end)
end, { noremap = true, silent = true })

vim.keymap.set("n", "ro", function()
    -- Execute the Slime command
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Plug>SlimeParagraphSend", true, false, true))

    -- Then send newline to terminal
    vim.schedule(function()
        if terminal_jobid then
            vim.api.nvim_chan_send(terminal_jobid, "\n")
            scroll_terminal_to_bottom()
        end
    end)
end, { noremap = true, silent = true })

vim.keymap.set("n", "rr", function()
    if ensure_slime_config() then
        local node = get_top_level_node()
        if node then
            -- send_node_range(node)
            local start_row, _, end_row, _ = node:range()
            send_and_execute(start_row + 1, end_row + 1)
            -- Send as string: in a list, newlines inside an item are sent as NUL
            vim.api.nvim_chan_send(terminal_jobid, "\n\n")
            scroll_terminal_to_bottom()
            move_to_next_node()
        else
            print("No top-level statement found")
        end
    end
end, opts)

-- Visual mode - send selection
-- vim.keymap.set("v", "r", "<Plug>SlimeRegionSend", opts)
vim.keymap.set("v", "r", function()
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Plug>SlimeRegionSend", true, false, true))
    vim.schedule(function()
        if terminal_jobid then
            vim.api.nvim_chan_send(terminal_jobid, "\n")
            scroll_terminal_to_bottom()
        end
    end)
end, { noremap = true, silent = true })

vim.keymap.set("n", "r", "<Plug>SlimeMotionSend")
-- vim.keymap.set("n", "r", function()
--   vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Plug>SlimeMotionSend", true, false, true))
--   vim.schedule(function()
--     if terminal_jobid then
--       vim.api.nvim_chan_send(terminal_jobid, "\n")
--       scroll_terminal_to_bottom()
--     end
--   end)
-- end, { noremap = true, silent = true })

vim.keymap.set("n", "rs", start_repl_for_filetype, { noremap = true, silent = true, desc = "Start REPL" })

-- Toggle terminal visibility
vim.keymap.set("n", "rt", function()
    if not terminal_bufnr or not vim.api.nvim_buf_is_valid(terminal_bufnr) then
        print("No terminal running. Use <leader>rs to start REPL")
        return
    end

    -- Check if terminal is visible in any window
    local terminal_win = nil

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == terminal_bufnr then
            terminal_win = win
            break
        end
    end

    -- Terminal and figure pane (see 'plugin/55_figures.lua') act as one
    if terminal_win or Config.figures.win() then
        if terminal_win then
            vim.api.nvim_win_hide(terminal_win)
        end
        Config.figures.close()
    else
        -- Terminal first, so that figure pane opens above it
        open_repl_win(terminal_bufnr)
        Config.figures.open()
    end
end, { noremap = true, silent = true, desc = "Toggle REPL terminal and figure pane" })

-- Explicit hide terminal
vim.keymap.set("n", "rh", function()
    if not terminal_bufnr or not vim.api.nvim_buf_is_valid(terminal_bufnr) then
        return
    end

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == terminal_bufnr then
            vim.api.nvim_win_hide(win)
            break
        end
    end
end, { noremap = true, silent = true, desc = "Hide REPL terminal" })

-- Jump to terminal
vim.keymap.set("n", "<leader>j", function()
    if not terminal_bufnr or not vim.api.nvim_buf_is_valid(terminal_bufnr) then
        print("No terminal running. Use <leader>rs to start REPL")
        return
    end

    -- Find window with terminal
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == terminal_bufnr then
            vim.api.nvim_set_current_win(win)
            -- Enter insert mode in terminal
            vim.cmd("startinsert")
            return
        end
    end

    print("Terminal not visible. Use <leader>rt to show it")
end, { noremap = true, silent = true, desc = "Jump to REPL terminal" })

-- Jump back to last editor window
vim.keymap.set("t", "<C-j>", function()
    -- Exit terminal mode and go to previous window
    vim.cmd("wincmd p")
end, { noremap = true, silent = true, desc = "Jump back to editor" })

-- Alternative: also add this in normal mode for convenience
vim.keymap.set("n", "rk", function()
    -- Jump to previous window (useful when in terminal in normal mode)
    vim.cmd("wincmd p")
end, { noremap = true, silent = true, desc = "Jump to previous window" })
