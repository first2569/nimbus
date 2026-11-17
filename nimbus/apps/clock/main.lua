-- Clock: game time, real time, daily alarms (game time) and countdown timers (real minutes).
-- shortcut: alarms and timers only ring while this window is open (minimized is fine);
-- move them into the kernel if they must survive closing it.
local ui, c = nimbus.ui, nimbus.theme
local BUTTONS = { "Add alarm", "Add timer", "Remove" }

local list = ui.list(1, 5)
local entries = {} -- alarm: { at = game hour, id }; timer: { ends = os.clock() value, id, label }
local status = ""
local tick = os.startTimer(1)

local function arm(at) entries[#entries + 1] = { at = at, id = os.setAlarm(at) } end
for _, at in ipairs(nimbus.prefs.alarms or {}) do arm(at) end

local function save() -- alarms come back next time; timers don't
  local out = {}
  for _, entry in ipairs(entries) do
    if entry.at then out[#out + 1] = entry.at end
  end
  nimbus.setPref("alarms", out)
end

while true do
  local _, h = term.getSize()
  local buttons = ui.buttons(1, BUTTONS, c.card, c.cardText)
  ui.row(2, "", c.view, c.viewText)
  ui.row(3, ("  %s   day %d   (real %s)"):format(textutils.formatTime(os.time(), true), os.day(), os.date("%H:%M")), c.view, c.viewText)
  ui.row(4, "", c.view, c.viewText)
  list.items = entries
  list.draw(h - 1, function(entry)
    if entry.at then return " Alarm  " .. textutils.formatTime(entry.at, true) .. "  every game day" end
    local secs = math.max(0, math.ceil(entry.ends - os.clock()))
    return (" Timer  %d:%02d left"):format(math.floor(secs / 60), secs % 60)
  end)
  ui.row(h, " " .. status, c.card, c.cardText)

  local e, a, x, y = os.pullEvent()
  if e == "timer" and a == tick then
    tick = os.startTimer(1)
  elseif e == "alarm" or e == "timer" then
    for i, entry in ipairs(entries) do
      if entry.id == a and (e == "alarm") == (entry.at ~= nil) then
        if entry.at then
          nimbus.notify("Alarm", "It is " .. textutils.formatTime(entry.at, true))
          entry.id = os.setAlarm(entry.at) -- rings again tomorrow
        else
          nimbus.notify("Timer done", entry.label)
          table.remove(entries, i)
        end
        break
      end
    end
  elseif e == "mouse_click" and y == 1 then
    local i = ui.hit(buttons, x)
    status = ""
    if i == 1 then
      local hh, mm = (ui.prompt(h, " Alarm at (HH:MM, game time): ") or ""):match("^(%d%d?):(%d%d)$")
      if hh and tonumber(hh) < 24 and tonumber(mm) < 60 then
        arm(tonumber(hh) + tonumber(mm) / 60)
        save()
      else
        status = "Use HH:MM, like 06:30"
      end
    elseif i == 2 then
      local mins = tonumber(ui.prompt(h, " Minutes: ") or "")
      if mins and mins > 0 then
        entries[#entries + 1] = { ends = os.clock() + mins * 60, id = os.startTimer(mins * 60), label = mins .. " min" }
      else
        status = "Enter a number of minutes"
      end
    elseif i == 3 and entries[list.sel] then
      local entry = table.remove(entries, list.sel)
      if entry.at then
        os.cancelAlarm(entry.id)
        save()
      else
        os.cancelTimer(entry.id)
      end
    end
  else
    list.event(e, a, x, y)
  end
end
