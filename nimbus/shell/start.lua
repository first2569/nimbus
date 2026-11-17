-- Start menu: search box, app grid, then the session and power buttons.
-- Typing filters the grid; the mouse wheel or the arrows at its right edge scroll it.
local wm = require("kernel.wm")
local apps = require("lib.apps")
local session = require("shell.session")
local c = require("lib.theme").c

local start = {}
local COLS = 3

function start.open()
  local W, H = wm.size()
  local w, h = math.min(W, 44), math.min(H - 1, 13)
  local x, y = math.floor((W - w) / 2) + 1, H - h
  local col, rows = math.floor((w - 2) / COLS), h - 8
  local query, shown, off = "", {}, 0 -- off: grid rows scrolled past
  local buttons = { -- keyed by panel row
    [h - 4] = {
      { nimbus.user.name:sub(1, 8), function() apps.launch("settings") end },
      { "Lock", session.lock }, { "Sign out", session.signOut },
    },
    [h - 2] = { { "Restart", function() os.reboot() end }, { "Shut down", function() os.shutdown() end } },
  }
  local function more() return #shown > (off + rows) * COLS end

  wm.overlay({
    draw = function()
      for row = 0, h - 1 do wm.text(x, y + row, (" "):rep(w), c.bar, c.barText) end
      wm.text(x + 1, y + 1, (" Search: " .. query .. "_" .. (" "):rep(w)):sub(1, w - 2), c.card, c.cardText)
      shown = {}
      for _, app in ipairs(apps.list) do
        if app.name:lower():find(query:lower(), 1, true) then shown[#shown + 1] = app end
      end
      off = math.max(0, math.min(off, math.ceil(#shown / COLS) - rows))
      for i = off * COLS + 1, math.min(#shown, (off + rows) * COLS) do
        local n = i - off * COLS - 1
        local first = i == 1 and query ~= "" -- highlighted: Enter opens this one
        wm.text(x + 1 + (n % COLS) * col, y + 3 + math.floor(n / COLS), (" " .. shown[i].name .. (" "):rep(col)):sub(1, col),
          first and c.desk or c.bar, first and colors.white or c.barText)
      end
      -- scroll arrows, on the blank rows above and below the grid
      if off > 0 then wm.text(x + w - 4, y + 2, " \30 ", c.card, c.cardText) end
      if more() then wm.text(x + w - 4, y + 3 + rows, " \31 ", c.card, c.cardText) end
      for row, list in pairs(buttons) do
        local px = x + 1
        for _, b in ipairs(list) do
          wm.text(px, y + row, " " .. b[1] .. " ", c.card, c.cardText)
          px = px + #b[1] + 3
        end
      end
    end,
    click = function(_, cx, cy)
      if cx < x or cx >= x + w or cy < y or cy >= y + h then return false end
      local row, pos = cy - y, cx - x - 1
      if pos >= w - 5 and (row == 2 or row == 3 + rows) then
        if row == 2 then off = off - 1 elseif more() then off = off + 1 end
        return true
      end
      if buttons[row] then
        local px = 0
        for _, b in ipairs(buttons[row]) do
          if pos >= px and pos < px + #b[1] + 2 then
            b[2]()
            return false -- wm keeps a new overlay (the lock screen) if the button opened one
          end
          px = px + #b[1] + 3
        end
        return true
      end
      local app = row >= 3 and row < 3 + rows and pos >= 0 and pos < col * COLS
        and shown[(off + row - 3) * COLS + math.floor(pos / col) + 1]
      if app then
        apps.launch(app)
        return false
      end
      return true
    end,
    scroll = function(dir) off = off + dir end,
    key = function(e, a)
      if e == "char" then
        query, off = query .. a, 0
      elseif e == "key" and a == keys.backspace then
        query, off = query:sub(1, -2), 0
      elseif e == "key" and a == keys.enter then
        if shown[1] then apps.launch(shown[1]) end
        return false
      end
      return true
    end,
  })
end

return start
