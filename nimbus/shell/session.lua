-- Sessions: first-boot setup, sign-in, lock and sign-out screens, and per-user preferences.
local wm = require("kernel.wm")
local users = require("lib.users")
local theme = require("lib.theme")
local notify = require("shell.notify")

local c = theme.c
local session = {}

-- A full-screen form that takes the keyboard and can't be clicked away.
-- tiles: optional list of names to pick from; fields: { { label, secret }, ... }.
-- submit(values, tile) returns an error message to stay open, or nothing when done.
local function form(title, tiles, fields, submit)
  local values, active, tile, msg = {}, 1, 1, ""
  for i = 1, #fields do values[i] = "" end
  local top, tileHits = 1, {}

  wm.overlay({
    modal = true,
    draw = function()
      local W, H = wm.size()
      for y = 1, H do wm.text(1, y, (" "):rep(W), c.desk, colors.white) end
      top = math.max(1, math.floor(H / 2) - 4)
      wm.text(math.max(1, math.floor((W - #title) / 2) + 1), top, title, c.desk, colors.white)
      tileHits = {}
      if tiles then
        local total = 0
        for _, name in ipairs(tiles) do total = total + #name + 3 end
        local x = math.max(1, math.floor((W - total) / 2) + 2)
        for i, name in ipairs(tiles) do
          wm.text(x, top + 2, " " .. name .. " ", i == tile and c.card or c.bar, i == tile and c.cardText or c.barText)
          tileHits[i] = { x, x + #name + 1 }
          x = x + #name + 3
        end
      end
      local x = math.max(1, math.floor((W - 28) / 2) + 1)
      for i, field in ipairs(fields) do
        local shown = field[2] and ("*"):rep(#values[i]) or values[i]
        if i == active then shown = shown .. "_" end
        wm.text(x, top + 3 + i, ("%9s "):format(field[1]), c.desk, colors.white)
        wm.text(x + 10, top + 3 + i, (" " .. shown:sub(-16) .. (" "):rep(18)):sub(1, 18), c.card, c.cardText)
      end
      wm.text(math.max(1, math.floor((W - #msg) / 2) + 1), top + 5 + #fields, msg, c.desk, colors.yellow)
      wm.text(W - 20, H, " Restart ", c.bar, c.barText)
      wm.text(W - 10, H, " Shut down ", c.bar, c.barText)
    end,
    click = function(_, x, y)
      local W, H = wm.size()
      for i, hit in ipairs(tileHits) do
        if y == top + 2 and x >= hit[1] and x <= hit[2] then tile = i end
      end
      if fields[y - top - 3] then active = y - top - 3 end
      if y == H and x >= W - 20 and x <= W - 12 then os.reboot() end
      if y == H and x >= W - 10 then os.shutdown() end
      return true
    end,
    key = function(e, a)
      if e == "char" or e == "paste" then
        values[active] = values[active] .. a
      elseif e == "key" and a == keys.backspace then
        values[active] = values[active]:sub(1, -2)
      elseif e == "key" and a == keys.tab and tiles then
        tile = tile % #tiles + 1
      elseif e == "key" and a == keys.enter then
        if active < #fields then
          active = active + 1
          return true
        end
        msg = submit(values, tiles and tiles[tile])
        if not msg then return false end
        for i, field in ipairs(fields) do
          if field[2] then values[i] = "" end -- retype secrets after an error
        end
        active = 1
      end
      return true
    end,
  })
end

function session.setPref(key, value)
  nimbus.prefs[key] = value
  local f = fs.open(nimbus.home .. "/.prefs", "w")
  f.write(textutils.serialize(nimbus.prefs))
  f.close()
  theme.apply(nimbus.prefs.theme, nimbus.prefs.accent)
  wm.redraw()
end

-- Runs after users.login succeeded: loads the user's desktop.
local function start()
  local user = users.current()
  nimbus.user, nimbus.home = user, "/home/" .. user.name
  local f = fs.open(nimbus.home .. "/.prefs", "r")
  nimbus.prefs = f and textutils.unserialize(f.readAll()) or {}
  if f then f.close() end
  theme.apply(nimbus.prefs.theme, nimbus.prefs.accent)

  local desk = nimbus.home .. "/Desktop"
  if not fs.exists(desk) then -- first sign-in
    fs.makeDir(desk)
    for name, id in pairs({ Files = "explorer", Terminal = "terminal" }) do
      local link = fs.open(desk .. "/" .. name .. ".lnk", "w")
      link.write(id)
      link.close()
    end
    notify.push("Welcome, " .. user.name, "Ctrl+Tab switches windows")
  end
  if wm.desktop then wm.desktop.refresh() end -- show this user's icons at once
end

function session.signIn()
  local names = {}
  for i, u in ipairs(users.list()) do names[i] = u.name end
  form("Sign in to Nimbus", names, { { "Password", true } }, function(values, name)
    if not users.login(name, values[1]) then return "Wrong password" end
    start()
  end)
end

-- Programs keep running behind the lock screen.
function session.lock()
  form("Locked", { nimbus.user.name }, { { "Password", true } }, function(values, name)
    if not users.check(name, values[1]) then return "Wrong password" end
  end)
end

function session.signOut()
  for _, win in ipairs(wm.wins) do wm.close(win) end
  users.logout()
  nimbus.user, nimbus.home, nimbus.prefs = nil, nil, {}
  theme.apply()
  session.signIn()
end

-- First boot: the first account is the admin.
function session.setup()
  local fields = { { "Name" }, { "Password", true }, { "Again", true } }
  form("Welcome to Nimbus - create your account", nil, fields, function(v)
    if v[2] ~= v[3] then return "Passwords don't match" end
    local ok, err = users.add(v[1], v[2], true)
    if not ok then return err end
    settings.set("shell.allow_disk_startup", false) -- a boot disk would otherwise skip the login
    settings.save()
    users.login(v[1], v[2])
    start()
  end)
end

return session
