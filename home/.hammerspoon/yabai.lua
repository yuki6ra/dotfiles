-- Send message(s) to a running instance of yabai.
local function yabai(commands)
    for _, cmd in ipairs(commands) do
      os.execute("/opt/homebrew/bin/yabai -m " .. cmd)
    end
end

local function alt(key, commands)
	hs.hotkey.bind({ "alt" }, key, function()
		yabai(commands)
	end)
end

local function altCmd(key, commands)
	hs.hotkey.bind({ "alt", "cmd" }, key, function()
		yabai(commands)
	end)
end

local function altShift(key, commands)
	hs.hotkey.bind({ "alt", "shift" }, key, function()
		yabai(commands)
	end)
end

local homeRow = {
    h = "west",
    j = "south",
    k = "north",
    l = "east"
}

-- focus | swap | warp WINDOW
for key, direction in pairs(homeRow) do
	alt(key, { "window --swap " .. direction })
	altShift(key, { "window --focus " .. direction })
    altCmd(key, { "window --warp " .. direction })
end

-- focus | swap RECENT WINDOW
alt("x" , {"window --focus recent"})
altShift("x", {"window --swap recent"})

local moveRow = {
    left = "rel:-20:0",
    down = "rel:0:20",
    up = "rel:0:-20",
    right = "rel:20:0"
}

-- move WINDOW
for key, direction in pairs(moveRow) do
    alt(key, { "window --move " .. direction })
end

local increaseRow = {
    left = "left:-20:0",
    down = "bottom:0:20",
    up = "top:0:-20",
    right = "right:20:0",
}

-- increase WINDOW
for key, direction in pairs(increaseRow) do
    altShift(key, { "window --resize " .. direction })
end

local decreaseRow = {
    left = "left:20:0",
    down = "bottom:0:-20",
    up = "top:0:20",
    right = "left:-20:0"
}

-- decrease WINDOW
for key, direction in pairs(decreaseRow) do
    altCmd(key, { "window --resize " .. direction })
end

-- fill screen
local fillRow = {
    a = "1:2:0:0:1:1",
    s = "1:2:1:0:1:1",
    w = "2:1:0:0:1:1",
    d = "2:1:0:1:1:1"
}

for key, direction in pairs(fillRow) do
    altShift(key, { "window --toggle float --grid " .. direction })
end

-- rotate tree
alt("r", { "space --rotate 90" })

-- mirror tree y-axis
altCmd("y", { "space --mirror y-axis" })

-- mirror tree x-axis
altCmd("x", { "space --mirror x-axis" })

-- toggle desktop offset
alt("o", { "space --toggle padding", "space --toggle gap" })

-- toggle window fullscreen zoom
alt("f", { "window --toggle zoom-fullscreen" })

-- toggle window native fullscreen
altShift("f", { "window --toggle native-fullscreen" })

-- toggle window split type
alt("e", { "window --toggle split" })

-- float / unfloat window and restore position
alt("t", { "window --toggle float", "window --grid 4:4:1:1:2:2" })
