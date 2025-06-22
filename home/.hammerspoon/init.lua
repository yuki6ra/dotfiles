hyper = { "ctrl", "alt", "cmd" }
meh = { "ctrl", "alt" }

-- initialize modal manager
-- spoon.SpoonInstall:andUse('ModalMgr')

-- spoon.ModalMgr.supervisor:bind('alt', 'L', 'Lock Screen', function() hs.caffeinate.lockScreen() end)
-- spoon.ModalMgr.supervisor:bind('alt', 'Z', 'Toggle Hammerspoon Console', function() hs.toggleConsole() end)

require("terminal")
-- require("yabai")
require("cheatsheet")

-- spoon.ModalMgr.supervisor:enter()
