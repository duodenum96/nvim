-- ~/.config/nvim/lua/plugins/dashboard.lua
-- Preconfigured snacks.nvim dashboard.
-- Requires: this file to be `require`'d from init.lua, e.g.
--   require("plugins.dashboard")

vim.pack.add({
  "https://github.com/folke/snacks.nvim",
})

require("snacks").setup({
    image={enabled=true},

  dashboard = {
    enabled = true,

    preset = {
      header = [[
 ______            _______  ______   _______          _________ _______ 
(  __  \ |\     /|(  ___  )(  __  \ (  ____ \|\     /|\__   __/(       )
| (  \  )| )   ( || (   ) || (  \  )| (    \/| )   ( |   ) (   | () () |
| |   ) || |   | || |   | || |   ) || (__    | |   | |   | |   | || || |
| |   | || |   | || |   | || |   | ||  __)   ( (   ) )   | |   | |(_)| |
| |   ) || |   | || |   | || |   ) || (       \ \_/ /    | |   | |   | |
| (__/  )| (___) || (___) || (__/  )| (____/\  \   /  ___) (___| )   ( |
(______/ (_______)(_______)(______/ (_______/   \_/   \_______/|/     \|
                                                                        
                        ______   ______   ______                          
                      / ____ \ / ____ \ / ____ \                         
                      ( (    \/( (    \/( (    \/                         
                      | (____  | (____  | (____                           
                      |  ___ \ |  ___ \ |  ___ \                          
                      | (   ) )| (   ) )| (   ) )                         
                      ( (___) )( (___) )( (___) )                         
  \_____/  \_____/  \_____/    
]],

      -- Custom keymap buttons shown on the dashboard.
      -- Uses Snacks' picker if you have fzf-lua / telescope.nvim / mini.pick installed;
      -- falls back gracefully to plain vim commands otherwise.
      keys = {
        { icon = " ", key = "f", desc = "Find File",     action = ":lua Snacks.dashboard.pick('files')" },
        { icon = " ", key = "n", desc = "New File",      action = ":ene | startinsert" },
        { icon = " ", key = "g", desc = "Find Text",     action = ":lua Snacks.dashboard.pick('live_grep')" },
        { icon = " ", key = "r", desc = "Recent Files",  action = ":lua Snacks.dashboard.pick('oldfiles')" },
        { icon = " ", key = "c", desc = "Config",        action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
        { icon = " ", key = "q", desc = "Quit",          action = ":qa" },
      },
    },


    sections = {
      { section = "header" },
      { section = "keys", gap = 1, padding = 1 },
      { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1, limit = 5 },
      { icon = " ", title = "Projects",     section = "projects",     indent = 2, padding = 1, limit = 5 },
  -- image, in a second column to the right
--       {
--         pane = 2,
--         section = "terminal",
-- cmd = "chafa ~/Pictures/Wallpapers/images.jpg --format kitty --size 60x30 --stretch; sleep .1",
--         -- height = 17,
--         -- padding = 1,
--       },
      -- Simple footer instead of `startup` (that section requires lazy.nvim)
      {
        text = { { "⚡ Neovim " .. tostring(vim.version()), hl = "SnacksDashboardDesc" } },
        align = "center",
        padding = 1,
      },
    },
  },
})

