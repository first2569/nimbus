-- File Share: download files that other Nimbus computers keep in their /shared folder.
-- To offer files from this computer, put them in /shared. Anyone in modem range can read it.
local ui, c, net = nimbus.ui, nimbus.theme, nimbus.net
local BUTTONS = { "Refresh", "Download" }
local LEFT = 16 -- width of the computer column

local peers, files = ui.list(1, 2, LEFT), ui.list(LEFT + 1, 2)
local status = net.online and "Refresh to look for computers" or "No modem attached"
local shown -- id of the computer whose files are listed
local incoming -- { from, name, parts } while a download runs

local function refresh()
  net.scan()
  sleep(1) -- let the answers arrive
  peers.items, files.items, shown = net.peerList(), {}, nil
  status = #peers.items .. " computers found"
end

local function save(name, data)
  local dir = nimbus.home .. "/Downloads"
  local path = fs.combine(dir, name)
  if fs.exists(path) then return "Already in Downloads: " .. name end
  local free = fs.getFreeSpace(nimbus.home)
  if type(free) == "number" and #data > free then return "Not enough space" end
  fs.makeDir(dir)
  local f, err = fs.open(path, "wb")
  if not f then return tostring(err) end
  f.write(data)
  f.close()
  return "Saved to " .. dir
end

while true do
  local _, h = term.getSize()
  local buttons = ui.buttons(1, BUTTONS, c.card, c.cardText)
  peers.draw(h - 1, function(p) return " " .. p.name .. "#" .. p.id end)
  files.draw(h - 1, function(f) return (" %-16s%7d"):format(f.name:sub(1, 16), f.size) end)
  ui.row(h, " " .. status, c.card, c.cardText)

  local e, a, b, d = os.pullEvent()
  if e == "rednet_message" and d == "nimbus" and type(b) == "table" then
    local from, msg = a, b -- replies come from another computer: check everything
    local peer = peers.items[peers.sel]
    if msg.type == "files" and peer and from == peer.id and type(msg.files) == "table" then
      files.items, shown = {}, from
      for _, f in ipairs(msg.files) do
        if type(f) == "table" and type(f.name) == "string" and type(f.size) == "number"
          and f.name ~= "" and not f.name:find("[/\\]") and f.name:sub(1, 1) ~= "." then
          files.items[#files.items + 1] = f
        end
      end
    elseif incoming and from == incoming.from and msg.type == "chunk" and msg.name == incoming.name
      and msg.seq == #incoming.parts + 1 and type(msg.data) == "string" then
      incoming.parts[msg.seq] = msg.data
      if msg.last then
        status = save(incoming.name, table.concat(incoming.parts))
        incoming = nil
      end
    elseif incoming and from == incoming.from and msg.type == "error" then
      status, incoming = tostring(msg.text), nil
    end
  elseif e == "mouse_click" and d == 1 then
    local i, file = ui.hit(buttons, b), files.items[files.sel]
    if i == 1 then
      refresh()
    elseif i == 2 and file and shown then
      incoming = { from = shown, name = file.name, parts = {} }
      status = "Downloading " .. file.name
      rednet.send(shown, { type = "get", name = file.name }, "nimbus")
    end
  elseif peers.event(e, a, b, d) then
    local peer = peers.items[peers.sel]
    if peer and peer.id ~= shown then
      files.items = {}
      rednet.send(peer.id, { type = "list" }, "nimbus")
    end
  elseif e ~= "key" then
    files.event(e, a, b, d)
  end
end
