-- Taskbar: Start, pinned apps (merged with their windows), other windows, then the tray.
local wm = require("kernel.wm")
local apps = require("lib.apps")
local notify = require("shell.notify")
local start = require("shell.start")
local c = require("lib.theme").c

local taskbar = {}
local hits, trayX = {}, 0

local function topOf(app) -- the app's highest window, if it has one
  for i = #wm.wins, 1, -1 do
    if wm.wins[i].app == app.id then return wm.wins[i] end
  end
end

function taskbar.draw(top)
  local W, H = wm.size()
  local segs = { { text = " \4 " } } -- Start
  for _, app in ipairs(apps.list) do
    if app.pinned then
      segs[#segs + 1] = { text = " " .. app.name:sub(1, 8) .. " ", app = app, win = topOf(app) }
    end
  end
  local loose = {} -- windows that don't belong to a pinned app
  for _, win in ipairs(wm.wins) do
    local app = apps.byId[win.app]
    if not (app and app.pinned) then loose[#loose + 1] = win end
  end
  table.sort(loose, function(a, b) return a.id < b.id end)

  local tray = (nimbus.net.online and "\18 " or "") -- a modem is attached
    .. (notify.unread > 0 and "\7" .. notify.unread .. " " or "") .. textutils.formatTime(os.time(), true) .. " "
  trayX = W - #tray + 1
  wm.text(trayX, H, tray, c.bar, c.barText)

  local total = 0
  for _, seg in ipairs(segs) do total = total + #seg.text end
  -- window titles shrink (8 characters down to 1) until everything fits left of the tray
  local len = math.max(1, math.min(8, math.floor((trayX - 1 - total) / math.max(1, #loose)) - 2))
  for _, win in ipairs(loose) do
    local seg = { text = " " .. win.title:sub(1, len) .. " ", win = win }
    segs[#segs + 1] = seg
    total = total + #seg.text
  end
  local left = 1
  if wm.touchMode then -- a monitor is in use: taps can't right-click, so this makes the next one a right-click
    wm.text(1, H, " \7\7\7 ", wm.armed and c.card or c.bar, wm.armed and c.cardText or c.barText)
    left = 6
  end
  local x = math.max(left, math.min(math.floor((W - total) / 2) + 1, trayX - total))
  hits = {}
  for _, seg in ipairs(segs) do
    -- shortcut: past about a dozen windows the last ones are dropped; add an overflow menu if that bites
    if x + #seg.text > trayX then break end
    local bg, fg = c.bar, c.barDim -- pinned, not running
    if not seg.app and not seg.win then fg = c.barText
    elseif seg.win and seg.win == top then bg, fg = c.card, c.cardText
    elseif seg.win then fg = c.barText end
    wm.text(x, H, seg.text, bg, fg)
    seg.x1, seg.x2 = x, x + #seg.text - 1
    hits[#hits + 1] = seg
    x = x + #seg.text
  end
end

-- Left click focuses, minimizes or launches; right click on a pinned app opens another window.
function taskbar.click(button, x)
  if x >= trayX then return notify.center() end
  if wm.touchMode and x <= 5 then
    wm.armed = true
    return wm.redraw()
  end
  for _, seg in ipairs(hits) do
    if x >= seg.x1 and x <= seg.x2 then
      if seg.app and (button == 2 or not seg.win) then apps.launch(seg.app)
      elseif not seg.win then start.open()
      elseif seg.win == wm.focused() then wm.minimize(seg.win)
      else wm.focus(seg.win) end
      return
    end
  end
end

wm.taskbar = taskbar
return taskbar
