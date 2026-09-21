local function toggleApp(appName)
  local app = hs.application.get(appName)

  if app == nil then
    -- 未起動なら起動
    hs.application.launchOrFocus(appName)
  elseif app:isFrontmost() then
    -- 最前面なら非表示
    app:hide()
  else
    -- 起動済みなら最前面へ
    app:activate()
  end
end

hs.hotkey.bind({ "alt" }, "space", function()
  toggleApp("Ghostty")
end)
