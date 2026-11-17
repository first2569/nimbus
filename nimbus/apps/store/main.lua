-- Store: installs extra apps into /nimbus/apps from a catalog.
-- The catalog is a URL or a local folder holding catalog.json and apps/<id>/<file>:
--   set nimbus.store <url-or-folder>     (default: the store folder of nimbus.repo)
-- Installing needs an admin: the file guard refuses standard users.
local ui, c = nimbus.ui, nimbus.theme
local BUTTONS = { "Install", "Uninstall", "Refresh" }
local APPS = "/nimbus/apps"

local list = ui.list(1, 2)
local status = ""

local function fetch(path)
  local repo = settings.get("nimbus.repo")
  return nimbus.fetch(settings.get("nimbus.store") or (repo and repo .. "/store"), path)
end

local function refresh()
  list.items = {}
  local body, err = fetch("catalog.json")
  local catalog = body and textutils.unserializeJSON(body)
  if not catalog or type(catalog.apps) ~= "table" then
    status = err or "The catalog is not valid"
    return
  end
  for _, app in ipairs(catalog.apps) do
    -- the catalog is untrusted and its names become paths: accept nothing that could leave /nimbus/apps/<id>
    local ok = type(app.id) == "string" and app.id:match("^[%w_%-]+$") and type(app.name) == "string"
      and type(app.files) == "table" and type(app.main) == "string"
    for _, file in ipairs(ok and { app.main, table.unpack(app.files) } or {}) do
      if type(file) ~= "string" or not file:match("^[%w_%-][%w_%-%.]*$") then ok = false end
    end
    if ok then list.items[#list.items + 1] = app end
  end
  status = #list.items .. " apps in the catalog"
end

local function install(app)
  local current = nimbus.apps.byId[app.id]
  if current and not current.store then status = app.name .. " is built in" return end
  local files, size = {}, 0
  for _, name in ipairs(app.files) do -- download everything first, so a failure installs nothing
    local body, err = fetch("apps/" .. app.id .. "/" .. name)
    if not body then status = err return end
    files[name], size = body, size + #body
  end
  local free = fs.getFreeSpace(APPS)
  if type(free) == "number" and size + 200 > free then
    status = "Not enough space: needs " .. size .. " bytes"
    return
  end

  local dir = fs.combine(APPS, app.id)
  local ok, err = pcall(function()
    fs.delete(dir) -- replace the old version
    -- app.json is written here, not downloaded, so a catalog can't choose what command it runs
    files["app.json"] = textutils.serializeJSON({
      name = app.name, run = "/" .. fs.combine(dir, app.main), version = tostring(app.version), store = true,
    })
    for name, body in pairs(files) do
      local f, why = fs.open(fs.combine(dir, name), "w")
      if not f then error(why, 0) end
      f.write(body)
      f.close()
    end
  end)
  nimbus.apps.scan()
  status = ok and "Installed " .. app.name or "Install failed: " .. tostring(err)
  if ok then nimbus.notify("Store", app.name .. " is installed") end
end

local function uninstall(app)
  local current = nimbus.apps.byId[app.id]
  if not (current and current.store) then status = app.name .. " is not installed" return end
  local ok, err = pcall(fs.delete, fs.combine(APPS, app.id))
  nimbus.apps.scan()
  status = ok and "Removed " .. app.name or tostring(err)
end

refresh()
while true do
  local _, h = term.getSize()
  local buttons = ui.buttons(1, BUTTONS, c.card, c.cardText)
  list.draw(h - 2, function(app)
    local current = nimbus.apps.byId[app.id]
    local state = not current and "" or current.version == tostring(app.version) and "installed" or "update"
    return (" %-16s %-6s %s"):format(app.name:sub(1, 16), tostring(app.version or ""), state)
  end)
  local picked = list.items[list.sel]
  ui.row(h - 1, " " .. (picked and tostring(picked.description or "") or ""), c.bar, c.barText)
  ui.row(h, " " .. status, c.card, c.cardText)

  local e, a, x, y = os.pullEvent()
  if e == "mouse_click" and y == 1 then
    local i = ui.hit(buttons, x)
    if i == 3 then refresh()
    elseif picked and i == 1 then install(picked)
    elseif picked and i == 2 then uninstall(picked) end
  else
    list.event(e, a, x, y)
  end
end
