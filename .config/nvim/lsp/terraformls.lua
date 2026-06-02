return {
  cmd = { 'terraform-ls', 'serve' },
  filetypes = {
    'terraform',
    'terraform-vars',
    'terraform-stack',
    'terraform-deploy',
    'terraform-search',
  },
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
