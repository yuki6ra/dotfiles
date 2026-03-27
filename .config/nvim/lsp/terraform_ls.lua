return {
  cmd = { 'terraform-ls', 'serve' },
  filetypes = {
    'terraform',
    'terraform-vars',
    'terraform-stack',
    'terraform-deploy',
    'terraform-search',
  },
  on_init = function(client)
    -- terraform-ls 側には lua-language-server のような
    -- 「Neovim 自身のランタイムを workspace に追加する」ような処理は不要なので、
    -- ここでは「プロジェクトルートに設定があればそれを優先する」
    -- という意味合いだけを lua-language-server 版と同様に残しています。
    if client.workspace_folders then
      local path = client.workspace_folders[1].name
      if path ~= vim.fn.stdpath('config') and (
            vim.uv.fs_stat(path .. '/.terraform-ls.json')
            or vim.uv.fs_stat(path .. '/.terraform-ls.jsonc')
          ) then
        -- プロジェクト側の設定ファイルがある場合は
        -- ここで早期 return して Neovim 側からの上書きを行わない
        return
      end
    end
    vim.cmd("autocmd BufNewFile,BufRead *.tf set filetype=terraform")
  end,
  settings = {
    -- terraform-ls の設定ルートは通常 `terraform` または `terraform-ls` 側で解釈されます。
    -- 公式ドキュメントに従ってここに必要な設定を追加してください。
    terraform = {
      -- 例: diagnostics まわりの設定を入れる場所（実際のキーは terraform-ls の SETTINGS.md を参照）
      -- diagnostics = {
      --   enable = true,
      -- },
    },
  }
}
