-- Kernel logic test: drives nimbus/kernel/wm.lua with fake ComputerCraft APIs.
-- Run from the project root:  lune run tests/kernel.luau
-- Covers routing, z-order, drag/resize/snap and window lifetime. It does NOT prove the
-- code runs on real CC; tests/phase1.lua does that inside the game or CraftOS-PC.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

-- A text-only stand-in for CC's window API (colors are accepted and ignored).
local function fakeWindow(par, x, y, w, h, visible)
	local self, lines = {}, {}
	local cx, cy, blink, fg = 1, 1, false, 1
	local function fit()
		for i = 1, h do
			local l = (lines[i] or ""):sub(1, w)
			lines[i] = l .. string.rep(" ", w - #l)
		end
		for i = h + 1, #lines do lines[i] = nil end
	end
	local function redraw()
		if not (visible and par) then return end
		for i = 1, h do
			par.setCursorPos(x, y + i - 1)
			par.write(lines[i])
		end
	end
	fit()
	function self.write(s)
		s = tostring(s)
		local from, to = math.max(1, cx), math.min(w, cx + #s - 1)
		if cy >= 1 and cy <= h and from <= to then
			lines[cy] = lines[cy]:sub(1, from - 1) .. s:sub(from - cx + 1, to - cx + 1) .. lines[cy]:sub(to + 1)
		end
		cx += #s
		redraw()
	end
	function self.clear() lines = {} fit() redraw() end
	function self.clearLine() if lines[cy] then lines[cy] = string.rep(" ", w) redraw() end end
	function self.setCursorPos(nx, ny) cx, cy = nx, ny end
	function self.getCursorPos() return cx, cy end
	function self.setCursorBlink(b) blink = b end
	function self.getCursorBlink() return blink end
	function self.setTextColor(c) fg = c end
	function self.getTextColor() return fg end
	function self.setBackgroundColor() end
	function self.getSize() return w, h end
	function self.getLine(n) return lines[n] end
	function self.setVisible(v) if v and not visible then visible = v redraw() end visible = v end
	function self.reposition(nx, ny, nw, nh, np) x, y, w, h, par = nx, ny, nw, nh, np or par fit() redraw() end
	return self
end

local current
local log = {}
local env

-- Stand-in for every program: fills its window with its tag letter and logs its events.
local function app(penv, tag)
	tag = tag or "t"
	local t = current
	penv.multishell.setTitle(penv.multishell.getCurrent(), "app-" .. tag)
	local function paint()
		local w, h = t.getSize()
		for y = 1, h do
			t.setCursorPos(1, y)
			t.write(string.rep(tag, w))
		end
	end
	paint()
	if tag == "x" then return end -- exits at once, before any input
	local filter = if tag == "f" then "rednet_message" else nil
	while true do
		local ev = table.pack(coroutine.yield(filter))
		table.insert(log, tag .. ":" .. table.concat(ev, " ", 1, ev.n))
		if ev[1] == "terminate" then error("Terminated", 0) end
		if ev[1] == "term_resize" or ev[1] == "repaint" then paint() end
	end
end

local base = fakeWindow(nil, 1, 1, 51, 19, true)
local modules = {}
env = {
	term = {
		redirect = function(t) local prev = current current = t return prev end,
		current = function() return current end,
	},
	window = { create = fakeWindow },
	colors = setmetatable({}, { __index = function() return 1 end }),
	fs = { getName = function(p) return p:match("[^/]+$") end },
	textutils = { formatTime = function() return "12:00" end },
	shell = {},
	keys = { tab = 15, leftCtrl = 29, rightCtrl = 157 },
	print = function(s) current.write(s) end,
	os = {
		time = function() return 0 end,
		startTimer = function() return 1000 end,
		run = function(penv, _path, ...) return (pcall(app, penv, ...)) end,
		pullEvent = function(filter)
			while true do
				local ev = table.pack(coroutine.yield(filter))
				if ev[1] == "terminate" then error("Terminated", 0) end
				if not filter or ev[1] == filter then return table.unpack(ev, 1, ev.n) end
			end
		end,
		reboot = function() table.insert(log, "reboot") end,
		shutdown = function() table.insert(log, "shutdown") end,
	},
}
env.require = function(name)
	if modules[name] == nil then
		local src = fs.readFile("nimbus/" .. name:gsub("%.", "/") .. ".lua")
		modules[name] = luau.load(src, { debugName = name, environment = env })()
	end
	return modules[name]
end

local wm = env.require("kernel.wm")
current = base
wm.init(base)

local passed = 0
local function check(cond, what)
	if not cond then error("FAIL: " .. what .. "\n  log: " .. table.concat(log, " | "), 2) end
	passed += 1
end
local function cell(x, y) return base.getLine(y):sub(x, x) end
local function onScreen(text)
	for y = 1, select(2, base.getSize()) do
		local x = base.getLine(y):find(text, 1, true)
		if x then return x, y end
	end
	return nil
end
local function logged(entry)
	local found = table.find(log, entry) ~= nil
	return found
end
local function step(...) table.clear(log) wm.step(...) end
local function click(x, y) step("mouse_click", 1, x, y) wm.step("mouse_up", 1, x, y) end
local function top() return wm.wins[#wm.wins] end

-- two overlapping windows: a at (2,2), b at (4,3), both 41x13
local a, b = wm.run("a"), wm.run("b")
wm.step()
check(#wm.wins == 2 and top() == b, "newest window is on top")
check(a.title == "app-a" and b.title == "app-b", "programs title their windows through the multishell shim")
check(cell(4, 4) == "b" and cell(2, 3) == "a", "top window covers the one beneath; exposed part still shows")

step("char", "z")
check(#log == 1 and logged("b:char z"), "keyboard goes only to the focused window")

step("mouse_click", 1, 2, 4)
check(top() == a and logged("a:mouse_click 1 1 2"), "clicking a window focuses it and sends window-local coordinates")
check(cell(5, 5) == "a", "focused window is drawn on top")
step("mouse_up", 1, 2, 4)
check(logged("a:mouse_up 1 1 2"), "mouse_up follows the window that took the click")

step("repaint")
check(logged("a:repaint") and logged("b:repaint"), "other events are broadcast")
check(cell(5, 5) == "a" and cell(44, 10) == "b", "a background repaint can't draw over the top window")

step("timer", 1000)
check(#log == 0, "the taskbar clock timer is not leaked to programs")

-- move by the title bar
step("mouse_click", 1, 5, 2)
wm.step("mouse_drag", 1, 10, 6)
wm.step("mouse_up", 1, 10, 6)
check(a.x == 7 and a.y == 6 and #log == 0, "dragging the title bar moves the window without telling the program")

-- maximize and restore (buttons are the last 12 cells of the title bar: # _ + x)
click(a.x + a.w - 5, a.y)
local bw, bh = a.body.getSize()
check(a.layout == "max" and a.w == 51 and a.h == 18 and bw == 51 and bh == 17, "maximize fills the work area")
check(logged("a:term_resize"), "the program is told its window resized")
click(a.x + a.w - 5, a.y)
check(a.x == 7 and a.y == 6 and a.w == 41 and a.h == 13 and not a.layout, "maximize again restores")

-- snap menu
click(a.x + a.w - 11, a.y)
local mx, my = onScreen("Left half")
check(mx ~= nil, "snap button opens the layout menu")
click(mx, my)
check(a.layout == "left" and a.x == 1 and a.y == 1 and a.w == 25 and a.h == 18, "snap left half")
check(not onScreen("Left half"), "menu closes after a pick")

-- dragging a snapped window restores its size; releasing at the right edge snaps right
step("mouse_click", 1, 3, 1)
wm.step("mouse_drag", 1, 20, 5)
check(not a.layout and a.w == 41 and a.x == 18 and a.y == 5, "dragging a snapped window un-snaps it")
wm.step("mouse_drag", 1, 51, 8)
wm.step("mouse_up", 1, 51, 8)
check(a.layout == "right" and a.x == 26 and a.w == 26, "dropping at the right edge snaps right")

-- resize b from its bottom-right grip
click(5, 3)
check(top() == b and b.x == 4, "a plain title click focuses without moving")
step("mouse_click", 1, b.x + b.w - 1, b.y + b.h - 1)
wm.step("mouse_drag", 1, 40, 12)
wm.step("mouse_up", 1, 40, 12)
check(b.w == 37 and b.h == 10 and logged("b:term_resize"), "corner drag resizes")
wm.step("mouse_click", 1, b.x + b.w - 1, b.y + b.h - 1)
wm.step("mouse_drag", 1, 1, 1)
wm.step("mouse_up", 1, 1, 1)
check(b.w == 16 and b.h == 3, "resize stops at the minimum size")

-- minimize / taskbar
click(b.x + b.w - 8, b.y)
check(b.minimized and top() == a, "minimize hands focus to the next window")
wm.focus(b)
check(not b.minimized and top() == b, "focusing restores a minimized window")

-- event filters, Ctrl+T, and programs that exit
local f = wm.run("f")
step("timer", 7)
check(logged("a:timer 7") and logged("b:timer 7") and not logged("f:timer 7"), "a process waiting on a filter is not woken by other events")
step("rednet_message", 3, "hi")
check(logged("f:rednet_message 3 hi"), "filtered event arrives")
check(top() == f, "new window takes focus")
step("terminate")
check(#wm.wins == 2 and #log == 1, "Ctrl+T closes only the focused program")

local x = wm.run("x")
wm.step()
check(#wm.wins == 3 and x.proc.filter == "key", "a program that exits unseen keeps its window until a key")
step("key", 28)
check(#wm.wins == 2, "then a key closes it")

local id = wm.multishell.launch({ multishell = wm.multishell }, "rom/programs/worm.lua", "g")
wm.step()
check(#wm.wins == 3 and wm.wins[2].id == id and wm.multishell.getFocus() ~= id, "multishell.launch opens in the background (bg)")
check(wm.multishell.setFocus(id) and top().id == id, "multishell.setFocus raises it (fg)")

-- display resize re-fits snapped windows
base.reposition(1, 1, 60, 25)
step("term_resize")
check(a.layout == "right" and a.x == 31 and a.w == 30 and a.h == 24, "snapped windows follow a display resize")

-- close buttons, then relaunch from Start
while #wm.wins > 0 do
	local n = #wm.wins
	click(top().x + top().w - 2, top().y)
	check(#wm.wins == n - 1, "close button closes window " .. n)
end

-- the hooks the desktop shell uses
local got = {}
wm.desktop = { draw = function() end, click = function() table.insert(got, "desk") end }
wm.taskbar = { draw = function() end, click = function(_, tx) table.insert(got, "bar" .. tx) end }
click(1, 1)
click(5, 25)
check(table.concat(got, " ") == "desk bar5", "clicks on the desktop and taskbar row go to the shell")

local a2, b2 = wm.run("a"), wm.run("b")
step("key", 29)
check(logged("b:key 29"), "modifier keys still reach the program")
step("key", 15)
check(top() == a2 and #log == 0, "Ctrl+Tab cycles windows and is not passed on")
wm.step("key_up", 29)
step("key", 15)
check(top() == a2 and logged("a:key 15"), "Tab alone is an ordinary key")

wm.on(function(e) return e == "ping" end)
step("ping")
check(#log == 0, "a listener can swallow an event")

got = {}
wm.overlay({
	draw = function() base.setCursorPos(1, 1) end,
	click = function() return false end,
	key = function(_, ch) table.insert(got, ch) return ch ~= "q" end,
})
step("char", "z")
step("char", "q")
check(table.concat(got) == "zq" and #log == 0, "an overlay with a key handler takes the keyboard")
step("char", "k")
check(logged("a:char k"), "and gives it back when it closes")
check(b2 ~= nil, "second window still open")

-- a second display that only reports taps, like a monitor
local mon = fakeWindow(nil, 1, 1, 60, 25, true)
local function onMon(text)
	for y = 1, 25 do
		local x = mon.getLine(y):find(text, 1, true)
		if x then return x, y end
	end
	return nil
end
local d2 = wm.addDisplay("monitor", mon)
wm.step()
check(onMon("app-") == nil and onScreen("app-a") ~= nil, "existing windows stay on their own display")
wm.touch(d2, 30, 10)
local m = wm.run("m")
wm.step()
check(m.display == d2 and onMon("mmm") and not onScreen("mmm"), "a new window opens on the display that was tapped last")

local x0 = m.x
wm.touch(d2, m.x + 2, m.y)
wm.step()
local px, py = onMon("Move (then tap)")
check(px ~= nil and m.x == x0, "a tap on a title bar opens the window menu instead of dragging")
wm.touch(d2, px, py)
wm.touch(d2, 12, 6)
check(m.x == 12 and m.y == 6, "Move, then a tap, places the window")

wm.armed = true
table.clear(log)
wm.touch(d2, m.x + 1, m.y + 2)
check(logged("m:mouse_click 2 2 2") and logged("m:mouse_up 2 2 2") and not wm.armed, "the right-click button turns the next tap into a right-click")
click(a2.x + 1, a2.y + 2)
check(top() == a2 and logged("a:mouse_click 1 2 2"), "the mouse still drives the computer's own screen")

wm.touch(d2, m.x + m.w - 11, m.y)
wm.step()
px, py = onMon("To screen")
wm.touch(d2, px, py)
wm.step()
check(m.display == wm.displays()[1] and onScreen("mmm") ~= nil and onMon("mmm") == nil, "the window menu sends a window to another display")
wm.moveTo(m, d2)
wm.removeDisplay(d2)
wm.step()
check(m.display == wm.displays()[1] and #wm.displays() == 1, "unplugging a display brings its windows back")

print(`kernel: {passed} checks passed`)
