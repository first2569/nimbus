-- Dice: click or press a key to roll two dice.
local c = nimbus.theme
while true do
  local a, b = math.random(6), math.random(6)
  term.setBackgroundColor(c.view)
  term.setTextColor(c.viewText)
  term.clear()
  term.setCursorPos(2, 2)
  term.write(("You rolled %d and %d: %d"):format(a, b, a + b))
  term.setCursorPos(2, 4)
  term.write("Click or press a key to roll again")
  repeat local e = os.pullEvent() until e == "mouse_click" or e == "key"
end
