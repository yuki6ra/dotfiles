return {
  cmd = { 'yaml-language-server', '--stdio' },
  filetypes = { 'yaml', 'yml' },
  on_init = function(client)
    client.config.settings.yaml = vim.tbl_deep_extend('force', client.config.settings.yaml or {}, {
      validate = true,
      format = {
        enable = true,
        bracketSpacing = true,
      },
    })
  end,
  settings = {
    yaml = {
      validate = true,
      format = {
        enable = true,
        bracketSpacing = true,
      },
    },
  },
}

