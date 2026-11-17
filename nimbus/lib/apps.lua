-- App registry: every folder in /nimbus/apps with an app.json { name, run, pinned, w, h }.
local wm = require("kernel.wm")

local apps = { list = {}, byId = {} }
local DIR = "/nimbus/apps"

function apps.scan()
  apps.list, apps.byId = {}, {}
  for _, id in ipairs(fs.list(DIR)) do
    local f = fs.open(fs.combine(DIR, id .. "/app.json"), "r")
    local app = f and textutils.unserializeJSON(f.readAll())
    if f then f.close() end
    if app and app.name then -- a broken app.json just hides that app
      app.id = id
      apps.list[#apps.list + 1] = app
      apps.byId[id] = app
    end
  end
end

local function quote(path) return '"' .. path .. '"' end -- shell.run splits on spaces

-- Launches an app (or app id) in a new window; extra arguments are passed as paths.
function apps.launch(app, ...)
  app = apps.byId[app] or app
  local cmd = app.run -- no command means a plain Terminal
  if cmd then
    cmd = cmd:gsub("~", nimbus.home) -- "~" in app.json is the user's home
    for _, arg in ipairs({ ... }) do cmd = cmd .. " " .. quote(arg) end
  end
  local win = cmd and wm.run(cmd) or wm.run()
  win.app, win.title = app.id, app.name
  if app.w and app.h then wm.resize(win, app.w, app.h) end -- app.json may ask for a window size
  return win
end

-- Opens a file or folder with whatever handles it.
function apps.open(path)
  path = "/" .. fs.combine(path, "")
  if fs.isDir(path) then return apps.launch("explorer", path) end
  if path:match("%.lnk$") then -- shortcut: an app id or a shell command line
    local f = fs.open(path, "r")
    local target = f.readAll():gsub("%s+$", "")
    f.close()
    if apps.byId[target] then return apps.launch(target) end
    return wm.run(target)
  elseif path:match("%.lua$") then
    return wm.run(quote(path))
  elseif path:match("%.nfp$") then
    return wm.run("paint", quote(path))
  end
  return wm.run("edit", quote(path))
end

apps.scan()
return apps
