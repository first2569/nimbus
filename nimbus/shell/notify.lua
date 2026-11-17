-- Notifications: a toast above the taskbar, and a notification center behind the tray.
local wm = require("kernel.wm")
local c = require("lib.theme").c

local notify = { list = {}, unread = 0 }
local toast, toastTimer

function notify.push(title, text)
  toast = { title = title, text = text or "" }
  table.insert(notify.list, 1, toast)
  notify.list[21] = nil -- keep the last 20
  notify.unread = notify.unread + 1
  toastTimer = os.startTimer(4)
  wm.redraw()
end

wm.on(function(e, id)
  if e == "timer" and id == toastTimer then
    toast = nil
    wm.redraw()
    return true
  end
end)

local function card(x, y, w, n)
  wm.text(x, y, (" " .. n.title .. (" "):rep(w)):sub(1, w), c.card, c.cardText)
  wm.text(x, y + 1, (" " .. n.text .. (" "):rep(w)):sub(1, w), c.card, c.cardDim)
end

wm.toast = function()
  local W, H = wm.size()
  if toast then card(W - 27, H - 3, 27, toast) end
end

function notify.center()
  notify.unread, toast = 0, nil
  local W, H = wm.size()
  local w = math.min(W, 29)
  local x = W - w + 1
  wm.overlay({
    draw = function()
      for y = 1, H - 1 do wm.text(x, y, (" "):rep(w), c.bar, c.barText) end
      wm.text(x, 1, " Notifications", c.bar, c.barText)
      wm.text(W - 6, 1, " Clear ", c.card, c.cardText)
      for i, n in ipairs(notify.list) do
        if i * 3 + 1 < H then card(x + 1, i * 3, w - 2, n) end
      end
    end,
    click = function(_, cx, cy)
      if cx < x or cy >= H then return false end
      if cy == 1 and cx >= W - 6 then notify.list = {} end
      return true
    end,
  })
end

return notify
