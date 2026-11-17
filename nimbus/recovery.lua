-- Nimbus safe mode: a plain full-screen menu that needs no window manager.
-- Hold Ctrl+T to drop to the plain CraftOS shell.
local NAME = "Nimbus safe mode"
local hiBg = term.isColor() and colors.blue or colors.white
local hiFg = term.isColor() and colors.white or colors.black

local function paint(bg, fg)
  term.setBackgroundColor(bg)
  term.setTextColor(fg)
end

local function clear()
  paint(colors.black, colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function pause()
  print("\n[press any key]")
  os.pullEvent("key")
end

-- Full-screen list. Returns the chosen index, or nil on Backspace.
local function menu(title, items)
  local sel, top = 1, 1
  local timer = os.startTimer(1) -- redraw every second so the clock ticks
  while true do
    local w, h = term.getSize()
    local rows = h - 2
    if sel < top then top = sel elseif sel >= top + rows then top = sel - rows + 1 end

    clear()
    paint(hiBg, hiFg)
    term.clearLine()
    term.write(" " .. title)
    local clock = textutils.formatTime(os.time(), true)
    term.setCursorPos(w - #clock, 1)
    term.write(clock)
    for i = top, math.min(#items, top + rows - 1) do
      term.setCursorPos(1, i - top + 2)
      if i == sel then paint(hiBg, hiFg) else paint(colors.black, colors.white) end
      term.clearLine()
      term.write(" " .. items[i])
    end
    paint(colors.black, colors.white)
    term.setCursorPos(1, h)
    term.write(" Up/Down  Enter=open  Backspace=back")

    local e, a, _, y = os.pullEvent()
    if e == "key" then
      if a == keys.up and sel > 1 then sel = sel - 1
      elseif a == keys.down and sel < #items then sel = sel + 1
      elseif a == keys.enter and items[sel] then return sel
      elseif a == keys.backspace then return nil end
    elseif e == "mouse_click" then
      local i = y - 2 + top
      if y >= 2 and y < h and items[i] then return i end
    elseif e == "mouse_scroll" then
      sel = math.max(1, math.min(#items, sel + a))
    elseif e == "timer" and a == timer then
      timer = os.startTimer(1)
    end
  end
end

local function launch(wait, ...)
  clear()
  local ok = shell.run(...)
  if wait or not ok then pause() end
end

-- shell.run splits on spaces, so paths are passed quoted
local function quoted(path) return '"/' .. path .. '"' end

local function files()
  local dir = ""
  while true do
    local items = {}
    if dir ~= "" then items[1] = ".." end
    for _, n in ipairs(fs.list(dir)) do
      items[#items + 1] = fs.isDir(fs.combine(dir, n)) and n .. "/" or n
    end
    local i = menu("Files: /" .. dir, items)
    if not i then return end
    local name = items[i]
    local path = fs.combine(dir, name)
    if name == ".." then
      dir = fs.getDir(dir)
    elseif name:sub(-1) == "/" then
      dir = path
    else
      local a = menu(name, { "Run", "Edit", "Delete", "Cancel" })
      if a == 1 then
        launch(true, quoted(path))
      elseif a == 2 then
        launch(false, "edit", quoted(path))
      elseif a == 3 and menu("Delete " .. name .. "?", { "No", "Yes" }) == 2 then
        local ok, err = pcall(fs.delete, path) -- /rom is read-only and throws
        if not ok then clear() print(err) pause() end
      end
    end
  end
end

local actions = {
  { "Shell", function()
    clear()
    print("Type 'exit' to return to " .. NAME)
    shell.run("shell")
  end },
  { "Files", files },
  { "New file", function()
    clear()
    write("File name: ")
    local n = read()
    if n ~= "" then launch(false, "edit", quoted(n)) end
  end },
  { "Lua prompt", function() launch(false, "lua") end },
  { "Reboot", os.reboot },
  { "Shut down", os.shutdown },
}

local labels = {}
for i, a in ipairs(actions) do labels[i] = a[1] end
while true do
  local i = menu(NAME .. "  #" .. os.getComputerID(), labels)
  if i then actions[i][2]() end
end
