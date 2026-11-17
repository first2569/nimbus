-- Desktop: wallpaper and the icons for everything in <home>/Desktop.
local wm = require("kernel.wm")
local apps = require("lib.apps")
local c = require("lib.theme").c

local desktop = {}
local icons, selected, lastClick, listed = {}, nil, 0, -1
local walls = {} -- rendered wallpaper, one per display and picture

local function scan()
  listed = os.clock()
  icons = {}
  local dir = nimbus.home and nimbus.home .. "/Desktop"
  if not (dir and fs.isDir(dir)) then return end
  local H = wm.displays()[1].H -- laid out for the computer screen, so the icons fit every display
  local rows = math.max(1, math.floor((H - 2) / 3)) -- icons are 2 rows tall plus a gap
  for i, name in ipairs(fs.list(dir)) do
    local path, ext = fs.combine(dir, name), name:match("%.(%w+)$")
    local icon = {
      path = path, label = name:gsub("%.lnk$", ""),
      x = 2 + math.floor((i - 1) / rows) * 10, y = 2 + ((i - 1) % rows) * 3,
    }
    if fs.isDir(path) then icon.tag, icon.color = "dir", colors.yellow
    elseif ext == "lnk" then icon.tag, icon.color = " " .. name:sub(1, 1):upper() .. " ", colors.lightBlue
    else icon.tag, icon.color = ((ext or "?") .. "   "):sub(1, 3), colors.white end
    icons[i] = icon
  end
end

desktop.refresh = scan

function desktop.draw()
  local W, H = wm.size()
  local path = nimbus.prefs.wallpaper
  local key = path and wm.display().name .. path .. W .. H .. c.desk
  local wall = key and walls[key]
  if key and wall == nil then -- render the image once into its own buffer, not every frame
    walls[key] = false -- false: tried, no usable picture
    local image = fs.exists(path) and paintutils.loadImage(path)
    if image then
      wall = window.create(wm.root(), 1, 1, W, H - 1, false)
      walls[key] = wall
      wall.setBackgroundColor(c.desk)
      wall.clear()
      local old = term.redirect(wall)
      paintutils.drawImage(image, 1, 1)
      term.redirect(old)
    end
  end
  if wall then
    wall.setVisible(true)
    wall.setVisible(false)
  end

  if os.clock() - listed > 1 then scan() end -- picks up files other programs create
  for _, icon in ipairs(icons) do
    local label = icon.label:sub(1, 9)
    wm.text(icon.x + 3, icon.y, icon.tag, icon.color, colors.black)
    local picked = icon.path == selected
    wm.text(icon.x + math.floor((9 - #label) / 2), icon.y + 1, label,
      picked and c.card or c.desk, picked and c.cardText or colors.white)
  end
end

function desktop.click(button, x, y)
  local hit
  for _, icon in ipairs(icons) do
    if x >= icon.x and x < icon.x + 9 and y >= icon.y and y <= icon.y + 1 then hit = icon end
  end
  local double = hit and button == 1 and hit.path == selected and os.clock() - lastClick < 0.5
  selected, lastClick = hit and hit.path, double and 0 or os.clock()
  wm.redraw()
  if double then
    apps.open(hit.path)
  elseif button == 2 and hit then
    wm.popup(x, y, {
      { "Open", function() apps.open(hit.path) end },
      { "Delete", function()
        wm.popup(x, y, {
          { "Keep " .. hit.label, function() end },
          { "Delete " .. hit.label, function() pcall(fs.delete, hit.path) scan() end },
        })
      end },
    })
  elseif button == 2 then
    wm.popup(x, y, {
      { "Open in Files", function() apps.open(nimbus.home .. "/Desktop") end },
      { "Terminal", function() apps.launch("terminal") end },
      { "Refresh", scan },
    })
  end
end

return desktop
