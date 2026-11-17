-- Nimbus window manager: displays, windows, z-order, input routing and compositing.
-- Routing follows rom/programs/advanced/multishell.lua: keyboard goes to the focused
-- process, mouse to the window under the cursor, everything else to every process.
-- The desktop shell plugs in through wm.desktop, wm.taskbar, wm.toast, wm.afterFrame, wm.on
-- and wm.overlay.
--
-- There can be several displays (the computer's screen, then monitors). Exactly one is "in
-- use" at a time - the one being drawn, or the one the current input came from - and
-- wm.size, wm.text, wm.root and the shell hooks all refer to it. That is why the shell's
-- code never mentions displays.
local sched = require("kernel.sched")
local c = require("lib.theme").c

local wm = { wins = {}, held = {}, mouse = { x = 1, y = 1 } }
-- wins is the z-order across all displays: wins[#wins] is on top; minimized windows sit at the bottom
local displays = {} -- [1] is the computer's own screen
local cur, parent, root, W, H -- the display in use, and its fields
local composed -- the display the shell last laid itself out for (taskbar hits, icon positions)
local dirty, cascade = true, 0
local drag, capture, overlay, pending, touching, clockTimer
local listeners, frameHooks = {}, {}
local handle

local BTN = { "#", "_", "+", "x" } -- window menu, minimize, maximize, close; 3 cells each
local BTN_W = #BTN * 3
local MIN_W, MIN_H = BTN_W + 4, 3
local SNAPS = {
  { "Left half", "left" }, { "Right half", "right" },
  { "Top left", "topleft" }, { "Top right", "topright" },
  { "Bottom left", "bottomleft" }, { "Bottom right", "bottomright" },
}
local INPUT = { key = true, key_up = true, char = true, paste = true, terminate = true }

local function use(d) cur, parent, root, W, H = d, d.parent, d.root, d.W, d.H end

function wm.size() return W, H end
function wm.root() return root end
function wm.display() return cur end
function wm.displays() return displays end
function wm.redraw() dirty = true end
function wm.modal() return overlay ~= nil and overlay.modal == true end

-- fn(event, ...) sees every event before it is routed; returning true swallows it.
function wm.on(fn) listeners[#listeners + 1] = fn end

-- fn(display) runs after each display has been drawn.
function wm.afterFrame(fn) frameHooks[#frameHooks + 1] = fn end

function wm.text(x, y, text, bg, fg)
  root.setCursorPos(x, y)
  root.setBackgroundColor(bg)
  root.setTextColor(fg)
  root.write(text)
end

local function layoutRect(name)
  local h = H - 1 -- the bottom row is the taskbar
  local lw, th = math.floor(W / 2), math.floor(h / 2)
  local r = ({
    max = { 1, 1, W, h },
    left = { 1, 1, lw, h },
    right = { lw + 1, 1, W - lw, h },
    topleft = { 1, 1, lw, th },
    topright = { lw + 1, 1, W - lw, th },
    bottomleft = { 1, th + 1, lw, h - th },
    bottomright = { lw + 1, th + 1, W - lw, h - th },
  })[name]
  return r[1], r[2], r[3], r[4]
end

function wm.focused()
  local top = wm.wins[#wm.wins]
  if top and not top.minimized then return top end
end

local function byId(id)
  for _, win in ipairs(wm.wins) do
    if win.id == id then return win end
  end
end

local function winAt(x, y)
  for i = #wm.wins, 1, -1 do
    local win = wm.wins[i]
    if win.display == cur and not win.minimized
      and x >= win.x and x < win.x + win.w and y >= win.y and y < win.y + win.h then
      return win
    end
  end
end

-- User input for one window, in that window's own coordinates.
local function send(win, event, ...)
  win.proc.interacted = true
  sched.resume(win.proc, event, ...)
end

local function setRect(win, x, y, w, h)
  local resized = w ~= win.w or h ~= win.h
  win.x, win.y, win.w, win.h = x, y, w, h
  win.body.reposition(x, y + 1, w, h - 1, win.display.root)
  if resized then sched.resume(win.proc, "term_resize") end
  dirty = true
end

local function restack(win, toBottom)
  for i, other in ipairs(wm.wins) do
    if other == win then table.remove(wm.wins, i) break end
  end
  win.minimized = toBottom
  table.insert(wm.wins, toBottom and 1 or #wm.wins + 1, win)
  dirty = true
end

function wm.focus(win) restack(win, false) end
function wm.minimize(win) restack(win, true) end

function wm.close(win)
  win.proc.dead = true
  dirty = true
end

function wm.resize(win, w, h) setRect(win, win.x, win.y, w, h) end

-- Snap or maximize by layout name; nil puts the window back where it was.
function wm.setLayout(win, name)
  if name then
    win.restore = win.restore or { win.x, win.y, win.w, win.h }
    win.layout = name
    setRect(win, layoutRect(name))
  elseif win.restore then
    local r = win.restore
    win.layout, win.restore = nil, nil
    setRect(win, r[1], r[2], r[3], r[4])
  end
end

-- Moves a window to another display: it keeps its snap layout, or is fitted inside.
function wm.moveTo(win, d)
  local back = cur
  use(d)
  win.display = d
  if win.layout then
    setRect(win, layoutRect(win.layout))
  else
    setRect(win, math.min(win.x, math.max(1, W - 3)), math.min(win.y, H - 1), math.min(win.w, W), math.min(win.h, H - 1))
  end
  use(back)
end

-- target is anything with the term API: the computer's terminal or a monitor.
function wm.addDisplay(name, target)
  local w, h = target.getSize()
  local d = { name = name, parent = target, W = w, H = h, root = window.create(target, 1, 1, w, h, false) }
  displays[#displays + 1] = d
  dirty = true
  return d
end

-- Its windows move to the computer's own screen. The first display can't be removed.
function wm.removeDisplay(d)
  for i = #displays, 2, -1 do
    if displays[i] == d then table.remove(displays, i) end
  end
  if cur == d then use(displays[1]) end
  if composed == d then composed = nil end
  if overlay and overlay.display == d then overlay = nil end
  for _, win in ipairs(wm.wins) do
    if win.display == d then wm.moveTo(win, displays[1]) end
  end
  dirty = true
end

-- Call when a display's terminal changed size.
function wm.resized(d)
  local back = cur
  d.W, d.H = d.parent.getSize()
  d.root.reposition(1, 1, d.W, d.H)
  use(d)
  for _, win in ipairs(wm.wins) do
    if win.display == d and win.layout then setRect(win, layoutRect(win.layout)) end
  end
  use(back)
  dirty = true
end

-- Shows one thing above everything else, on the display in use, until it is dismissed.
-- o = { draw = fn(), click = fn(button, x, y), key = fn(event, arg), scroll = fn(dir) }; click and key
-- return true to stay open. With a key handler the overlay also takes the keyboard;
-- modal = true (sign-in, lock) covers every display and also blocks shortcuts and Ctrl+T. An overlay
-- with raw = fn(event, ...) gets every keyboard and mouse event itself; false from it closes the overlay.
function wm.overlay(o)
  overlay, drag, capture = o, nil, nil
  if o then o.display = cur end
  dirty = true
end

-- items = { { label, fn }, ... }; the next click picks one or dismisses the popup.
function wm.popup(x, y, items, onDismiss)
  local w = 0
  for _, item in ipairs(items) do w = math.max(w, #item[1] + 2) end
  x = math.max(1, math.min(x, W - w + 1))
  y = math.max(1, math.min(y, H - #items))
  wm.overlay({
    draw = function()
      for i, item in ipairs(items) do
        wm.text(x, y + i - 1, (" " .. item[1] .. (" "):rep(w)):sub(1, w), c.card, c.cardText)
      end
    end,
    click = function(_, cx, cy)
      overlay = nil -- before the callback, which may open another popup
      local item = items[cy - y + 1]
      if item and cx >= x and cx < x + w then item[2]() elseif onDismiss then onDismiss() end
    end,
  })
end

-- For programs: a context menu at the last click. The pick comes back to the caller as a
-- "nimbus_menu" event (the index, or nothing if dismissed), so no program code runs in the kernel.
function wm.menu(labels)
  local proc, items = sched.current, {}
  for i, label in ipairs(labels) do
    items[i] = { label, function() sched.resume(proc, "nimbus_menu", i) end }
  end
  wm.popup(wm.mouse.x, wm.mouse.y, items, function() sched.resume(proc, "nimbus_menu") end)
end

local function setTitle(win, title)
  title = title:gsub("%.lua$", "")
  win.title = title == "shell" and "Terminal" or title
  dirty = true
end

-- The multishell API handed to programs, so the stock shell titles its window and
-- `fg`/`bg` open new windows without knowing Nimbus exists.
local ms = {}
wm.multishell = ms

-- New windows open on the display in use: the one the last click or tap came from.
local function open(focus, env, path, ...)
  local args = table.pack(...)
  local n = cascade % 5
  cascade = cascade + 1
  local win = { display = cur, x = 2 + n * 2, y = 2 + n, w = math.min(51, W - 10), h = math.min(20, H - 6) }
  setTitle(win, fs.getName(path))
  win.body = window.create(root, win.x, win.y + 1, win.w, win.h - 1, false)
  win.proc = sched.spawn(win.title, win.body, function()
    os.run(env, path, table.unpack(args, 1, args.n))
    if not win.proc.interacted then -- as in multishell: don't let unseen output vanish
      print("Press any key to close")
      os.pullEvent("key")
    end
  end)
  win.proc.win = win
  win.id = win.proc.pid
  if focus or not wm.focused() then
    table.insert(wm.wins, win)
  else
    table.insert(wm.wins, #wm.wins, win) -- just under the focused window
  end
  sched.resume(win.proc)
  dirty = true
  return win
end

-- Opens a Terminal, or runs a shell command line in a new window.
function wm.run(...)
  return open(true, { shell = shell, multishell = ms }, "rom/programs/shell.lua", ...)
end

function ms.getCurrent() return sched.current and sched.current.pid end
function ms.getCount() return #wm.wins end
function ms.launch(env, path, ...) return open(false, env, path, ...).id end
function ms.getFocus()
  local win = wm.focused()
  return win and win.id
end
function ms.setFocus(id)
  local win = byId(id)
  if win then wm.focus(win) end
  return win ~= nil
end
function ms.getTitle(id)
  local win = byId(id)
  return win and win.title
end
function ms.setTitle(id, title)
  local win = byId(id)
  if win then setTitle(win, title) end
end

local function compose(d)
  use(d)
  composed = d
  root.setVisible(false) -- compose off-screen, then show the frame in one go
  root.setBackgroundColor(c.desk)
  root.clear()
  if wm.desktop then wm.desktop.draw() end
  local top = wm.focused()
  for _, win in ipairs(wm.wins) do
    if win.display == d and not win.minimized then
      local room = win.w - BTN_W
      local title = (" " .. win.title):sub(1, room)
      wm.text(win.x, win.y, title .. (" "):rep(room - #title),
        win == top and c.bar or c.idle, win == top and c.barText or c.idleText)
      for _, b in ipairs(BTN) do
        if b == "x" then root.setBackgroundColor(colors.red) root.setTextColor(colors.white) end
        root.write(" " .. b .. " ")
      end
      -- bodies stay hidden except for this copy, so background windows can't draw over others
      win.body.setVisible(true)
      win.body.setVisible(false)
      if win == top and not win.layout then -- resize grip
        wm.text(win.x + win.w - 1, win.y + win.h - 1, "\127", c.bar, c.barDim)
      end
    end
  end
  wm.text(1, H, (" "):rep(W), c.bar, c.barText)
  if wm.taskbar then wm.taskbar.draw(top) end
  if wm.toast then wm.toast() end
  if overlay and (overlay.modal or overlay.display == d) then overlay.draw() end
  root.setVisible(true)
  for _, fn in ipairs(frameHooks) do fn(d) end

  local blink = false
  if top and top.display == d and not overlay and top.body.getCursorBlink() then
    local cx, cy = top.body.getCursorPos()
    if cx >= 1 and cx <= top.w and cy >= 1 and cy < top.h and top.y + cy < H then
      root.setTextColor(top.body.getTextColor())
      root.setCursorPos(top.x + cx - 1, top.y + cy)
      blink = true
    end
  end
  root.setCursorBlink(blink)
end

-- A monitor can be unplugged mid-frame; its detach event follows and removes the display.
local function composeSafe(d)
  if d == displays[1] then compose(d) else pcall(compose, d) end
end

local function draw()
  dirty = false
  local back = cur
  for _, d in ipairs(displays) do
    if d ~= back then composeSafe(d) end
  end
  composeSafe(back) -- last, so the shell's layout matches the display in use
  use(back)
end

-- Makes d the display in use and gets the shell to lay itself out for it.
local function enter(d)
  use(d)
  if composed ~= d then
    composeSafe(d)
    use(d)
  end
end

-- The window menu: the "#" button, or a tap on the title bar of a touch display (which can't drag).
local function windowMenu(win, x)
  local items = {
    { "Move (then tap)", function() pending = { win = win, mode = "move" } end },
    { "Resize (then tap)", function() pending = { win = win, mode = "resize" } end },
  }
  for _, snap in ipairs(SNAPS) do
    items[#items + 1] = { snap[1], function() wm.setLayout(win, snap[2]) end }
  end
  for _, d in ipairs(displays) do
    if d ~= win.display then items[#items + 1] = { "To " .. d.name, function() wm.moveTo(win, d) end } end
  end
  wm.popup(x, win.y + 1, items)
end

local function titleClick(win, x)
  local b = math.floor((x - (win.x + win.w - BTN_W)) / 3) + 1
  if b < 1 and not touching then
    drag = { win = win, mode = "move", dx = x - win.x }
  elseif b <= 1 then
    windowMenu(win, x)
  elseif b == 2 then
    wm.minimize(win)
  elseif b == 3 then
    wm.setLayout(win, win.layout ~= "max" and "max" or nil)
  else
    wm.close(win)
  end
end

local function click(button, x, y)
  wm.mouse.x, wm.mouse.y = x, y
  if wm.armed then -- the taskbar's right-click button was used just before
    button, wm.armed, dirty = 2, false, true
  end
  if overlay then
    local o = overlay
    if not (o.modal or o.display == cur) then
      overlay = nil -- a click on another display dismisses it
    elseif not o.click(button, x, y) and overlay == o then
      overlay = nil
    end
    dirty = true
    return
  end
  drag, capture = nil, nil
  if pending then -- second step of "Move" or "Resize" from the window menu
    local win, mode = pending.win, pending.mode
    pending = nil
    if win.display == cur and not win.proc.dead then
      wm.focus(win)
      wm.setLayout(win, nil)
      y = math.max(1, math.min(H - 1, y))
      if mode == "move" then
        setRect(win, math.min(x, W - 3), y, win.w, win.h)
      else
        setRect(win, win.x, win.y, math.max(MIN_W, x - win.x + 1), math.max(MIN_H, y - win.y + 1))
      end
    end
    return
  end
  if y == H then
    if wm.taskbar then wm.taskbar.click(button, x) end
    return
  end
  local win = winAt(x, y)
  if not win then
    if wm.desktop then wm.desktop.click(button, x, y) end
    return
  end
  wm.focus(win)
  if y == win.y then
    titleClick(win, x)
  elseif not win.layout and x == win.x + win.w - 1 and y == win.y + win.h - 1 then
    drag = { win = win, mode = "resize" }
  else
    capture = win
    send(win, "mouse_click", button, x - win.x + 1, y - win.y)
  end
end

local function dragTo(x, y)
  local win = drag.win
  y = math.max(1, math.min(H - 1, y))
  if drag.mode == "resize" then
    setRect(win, win.x, win.y, math.max(MIN_W, x - win.x + 1), math.max(MIN_H, y - win.y + 1))
    return
  end
  if win.layout then -- dragging a snapped window pops it back to its old size under the cursor
    drag.dx = math.min(drag.dx, win.restore[3] - BTN_W - 1)
    wm.setLayout(win, nil)
  end
  drag.moved = true
  setRect(win, math.max(4 - win.w, math.min(W - 3, x - drag.dx)), y, win.w, win.h)
end

function handle(e, ...)
  local a, x, y = ... -- forward `...` itself so programs see the event's real argument count
  local mouse = e:sub(1, 6) == "mouse_"
  if mouse and not touching then enter(displays[1]) end -- a real mouse is always on the computer's own screen
  if e == "key" then
    wm.held[a] = true
    -- Ctrl+Tab cycles windows (Alt+Tab never reaches Minecraft)
    if a == keys.tab and (wm.held[keys.leftCtrl] or wm.held[keys.rightCtrl]) and not wm.modal() then
      if wm.wins[1] then wm.focus(wm.wins[1]) end
      return
    end
  elseif e == "key_up" then
    wm.held[a] = nil
  end
  for _, fn in ipairs(listeners) do
    if fn(e, ...) then return end
  end

  if overlay and overlay.raw and (INPUT[e] or mouse) then
    if overlay.raw(e, ...) == false then overlay = nil end
    dirty = true
    return
  end

  if INPUT[e] then
    if overlay and overlay.key and (e ~= "terminate" or overlay.modal) then
      if not overlay.key(e, ...) then overlay = nil end
      dirty = true
    else
      local win = wm.focused()
      if win then send(win, e, ...) end
    end
  elseif e == "mouse_click" then
    click(a, x, y)
  elseif e == "mouse_drag" then
    if drag then dragTo(x, y)
    elseif capture then send(capture, e, a, x - capture.x + 1, y - capture.y) end
  elseif e == "mouse_up" then
    if drag then
      if drag.mode == "move" and drag.moved then -- edge snap, like dragging to a screen edge
        if y <= 1 then wm.setLayout(drag.win, "max")
        elseif x <= 1 then wm.setLayout(drag.win, "left")
        elseif x >= W then wm.setLayout(drag.win, "right") end
      end
      drag = nil
    elseif capture then
      send(capture, e, a, x - capture.x + 1, y - capture.y)
    end
  elseif e == "mouse_scroll" then
    local win = not overlay and winAt(x, y)
    if win and y > win.y and y < H then send(win, e, a, x - win.x + 1, y - win.y) end
    if overlay and overlay.scroll then
      overlay.scroll(a)
      dirty = true
    end
  elseif e == "term_resize" then
    wm.resized(displays[1])
  elseif e == "timer" and a == clockTimer then
    clockTimer = os.startTimer(1)
    dirty = true
  else
    sched.broadcast(e, ...)
  end
end

-- A tap on a touch display: a click and release there. Monitors can't drag, scroll or right-click.
function wm.touch(d, x, y)
  enter(d)
  local button = wm.armed and 2 or 1 -- the taskbar's right-click button
  touching = true
  handle("mouse_click", button, x, y)
  handle("mouse_up", button, x, y)
  touching = false
end

function wm.init(screen)
  use(wm.addDisplay("screen", screen))
  clockTimer = os.startTimer(1)
end

-- Processes one event (or none, to just redraw), then closes dead windows and repaints.
function wm.step(e, ...)
  local before = sched.resumes
  if e then handle(e, ...) end
  for i = #wm.wins, 1, -1 do
    local win = wm.wins[i]
    if win.proc.dead then
      table.remove(wm.wins, i)
      if drag and drag.win == win then drag = nil end
      if capture == win then capture = nil end
      dirty = true
    end
  end
  sched.reap()
  if dirty or sched.resumes ~= before then draw() end
end

function wm.loop()
  wm.step()
  while true do wm.step(os.pullEventRaw()) end -- raw: Ctrl+T reaches the focused app, not the OS
end

return wm
