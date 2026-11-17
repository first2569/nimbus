-- Tasks: Nimbus's task manager. Lists every process; Activity is events handled per second.
local ui, wm, sched, c = nimbus.ui, nimbus.wm, nimbus.sched, nimbus.theme
local BUTTONS = { "End task", "Switch to" }

local list = ui.list(1, 3)
local seen, rate = {}, {}
local timer = os.startTimer(1)

while true do
  local _, h = term.getSize()
  list.items = {}
  for i, p in ipairs(sched.procs) do list.items[i] = p end
  local buttons = ui.buttons(1, BUTTONS, c.card, c.cardText)
  ui.row(2, (" %-5s%-16s%-10s%s"):format("PID", "Name", "State", "Activity"), c.bar, c.barText)
  list.draw(h, function(p)
    local win = p.win
    local state = not win and "service" or win.minimized and "minimized" or win == wm.focused() and "focused" or "open"
    return (" %-5d%-16s%-10s%d/s"):format(p.pid, (win and win.title or p.name):sub(1, 15), state, rate[p.pid] or 0)
  end)

  local e, a, x, y = os.pullEvent()
  if e == "timer" and a == timer then
    for _, p in ipairs(sched.procs) do
      rate[p.pid] = p.resumes - (seen[p.pid] or p.resumes)
      seen[p.pid] = p.resumes
    end
    timer = os.startTimer(1)
  elseif e == "mouse_click" and y == 1 then
    local i, p = ui.hit(buttons, x), list.items[list.sel]
    if p and p.win and i == 1 then wm.close(p.win) end
    if p and p.win and i == 2 then wm.focus(p.win) end
  else
    list.event(e, a, x, y)
  end
end
