-- Chat: messages to everyone in modem range, or to one computer.
-- Not private: rednet can be overheard and sender names can be faked.
local ui, c, net = nimbus.ui, nimbus.theme, nimbus.net
local to, toName, input = nil, "everyone", ""

while true do
  local w, h = term.getSize()
  ui.row(1, " To: " .. toName .. (net.online and "   (click to change)" or "   No modem attached"), c.bar, c.barText)
  local first = math.max(1, #net.chat - (h - 3))
  for y = 2, h - 1 do
    local m = net.chat[first + y - 2]
    -- shortcut: long messages are cut at the window edge, not wrapped
    ui.row(y, m and " " .. m.from .. ": " .. m.text or "", c.view, m and m.from == "me" and c.cardDim or c.viewText)
  end
  ui.row(h, " > " .. input:sub(-(w - 5)) .. "_", c.card, c.cardText)

  local e, a, _, y = os.pullEvent()
  if e == "char" or e == "paste" then
    input = input .. a
  elseif e == "key" and a == keys.backspace then
    input = input:sub(1, -2)
  elseif e == "key" and a == keys.enter and input ~= "" then
    net.say(input, to)
    input = ""
  elseif e == "mouse_click" and y == 1 then
    net.scan()
    sleep(1) -- let the answers arrive
    local peers, labels = net.peerList(), { "Everyone" }
    for i, p in ipairs(peers) do labels[i + 1] = p.name .. "#" .. p.id end
    local i = ui.menu(labels)
    if i == 1 then to, toName = nil, "everyone"
    elseif i then to, toName = peers[i - 1].id, labels[i] end
  end
end
