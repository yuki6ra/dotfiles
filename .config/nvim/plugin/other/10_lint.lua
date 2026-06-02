-- コード診断、フォーマットは基本LSP
-- チーム内で共有のツールを使う場合、こちらで設定する
local later = Config.later

-- nvim-lint
later(function()
  vim.pack.add({ 'https://github.com/mfussenegger/nvim-lint' })
  local lint = require('lint')
  lint.linters_by_ft = {
    terraform = { 'tflint' },
    terraformvars = { 'tflint' },
  }

  -- 保存時やバッファ切り替えでlinterを実行
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter", "InsertLeave" }, {
    callback = function()
      lint.try_lint()
    end,
  })
end)

-- conform.nvim
later(function()
  vim.pack.add({ 'https://github.com/stevearc/conform.nvim' })
  local conform = require('conform')
  conform.setup({
    formatters_by_ft = {
      json = { "prettier" },
      yaml = { "prettier" },
      -- terraform = { 'terraform_fmt' }
    },
    format_on_save = {
      lsp_fallback = true,  -- LSPのformatと併用
    }
  })

  vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*",
    callback = function(args)
      conform.format({ bufnr = args.buf })
    end,
  })
end)
