-- Smoke test: runs startup.lua against stubbed ComputerCraft APIs with scripted input.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local keys = { up = 1, down = 2, enter = 3, backspace = 4 }
local K = function(k) return { "key", keys[k] } end
local events = {
	K "down", K "enter",                 -- main -> Files
	K "down", K "enter", K "enter",      -- hello.lua -> Run
	K "enter",                           -- pause after run
	K "down", K "enter", K "down", K "down", K "enter", -- hello.lua -> Delete
	K "down", K "enter",                 -- confirm Yes
	K "enter",                           -- into rom/
	{ "timer", 0 },                      -- stray timer must be ignored
	K "enter",                           -- ".." back to root
	K "backspace",                       -- back to main
	{ "mouse_scroll", 1, 1, 1 }, { "mouse_scroll", -1, 1, 1 },
	{ "mouse_click", 1, 3, 6 },          -- row 6 = item 5 = Reboot
}
local log = {}
local function rec(name) return function(...) table.insert(log, name .. " " .. table.concat({ ... }, " ")) end end
local noop = function() end
local tree = { [""] = { "rom", "hello.lua" }, rom = { "startup.lua" } }

local env = {
	keys = keys,
	colors = { black = 1, white = 2, blue = 3 },
	term = {
		isColor = function() return true end, getSize = function() return 51, 19 end,
		setBackgroundColor = noop, setTextColor = noop, clear = noop, clearLine = noop,
		setCursorPos = noop, write = function(s) assert(type(s) == "string") end,
	},
	textutils = { formatTime = function() return "12:00" end },
	shell = { run = function(...) rec("run")(...) return true end },
	fs = {
		list = function(d) return assert(tree[d], "bad dir " .. d) end,
		isDir = function(p) return tree[p] ~= nil end,
		combine = function(a, b) b = b:gsub("/$", "") return a == "" and b or a .. "/" .. b end,
		getDir = function(p) return p:match("^(.*)/[^/]*$") or "" end,
		delete = rec("delete"),
	},
	print = noop, write = noop, read = function() return "" end,
	os = {
		startTimer = function() return 99 end, time = function() return 0 end,
		getComputerID = function() return 7 end, shutdown = rec("shutdown"),
		reboot = function() table.insert(log, "reboot") error("END") end,
		pullEvent = function(filter)
			while true do
				local e = assert(table.remove(events, 1), "script ran out of events")
				if not filter or e[1] == filter then return table.unpack(e) end
			end
		end,
	},
}

local ok, err = pcall(luau.load(fs.readFile(process.args[1]), { environment = env }))
assert(not ok and tostring(err):find("END"), "unexpected exit: " .. tostring(err))
local want = { 'run "/hello.lua"', "delete hello.lua", "reboot" }
assert(table.concat(log, "|") == table.concat(want, "|"), "got: " .. table.concat(log, "|"))
assert(#events == 0, "unconsumed events: " .. #events)
print("OK", table.concat(log, " | "))
