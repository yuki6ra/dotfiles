local later = Config.later

later(function()
  vim.pack.add({ 'https://github.com/MeanderingProgrammer/render-markdown.nvim' })
  require('render-markdown').setup({
    enabled = true,
    pipe_table = {
      preset = 'round',
    },
  })

  -- コマンドでpreview enable
  vim.api.nvim_set_keymap("n", "<leader>m", "<CMD>RenderMarkdown toggle<CR>", { desc = "Toggles `render-markdown` previews globally." });
end)
