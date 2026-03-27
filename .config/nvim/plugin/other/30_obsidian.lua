Config.later(function()
  vim.pack.add {
    {
      src = "https://github.com/obsidian-nvim/obsidian.nvim",
      version = vim.version.range "*", -- use latest release, remove to use latest commit
    },
  }
  require('obsidian').setup({
    workspaces = {
      {
        name = "test vault",
        path = "~/Documents/vault"
      }
    },
    legacy_commands = false,
  })
end)
