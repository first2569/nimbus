-- Monitors. Advanced monitors become extra desktops ("extend"), copies of the computer's
-- screen ("duplicate", the default) or stay unused ("off"); see Settings > Display.
-- A monitor only reports taps, so taps are turned into clicks. Dragging is replaced by the
-- window menu, right-click by the taskbar's right-click button, and the wheel by list arrows.
local wm = require("kernel.wm")

local display = {}
local mirrors = {} -- duplicate mode: monitor name -> monitor

function display.mode() return settings.get("nimbus.display", "duplicate") end

local function find(name)
  for _, d in ipairs(wm.displays()) do
    if d.name == name then return d end
  end
end

local function touchMode()
  wm.touchMode = #wm.displays() > 1 or next(mirrors) ~= nil -- shows the taskbar's right-click button
  wm.redraw()
end

local function add(name)
  if peripheral.getType(name) ~= "monitor" or display.mode() == "off" or find(name) or mirrors[name] then return end
  local mon = peripheral.wrap(name)
  if not mon.isColor() then return end -- only advanced monitors report taps
  for scale = 5, 0.5, -0.5 do -- the largest text that still leaves room for a 51x19 desktop
    mon.setTextScale(scale)
    local w, h = mon.getSize()
    if w >= 51 and h >= 19 then break end
  end
  mon.setBackgroundColor(colors.black)
  mon.clear()
  if display.mode() == "extend" then wm.addDisplay(name, mon) else mirrors[name] = mon end
  touchMode()
end

local function remove(name)
  local d = find(name)
  if d and d ~= wm.displays()[1] then wm.removeDisplay(d) end
  mirrors[name] = nil
  touchMode()
end

-- Drops every monitor and picks them up again; call after changing the mode.
function display.refresh()
  for name in pairs(mirrors) do remove(name) end
  for i = #wm.displays(), 2, -1 do remove(wm.displays()[i].name) end
  for _, name in ipairs(peripheral.getNames()) do add(name) end
end

function display.setMode(mode)
  settings.set("nimbus.display", mode)
  local saved = settings.save() -- false for standard users: the choice then lasts until restart
  display.refresh()
  return saved
end

-- Names and sizes for the Settings page.
function display.list()
  local out = {}
  for _, d in ipairs(wm.displays()) do out[#out + 1] = { name = d.name, w = d.W, h = d.H } end
  for name, mon in pairs(mirrors) do
    local w, h = mon.getSize()
    out[#out + 1] = { name = name .. " (copy)", w = w, h = h }
  end
  return out
end

wm.on(function(e, name, x, y)
  if e == "monitor_touch" then
    local d = mirrors[name] and wm.displays()[1] or find(name)
    if d then wm.touch(d, x, y) end
    return true
  elseif e == "monitor_resize" then
    local d = find(name)
    if d then wm.resized(d) end
  elseif e == "peripheral" then
    add(name)
  elseif e == "peripheral_detach" then
    remove(name)
  end
end)

-- Duplicate mode: after the computer's screen is drawn, copy it onto each mirror.
wm.afterFrame(function(d)
  if d ~= wm.displays()[1] then return end
  for name, mon in pairs(mirrors) do
    local ok = pcall(function()
      for y = 1, d.H do
        mon.setCursorPos(1, y)
        mon.blit(d.root.getLine(y))
      end
    end)
    if not ok then mirrors[name] = nil end -- unplugged mid-frame
  end
end)

return display
