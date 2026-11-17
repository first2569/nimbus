-- Files: Nimbus's file explorer. Optional argument: the folder to open.
local ui, c = nimbus.ui, nimbus.theme
local TOOLS = { "Up", "+Dir", "+File", "Rename", "Copy", "Cut", "Paste", "Del" }
local SIDE = 10 -- sidebar width

local dir = fs.combine(... or nimbus.home, "")
local list = ui.list(SIDE + 1, 3)
local status = ""
local toolbar, crumbs

local places = { { "Home", nimbus.home }, { "Desktop", nimbus.home .. "/Desktop" }, { "Shared", "shared" }, { "Root", "" }, { "ROM", "rom" } }
if fs.isDir("disk") then places[#places + 1] = { "Disk", "disk" } end
for _, p in ipairs(places) do p[2] = fs.combine(p[2], "") end

local function load()
  local dirs, files = {}, {}
  for _, name in ipairs(fs.list(dir)) do
    local path = fs.combine(dir, name)
    local item = { name = name, path = path, dir = fs.isDir(path) }
    table.insert(item.dir and dirs or files, item)
  end
  for _, f in ipairs(files) do dirs[#dirs + 1] = f end -- folders first
  list.items = dirs
end

local function go(path)
  dir, list.sel, status = path, 1, ""
  load()
end

local function draw()
  local w, h = term.getSize()
  toolbar = ui.buttons(1, TOOLS, c.card, c.cardText)

  ui.row(2, " /", c.bar, c.barText) -- breadcrumbs: every segment is clickable
  crumbs = { { 2, 2, "" } }
  local x, path = 3, ""
  for seg in dir:gmatch("[^/]+") do
    path = fs.combine(path, seg)
    term.setCursorPos(x, 2)
    term.write(seg .. "/")
    crumbs[#crumbs + 1] = { x, x + #seg, path }
    x = x + #seg + 1
  end

  for row = 3, h - 1 do
    local p = places[row - 2]
    term.setCursorPos(1, row)
    local here = p and p[2] == dir
    term.setBackgroundColor(here and c.desk or c.bar)
    term.setTextColor(here and colors.white or c.barText)
    term.write((" " .. (p and p[1] or "") .. (" "):rep(SIDE)):sub(1, SIDE))
  end

  local nameW = math.max(1, w - SIDE - 9)
  list.draw(h - 1, function(item)
    local size = item.dir and "" or tostring(fs.getSize(item.path))
    return (" %-" .. nameW .. "s%7s"):format((item.name .. (item.dir and "/" or "")):sub(1, nameW), size)
  end)
  ui.row(h, " " .. status, c.card, c.cardText)
end

-- Runs a file operation, shows its error (read-only, name taken...) and reloads.
local function try(fn, ...)
  local ok, err = pcall(fn, ...)
  status = ok and "" or tostring(err)
  load()
  return ok
end

local function act(name, item)
  local _, h = term.getSize()
  if name == "Up" then
    if dir ~= "" then go(fs.getDir(dir)) end
  elseif name == "+Dir" then
    local n = ui.prompt(h, " New folder: ")
    if n then try(fs.makeDir, fs.combine(dir, n)) end
  elseif name == "+File" then
    local n = ui.prompt(h, " New file: ")
    if n then
      try(function()
        local path = fs.combine(dir, n)
        if fs.exists(path) then error("File exists", 0) end
        local f, err = fs.open(path, "w")
        if not f then error(err, 0) end
        f.close()
      end)
    end
  elseif name == "Paste" then
    local clip = nimbus.clipboard
    if not clip then status = "Nothing to paste" return end
    if try(clip.cut and fs.move or fs.copy, clip.path, fs.combine(dir, fs.getName(clip.path))) and clip.cut then
      nimbus.clipboard = nil
    end
  elseif not item then
    status = "Select something first"
  elseif name == "Open" then
    if item.dir then go(item.path) else nimbus.open(item.path) end
  elseif name == "Rename" then
    local n = ui.prompt(h, " Rename to: ", item.name)
    if n then try(fs.move, item.path, fs.combine(dir, n)) end
  elseif name == "Copy" or name == "Cut" then
    nimbus.clipboard = { path = item.path, cut = name == "Cut" } -- shared by every Files window
    status = name .. ": " .. item.name
  elseif name == "Del" then
    if ui.prompt(h, " Delete " .. item.name .. "? (y/n) ") == "y" then try(fs.delete, item.path) end
  elseif name == "Wallpaper" then
    nimbus.setPref("wallpaper", "/" .. item.path)
  end
end

load()
while true do
  draw()
  local e, a, x, y = os.pullEvent()
  local action, item = list.event(e, a, x, y)
  if action == "open" then
    act("Open", item)
  elseif action == "menu" then
    local labels = item and { "Open", "Rename", "Copy", "Cut", "Del" } or { "Paste", "+Dir", "+File" }
    if item and item.name:match("%.nfp$") then labels[#labels + 1] = "Wallpaper" end
    local i = ui.menu(labels)
    if i then act(labels[i], item) end
  elseif e == "mouse_click" and y == 1 then
    local i = ui.hit(toolbar, x)
    if i then act(TOOLS[i], list.items[list.sel]) end
  elseif e == "mouse_click" and y == 2 then
    local i = ui.hit(crumbs, x)
    if i then go(crumbs[i][3]) end
  elseif e == "mouse_click" and x <= SIDE and places[y - 2] then
    go(places[y - 2][2])
  elseif e == "key" and a == keys.backspace then
    act("Up")
  elseif e == "key" and a == keys.delete then
    act("Del", list.items[list.sel])
  elseif e == "key" and a == keys.f5 then
    load()
  end
end
