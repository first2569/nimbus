-- Networking over rednet: discovery, chat, the shared folder and remote desktop.
-- None of it is private or authenticated. Rednet is not encrypted and any computer in range
-- can forge a sender id, so this is for players you trust. The remote-desktop PIN stops
-- accidents, not attackers.
local wm = require("kernel.wm")
local sched = require("kernel.sched")
local notify = require("shell.notify")

local net = { online = false, chat = {}, peers = {} }
local PROTO, SHARED, CHUNK = "nimbus", "/shared", 8192
local INPUTS = { -- the only events a remote viewer may inject
  key = true, key_up = true, char = true, paste = true,
  mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true,
}
local share -- hosting: { pin, tries, viewer, owner, sent }
local view -- viewing: { host, lines }

local function send(to, msg)
  if to then rednet.send(to, msg, PROTO) else rednet.broadcast(msg, PROTO) end
end

local function openModems()
  net.online = false
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      if not rednet.isOpen(name) then rednet.open(name) end
      net.online = true
    end
  end
end

function net.name() return os.getComputerLabel() or "computer" end

-- Asks who is out there; answers trickle into net.peers over the next second.
function net.scan()
  net.peers = {}
  send(nil, { type = "who" })
end

function net.peerList()
  local list = {}
  for _, peer in pairs(net.peers) do list[#list + 1] = peer end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- to = computer id, or nil for everyone in range.
function net.say(text, to)
  send(to, { type = "chat", from = net.name(), text = text })
  net.chat[#net.chat + 1] = { from = "me", text = text }
end

-- Remote desktop, host side. Sharing ends when the program that started it closes.
function net.shareStart()
  share = { pin = ("%04d"):format(math.random(0, 9999)), tries = 0, owner = sched.current, sent = {} }
  return share.pin
end

function net.shareStop()
  if share and share.viewer then send(share.viewer, { type = "bye" }) end
  share = nil
end

function net.shareState() return share and { pin = share.pin, viewer = share.viewer } end

-- After the computer's own screen is drawn, send the paired viewer the lines that changed.
wm.afterFrame(function(d)
  if d ~= wm.displays()[1] or not share then return end
  local root, H = d.root, d.H
  if share.owner and share.owner.dead then return net.shareStop() end
  if not share.viewer then return end
  local lines, any = {}, false
  for y = 1, H do
    local text, fg, bg = root.getLine(y)
    local key = text .. fg .. bg
    if share.sent[y] ~= key then share.sent[y], lines[y], any = key, { text, fg, bg }, true end
  end
  if any then send(share.viewer, { type = "frame", lines = lines }) end
end)

-- Remote desktop, viewer side. Call from a program; returns true once paired, or false, reason.
-- The remote screen then covers this one until F12.
function net.connect(id, pin)
  send(id, { type = "pair", pin = pin })
  local timer = os.startTimer(3)
  while true do
    local e, a, msg, proto = os.pullEvent()
    if e == "timer" and a == timer then return false, "No answer" end
    if e == "rednet_message" and a == id and proto == PROTO and type(msg) == "table" then
      if msg.type == "refused" then return false, "Wrong PIN, or it isn't sharing" end
      if msg.type == "paired" then break end
    end
  end
  view = { host = id, lines = {} }
  wm.overlay({
    modal = true,
    draw = function()
      local root = wm.root()
      local W, H = wm.size()
      for y = 1, H do wm.text(1, y, (" "):rep(W), colors.black, colors.white) end
      for y, line in pairs(view.lines) do
        root.setCursorPos(1, y)
        root.blit(line[1], line[2], line[3])
      end
    end,
    raw = function(e, ...)
      if e == "key" and (...) == keys.f12 then
        send(view.host, { type = "bye" })
        view = nil
        return false
      end
      send(view.host, { type = "input", event = { e, ... } })
      return true
    end,
  })
  return true
end

local function validLine(line)
  return type(line) == "table" and type(line[1]) == "string" and type(line[2]) == "string" and type(line[3]) == "string"
    and #line[1] == #line[2] and #line[1] == #line[3] and line[2]:match("^[0-9a-f]*$") and line[3]:match("^[0-9a-f]*$")
end

-- Everything arriving here is untrusted input from another computer.
local function handle(from, msg)
  local kind = msg.type
  if kind == "who" then
    send(from, { type = "here", name = net.name(), user = nimbus.user and nimbus.user.name })
  elseif kind == "here" then
    net.peers[from] = { id = from, name = tostring(msg.name):sub(1, 16), user = msg.user and tostring(msg.user):sub(1, 12) }
  elseif kind == "chat" and type(msg.text) == "string" then
    local who = tostring(msg.from):sub(1, 16) .. "#" .. from
    net.chat[#net.chat + 1] = { from = who, text = msg.text:sub(1, 200) }
    if #net.chat > 100 then table.remove(net.chat, 1) end
    local top = wm.focused()
    if not (top and top.app == "chat") then notify.push("Chat: " .. who, msg.text:sub(1, 40)) end
  elseif kind == "list" then
    local files = {}
    for _, name in ipairs(fs.list(SHARED)) do
      local path = fs.combine(SHARED, name)
      if not fs.isDir(path) then files[#files + 1] = { name = name, size = fs.getSize(path) } end
    end
    send(from, { type = "files", files = files })
  elseif kind == "get" and type(msg.name) == "string" then
    local path = fs.combine(SHARED, msg.name)
    -- only plain files directly inside the shared folder, whatever the name says
    if fs.getDir(path) ~= fs.combine(SHARED, "") or not fs.exists(path) or fs.isDir(path) then
      return send(from, { type = "error", text = "No such file" })
    end
    local f = fs.open(path, "rb")
    local data = f.readAll() or ""
    f.close()
    local parts = math.max(1, math.ceil(#data / CHUNK))
    for i = 1, parts do
      send(from, { type = "chunk", name = msg.name, seq = i, last = i == parts, data = data:sub((i - 1) * CHUNK + 1, i * CHUNK) })
    end
  elseif kind == "pair" then
    if share and not share.viewer and msg.pin == share.pin then
      share.viewer, share.sent = from, {}
      local W, H = wm.size()
      send(from, { type = "paired", w = W, h = H })
      notify.push("Remote Desktop", "Computer #" .. from .. " is in control")
    else
      send(from, { type = "refused" })
      if share and not share.viewer then
        share.tries = share.tries + 1
        if share.tries >= 5 then net.shareStop() end -- a 4-digit PIN doesn't survive guessing
      end
    end
  elseif kind == "input" and share and from == share.viewer and type(msg.event) == "table" and INPUTS[msg.event[1]] then
    os.queueEvent(table.unpack(msg.event, 1, 4))
  elseif kind == "bye" then
    if share and from == share.viewer then net.shareStop() end
    if view and from == view.host then
      view = nil
      wm.overlay(nil)
    end
  elseif kind == "frame" and view and from == view.host and type(msg.lines) == "table" then
    for y, line in pairs(msg.lines) do
      if type(y) == "number" and y >= 1 and y <= 200 and y % 1 == 0 and validLine(line) then view.lines[y] = line end
    end
    wm.redraw()
  end
end

-- Starts the background service: it has no window and shows up in Tasks as "network".
function net.start()
  if not fs.exists(SHARED) then fs.makeDir(SHARED) end
  local proc = sched.spawn("network", window.create(wm.root(), 1, 1, 1, 1, false), function()
    openModems()
    while true do
      local e, from, msg, proto = os.pullEventRaw()
      if e == "peripheral" or e == "peripheral_detach" then
        openModems()
        wm.redraw()
      elseif e == "rednet_message" and proto == PROTO and type(msg) == "table" then
        pcall(handle, from, msg) -- a malformed message must not take the service down
      end
    end
  end)
  sched.resume(proc)
end

return net
