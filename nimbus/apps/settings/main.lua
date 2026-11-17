-- Settings: personalization, accounts and system information.
local ui, c, users = nimbus.ui, nimbus.theme, nimbus.users
local PAGES = { "Personalize", "Accounts", "System", "Display", "Network", "Update" }
local SIDE = 12 -- sidebar width

local page, status = 1, ""
local picked = nimbus.user.name -- the account the Accounts buttons act on
local hits = {} -- { x1, x2, y, fn }, rebuilt on every draw
local found, staged -- what the last update check found; whether a download is waiting for a restart

local function text(x, y, s, bg, fg)
  term.setCursorPos(x, y)
  term.setBackgroundColor(bg or c.view)
  term.setTextColor(fg or c.viewText)
  term.write(s)
end

local function button(x, y, label, fn)
  text(x, y, " " .. label .. " ", c.card, c.cardText)
  hits[#hits + 1] = { x, x + #label + 1, y, fn }
  return x + #label + 3
end

local function ask(label, mask)
  local _, h = term.getSize()
  return ui.prompt(h, " " .. label .. ": ", nil, mask)
end

local function report(ok, err) status = ok and "Done" or err end

local pages = {}

pages[1] = function(x)
  text(x, 2, "Theme")
  local bx = x + 10
  for _, mode in ipairs({ "dark", "light" }) do
    bx = button(bx, 2, mode, function() nimbus.setPref("theme", mode) end)
  end
  text(x, 4, "Accent")
  for i, name in ipairs(nimbus.accents) do
    local sx = x + (i - 1) * 3
    text(sx, 5, "  ", colors[name])
    hits[#hits + 1] = { sx, sx + 1, 5, function() nimbus.setPref("accent", name) end }
  end
  text(x, 7, "Wallpaper")
  text(x, 8, (nimbus.prefs.wallpaper or "none"):sub(-26))
  if nimbus.prefs.wallpaper then button(x, 9, "Clear", function() nimbus.setPref("wallpaper", nil) end) end
  text(x, 11, "To set one, right-click an", c.view, c.cardDim)
  text(x, 12, ".nfp picture in Files.", c.view, c.cardDim)
end

pages[2] = function(x)
  local w = term.getSize()
  local me, y = users.current(), 2
  for _, u in ipairs(users.list()) do
    local line = ("%-12s %-9s%s"):format(u.name, u.admin and "admin" or "standard", u.name == me.name and "(you)" or "")
    text(x, y, (line .. (" "):rep(w)):sub(1, w - x + 1), u.name == picked and c.desk, u.name == picked and colors.white)
    hits[#hits + 1] = { x, w, y, function() picked = u.name end }
    y = y + 1
  end
  local bx = button(x, y + 1, "Password", function()
    local pw = ask("New password for " .. picked, "*")
    if pw then report(users.setPassword(picked, pw)) end
  end)
  if not me.admin then return end
  button(bx, y + 1, "Add user", function()
    local name = ask("New user name")
    local pw = name and ask("Password for " .. name, "*")
    if pw then report(users.add(name, pw, false)) end
  end)
  bx = button(x, y + 3, "Admin on/off", function()
    for _, u in ipairs(users.list()) do
      if u.name == picked then report(users.setAdmin(picked, not u.admin)) end
    end
  end)
  button(bx, y + 3, "Remove", function()
    if ask("Remove " .. picked .. "? (y/n)") == "y" then
      report(users.remove(picked))
      picked = me.name
    end
  end)
end

pages[3] = function(x)
  local free, cap = fs.getFreeSpace("/"), fs.getCapacity and fs.getCapacity("/")
  local storage = type(free) == "number" and math.floor(free / 1024) .. " KB free" or tostring(free)
  if type(cap) == "number" then storage = storage .. " of " .. math.floor(cap / 1024) end
  local rows = {
    { "Name", os.getComputerLabel() or "(none)" }, { "ID", os.getComputerID() }, { "Storage", storage },
    { "Nimbus", nimbus.version }, { "Runtime", os.version() },
  }
  for i, row in ipairs(rows) do text(x, 1 + i, ("%-8s %s"):format(row[1], tostring(row[2])):sub(1, 27)) end
  button(x, 8, "Rename computer", function()
    local name = ask("Computer name")
    if name then os.setComputerLabel(name) end
  end)
end

pages[4] = function(x)
  local mode = nimbus.display.mode()
  text(x, 2, "Monitors")
  local bx = x
  for _, name in ipairs({ "off", "duplicate", "extend" }) do
    bx = button(bx, 3, (name == mode and "*" or "") .. name, function()
      status = nimbus.display.setMode(name) and "Monitors: " .. name or "Set until restart (admins can save it)"
    end)
  end
  for i, d in ipairs(nimbus.display.list()) do
    text(x, 4 + i, ("%-17s %dx%d"):format(d.name:sub(1, 17), d.w, d.h))
  end
  text(x, 10, "On a monitor, tap a title", c.view, c.cardDim)
  text(x, 11, "bar to move or snap a window.", c.view, c.cardDim)
end

pages[5] = function(x)
  local net, modems = nimbus.net, 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then modems = modems + 1 end
  end
  text(x, 2, "Status   " .. (net.online and "online" or "no modem attached"))
  text(x, 3, "Modems   " .. modems)
  text(x, 4, ("Name     " .. net.name() .. " #" .. os.getComputerID()):sub(1, 27))
  text(x, 6, "Chat, File Share and Remote", c.view, c.cardDim)
  text(x, 7, "Desktop are not private:", c.view, c.cardDim)
  text(x, 8, "anyone in range can listen.", c.view, c.cardDim)
end

pages[6] = function(x)
  text(x, 2, "Installed  " .. nimbus.version)
  text(x, 3, "Source     " .. tostring(settings.get("nimbus.repo") or "not set"):sub(-16))
  local bx = button(x, 5, "Check", function()
    local err
    found, err = nimbus.update.check()
    if not found then status = err
    elseif #found.files == 0 then status = "Nimbus is up to date"
    else status = #found.files .. " files to update (version " .. tostring(found.version) .. ")" end
  end)
  if found and #found.files > 0 and not staged then
    button(bx, 5, "Download", function()
      local ok, err = nimbus.update.download(found)
      staged = ok
      status = ok and "Restart to finish updating" or tostring(err)
    end)
  end
  if staged then button(x, 7, "Restart now", function() os.reboot() end) end
end

while true do
  local _, h = term.getSize()
  term.setBackgroundColor(c.view)
  term.clear()
  hits = {}
  for y = 1, h - 1 do
    local name = PAGES[y - 1]
    text(1, y, (" " .. (name or "") .. (" "):rep(SIDE)):sub(1, SIDE), y - 1 == page and c.desk or c.bar, y - 1 == page and colors.white or c.barText)
    if name then hits[#hits + 1] = { 1, SIDE, y, function() page = y - 1 end } end
  end
  pages[page](SIDE + 2)
  ui.row(h, " " .. status, c.card, c.cardText)

  local e, _, x, y = os.pullEvent()
  if e == "mouse_click" then
    for _, hit in ipairs(hits) do
      if y == hit[3] and x >= hit[1] and x <= hit[2] then
        status = ""
        hit[4]()
        break
      end
    end
  end
end
