-- Peripherals: what is attached, what it can do, and a quick action for common devices.
local ui, c = nimbus.ui, nimbus.theme
local LEFT = 19 -- width of the device column

-- type -> { button label, fn(device, name) returning a status line }
local ACTIONS = {
  speaker = { "Beep", function(p) p.playNote("harp", 1, 12) return "Played a note" end },
  drive = { "Eject", function(p)
    if not p.isDiskPresent() then return "No disk in the drive" end
    p.ejectDisk()
    return "Ejected"
  end },
  printer = { "Levels", function(p) return ("Ink %d, paper %d"):format(p.getInkLevel(), p.getPaperLevel()) end },
  monitor = { "Identify", function(p, name)
    p.clear()
    p.setCursorPos(1, 1)
    p.write(name)
    return "Wrote its name on it"
  end },
}

local devices, methods = ui.list(1, 2, LEFT), ui.list(LEFT + 1, 2)
local status = ""

local function load()
  devices.items = {}
  for i, name in ipairs(peripheral.getNames()) do
    devices.items[i] = { name = name, type = peripheral.getType(name) }
  end
end

load()
while true do
  local w, h = term.getSize()
  devices.draw(h - 1, function(d) return (" %-9s%s"):format(d.name:sub(1, 8), d.type) end)
  local dev = devices.items[devices.sel]
  local action = dev and ACTIONS[dev.type]
  methods.items = dev and peripheral.getMethods(dev.name) or {}
  methods.draw(h - 1, function(m) return " " .. m end)
  ui.row(1, dev and " " .. dev.name .. ": " .. dev.type or " Nothing attached", c.bar, c.barText)
  local bx = action and w - #action[1] - 2
  if action then
    term.setCursorPos(bx, 1)
    term.setBackgroundColor(c.card)
    term.setTextColor(c.cardText)
    term.write(" " .. action[1] .. " ")
  end
  ui.row(h, " " .. status, c.card, c.cardText)

  local e, a, x, y = os.pullEvent()
  if e == "peripheral" or e == "peripheral_detach" then
    load()
  elseif e == "mouse_click" and y == 1 and action and x >= bx then
    local ok, result = pcall(action[2], peripheral.wrap(dev.name), dev.name)
    status = ok and result or tostring(result)
  elseif not devices.event(e, a, x, y) and e ~= "key" then
    methods.event(e, a, x, y) -- keys drive the device list only
  end
end
