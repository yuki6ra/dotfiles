local wezterm = require("wezterm")
local act = wezterm.action

return {
	keys = {
		--------------------------------
		-- アプリ操作
		--------------------------------
		-- コマンドパレット表示
		{ key = "p", mods = "SHIFT|CTRL", action = act.ActivateCommandPalette },
		-- フルスクリーン
		{ key = "Enter", mods = "ALT", action = act.ToggleFullScreen },
		-- (macOS)アプリを非表示にする
		{ key = "H", mods = "CTRL", action = act.HideApplication },
		-- アプリを縮小化する
		{ key = "M", mods = "CTRL", action = act.Hide },

		-- よくわからない
		-- { key = "K", mods = "CTRL", action = act.ClearScrollback("ScrollbackOnly") },
		-- { key = "L", mods = "CTRL", action = act.ShowDebugOverlay },
		-- rootで新しいwindowを作成する?
		{ key = "N", mods = "CTRL", action = act.SpawnWindow },

		-- 全てのtabを閉じる(アプリを終了する)
		{ key = "Q", mods = "CTRL", action = act.QuitApplication },
		-- 設定再読み込み
		{ key = "R", mods = "CTRL", action = act.ReloadConfiguration },

		-- 上に1ページ分スクロールする
		{ key = "b", mods = "SHIFT|CTRL", action = act.ScrollByPage(-1) },
		-- 下に1ページ分スクロールする
		{ key = "f", mods = "SHIFT|CTRL", action = act.ScrollByPage(1) },

		-- ()検索
		-- { key = "f", mods = "CTRL", action = act.Search("CurrentSelectionOrEmptyString") },
		-- 絵文字を選ぶ?
		{
			key = "U",
			mods = "CTRL",
			action = act.CharSelect({ copy_on_select = true, copy_to = "ClipboardAndPrimarySelection" }),
		},

		--------------------------------
		-- tab
		--------------------------------
		-- 新規tab作成
		{ key = "t", mods = "SUPER", action = act.SpawnTab("CurrentPaneDomain") },
		-- 現在のtabを削除
		{ key = "w", mods = "SUPER", action = act.CloseCurrentTab({ confirm = true }) },
		-- tab移動
		{ key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
		{ key = "Tab", mods = "SHIFT|CTRL", action = act.ActivateTabRelative(-1) },
		-- tab切り替え
		{ key = "1", mods = "SUPER", action = act.ActivateTab(0) },
		{ key = "2", mods = "SUPER", action = act.ActivateTab(1) },
		{ key = "3", mods = "SUPER", action = act.ActivateTab(2) },
		{ key = "4", mods = "SUPER", action = act.ActivateTab(3) },
		{ key = "5", mods = "SUPER", action = act.ActivateTab(4) },
		{ key = "6", mods = "SUPER", action = act.ActivateTab(5) },
		{ key = "7", mods = "SUPER", action = act.ActivateTab(6) },
		{ key = "8", mods = "SUPER", action = act.ActivateTab(7) },
		{ key = "0", mods = "SUPER", action = act.ActivateTab(-1) },
		-- 現在のtabから相対的に移動
		-- { key = "PageUp", mods = "SHIFT|CTRL", action = act.MoveTabRelative(-1) },
		-- { key = "PageDown", mods = "SHIFT|CTRL", action = act.MoveTabRelative(1) },

		--------------------------------
		-- pane
		--------------------------------
		-- 縦に分割
		{ key = "d", mods = "SUPER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
		-- 横に分割
		{ key = "D", mods = "SUPER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
		-- paneを閉じる
		{ key = "x", mods = "SUPER", action = act({ CloseCurrentPane = { confirm = true } }) },
		-- pane移動
		{ key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
		{ key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
		{ key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
		{ key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
		-- pane選択
		{ key = "[", mods = "CTRL", action = act.PaneSelect },
		-- 選択中のPaneのみ表示
		{ key = "z", mods = "CTRL|SHIFT", action = act.TogglePaneZoomState },
		-- paneのサイズを調整する
		{ key = "LeftArrow", mods = "ALT", action = act.AdjustPaneSize({ "Left", 1 }) },
		{ key = "RightArrow", mods = "ALT", action = act.AdjustPaneSize({ "Right", 1 }) },
		{ key = "UpArrow", mods = "ALT", action = act.AdjustPaneSize({ "Up", 1 }) },
		{ key = "DownArrow", mods = "ALT", action = act.AdjustPaneSize({ "Down", 1 }) },

		--------------------------------
		-- copy
		--------------------------------
		-- copy
		{ key = "c", mods = "SUPER", action = act.CopyTo("Clipboard") },
		-- paste
		{ key = "v", mods = "SUPER", action = act.PasteFrom("Clipboard") },
		-- copy mode
		{ key = "c", mods = "CTRL|SHIFT", action = act.ActivateCopyMode },
		-- quickSelectModeを起動する
		{ key = "phys:Space", mods = "SHIFT|CTRL", action = act.QuickSelect },

		--------------------------------
		-- font size
		--------------------------------
		-- reset font size
		{ key = "0", mods = "CTRL", action = act.ResetFontSize },
		-- font size拡大
		{ key = "+", mods = "CTRL", action = act.IncreaseFontSize },
		-- font size縮小
		{ key = "-", mods = "CTRL", action = act.DecreaseFontSize },
	},

	key_tables = {
		copy_mode = {
			{ key = "Tab", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
			{ key = "Tab", mods = "SHIFT", action = act.CopyMode("MoveBackwardWord") },
			{ key = "Enter", mods = "NONE", action = act.CopyMode("MoveToStartOfNextLine") },
			{ key = "Escape", mods = "NONE", action = act.Multiple({ "ScrollToBottom", { CopyMode = "Close" } }) },
			{ key = "Space", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
			{ key = "$", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
			{ key = "$", mods = "SHIFT", action = act.CopyMode("MoveToEndOfLineContent") },
			{ key = ",", mods = "NONE", action = act.CopyMode("JumpReverse") },
			{ key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
			{ key = ";", mods = "NONE", action = act.CopyMode("JumpAgain") },
			{ key = "F", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
			{ key = "F", mods = "SHIFT", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
			{ key = "G", mods = "NONE", action = act.CopyMode("MoveToScrollbackBottom") },
			{ key = "G", mods = "SHIFT", action = act.CopyMode("MoveToScrollbackBottom") },
			{ key = "H", mods = "NONE", action = act.CopyMode("MoveToViewportTop") },
			{ key = "H", mods = "SHIFT", action = act.CopyMode("MoveToViewportTop") },
			{ key = "L", mods = "NONE", action = act.CopyMode("MoveToViewportBottom") },
			{ key = "L", mods = "SHIFT", action = act.CopyMode("MoveToViewportBottom") },
			{ key = "M", mods = "NONE", action = act.CopyMode("MoveToViewportMiddle") },
			{ key = "M", mods = "SHIFT", action = act.CopyMode("MoveToViewportMiddle") },
			{ key = "O", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEndHoriz") },
			{ key = "O", mods = "SHIFT", action = act.CopyMode("MoveToSelectionOtherEndHoriz") },
			{ key = "T", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
			{ key = "T", mods = "SHIFT", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
			{ key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },
			{ key = "V", mods = "SHIFT", action = act.CopyMode({ SetSelectionMode = "Line" }) },
			{ key = "^", mods = "NONE", action = act.CopyMode("MoveToStartOfLineContent") },
			{ key = "^", mods = "SHIFT", action = act.CopyMode("MoveToStartOfLineContent") },
			{ key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
			{ key = "b", mods = "ALT", action = act.CopyMode("MoveBackwardWord") },
			{ key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
			{ key = "c", mods = "CTRL", action = act.Multiple({ "ScrollToBottom", { CopyMode = "Close" } }) },
			{ key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage = 0.5 }) },
			{ key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
			{ key = "f", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = false } }) },
			{ key = "f", mods = "ALT", action = act.CopyMode("MoveForwardWord") },
			{ key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },
			{ key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
			{ key = "g", mods = "CTRL", action = act.Multiple({ "ScrollToBottom", { CopyMode = "Close" } }) },
			{ key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
			{ key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
			{ key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
			{ key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
			{ key = "m", mods = "ALT", action = act.CopyMode("MoveToStartOfLineContent") },
			{ key = "o", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEnd") },
			{ key = "q", mods = "NONE", action = act.Multiple({ "ScrollToBottom", { CopyMode = "Close" } }) },
			{ key = "t", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = true } }) },
			{ key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
			{ key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
			{ key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },
			{ key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
			{
				key = "y",
				mods = "NONE",
				action = act.Multiple({
					{ CopyTo = "ClipboardAndPrimarySelection" },
					{ Multiple = { "ScrollToBottom", { CopyMode = "Close" } } },
				}),
			},
			{ key = "PageUp", mods = "NONE", action = act.CopyMode("PageUp") },
			{ key = "PageDown", mods = "NONE", action = act.CopyMode("PageDown") },
			{ key = "End", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
			{ key = "Home", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
			{ key = "LeftArrow", mods = "NONE", action = act.CopyMode("MoveLeft") },
			{ key = "LeftArrow", mods = "ALT", action = act.CopyMode("MoveBackwardWord") },
			{ key = "RightArrow", mods = "NONE", action = act.CopyMode("MoveRight") },
			{ key = "RightArrow", mods = "ALT", action = act.CopyMode("MoveForwardWord") },
			{ key = "UpArrow", mods = "NONE", action = act.CopyMode("MoveUp") },
			{ key = "DownArrow", mods = "NONE", action = act.CopyMode("MoveDown") },
		},

		search_mode = {
			{ key = "Enter", mods = "NONE", action = act.CopyMode("PriorMatch") },
			{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
			{ key = "n", mods = "CTRL", action = act.CopyMode("NextMatch") },
			{ key = "p", mods = "CTRL", action = act.CopyMode("PriorMatch") },
			{ key = "r", mods = "CTRL", action = act.CopyMode("CycleMatchType") },
			{ key = "u", mods = "CTRL", action = act.CopyMode("ClearPattern") },
			{ key = "PageUp", mods = "NONE", action = act.CopyMode("PriorMatchPage") },
			{ key = "PageDown", mods = "NONE", action = act.CopyMode("NextMatchPage") },
			{ key = "UpArrow", mods = "NONE", action = act.CopyMode("PriorMatch") },
			{ key = "DownArrow", mods = "NONE", action = act.CopyMode("NextMatch") },
		},
	},
}
