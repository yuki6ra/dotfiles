-- 初回Wezterm起動
-- hs.hotkey.bind({ "cmd" }, "return", function()
--     hs.execute("open -na /opt/homebrew/bin/wezterm")
-- end)

local centering = function()
	local win = hs.window.focusedWindow()
	local f = win:frame()
	local max = win:screen():frame()

	local x = f

	x.x = ((max.w - f.w) / 2) + max.x
	x.y = ((max.h - f.h) / 2) + max.y
	win:setFrame(x)
end

local open_terminal = function()
	local appName = "Ghostty"
	-- local toScreen = nil
	-- local inBounds = true
	local app = hs.application.get(appName)

	if app == nil or app:isHidden() or not (app:isFrontmost()) then
		hs.application.launchOrFocus(appName)
		-- hs.window.focusedWindow():centerOnScreen(toScreen, inBounds)
		centering()
	else
		app:hide()
	end
end

hs.hotkey.bind({ "option" }, "space", open_terminal)
