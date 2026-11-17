-- Remote Desktop: let another computer see and control this one, or control another one.
-- The PIN stops accidents, not attackers: rednet is not encrypted and sender ids can be forged.
-- Sharing stops when this window closes.
local ui, c, net = nimbus.ui, nimbus.theme, nimbus.net

local list = ui.list(1, 4)
local status = net.online and "" or "No modem attached"
local tick = os.startTimer(1)

while true do
  local _, h = term.getSize()
  local sharing = net.shareState()
  local buttons = ui.buttons(1, { sharing and "Stop sharing" or "Share", "Find", "Connect" }, c.card, c.cardText)
  local line = " Not shared"
  if sharing and sharing.viewer then line = " Controlled by computer #" .. sharing.viewer
  elseif sharing then line = " Waiting: this is #" .. os.getComputerID() .. ", PIN " .. sharing.pin end
  ui.row(2, line, c.view, c.viewText)
  ui.row(3, " Computers in range", c.bar, c.barText)
  list.draw(h - 1, function(p) return " " .. p.name .. "#" .. p.id .. (p.user and "  (" .. p.user .. ")" or "") end)
  ui.row(h, " " .. status, c.card, c.cardText)

  local e, a, x, y = os.pullEvent()
  if e == "timer" and a == tick then
    tick = os.startTimer(1) -- keeps the sharing line current
  elseif e == "mouse_click" and y == 1 then
    local i, peer = ui.hit(buttons, x), list.items[list.sel]
    status = ""
    if i == 1 then
      if sharing then net.shareStop() else net.shareStart() end
    elseif i == 2 then
      net.scan()
      sleep(1) -- let the answers arrive
      list.items = net.peerList()
      status = #list.items .. " computers found"
      tick = os.startTimer(1)
    elseif i == 3 and peer then
      local pin = ui.prompt(h, " PIN shown on that computer: ")
      if pin then
        local ok, err = net.connect(peer.id, pin)
        status = ok and "Connected. F12 disconnects." or err
        tick = os.startTimer(1)
      end
    elseif i == 3 then
      status = "Find a computer first"
    end
  else
    list.event(e, a, x, y)
  end
end
