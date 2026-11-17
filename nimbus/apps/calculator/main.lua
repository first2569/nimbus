-- Calculator: click the keys or type. Enter or = evaluates, C clears, < deletes.
local ui, c = nimbus.ui, nimbus.theme
local KEYS = { "789/C", "456*<", "123-(", "0.=+)" }
local expr, shown = "", "0"

local function press(k)
  if k == "C" then
    expr = ""
  elseif k == "<" then
    expr = expr:sub(1, -2)
  elseif k == "=" then
    -- only digits and operators get this far, so load() can't run anything else
    local fn = expr:match("^[%d%.%+%-%*/%(%)%^%% ]+$") and load("return " .. expr, "calc", "t", {})
    local ok, result = pcall(fn or error)
    expr = ok and type(result) == "number" and tostring(result) or ""
    shown = expr ~= "" and expr or "Error"
    return
  else
    expr = expr .. k
  end
  shown = expr ~= "" and expr or "0"
end

while true do
  local w = term.getSize()
  term.setBackgroundColor(c.view)
  term.clear()
  ui.row(1, "", c.card, c.cardText)
  term.setCursorPos(math.max(1, w - #shown), 1)
  term.write(shown:sub(-(w - 1)))
  for r, row in ipairs(KEYS) do
    for i = 1, #row do
      term.setCursorPos(2 + (i - 1) * 4, 1 + r * 2)
      term.write(" " .. row:sub(i, i) .. " ")
    end
  end

  local e, a, x, y = os.pullEvent()
  if e == "mouse_click" then
    local r, i = (y - 1) / 2, math.floor((x - 2) / 4) + 1
    if KEYS[r] and x >= 2 and (x - 2) % 4 < 3 and i <= #KEYS[r] then press(KEYS[r]:sub(i, i)) end
  elseif e == "char" then
    if a:match("[%d%.%+%-%*/%(%)%^%%=]") then press(a) elseif a:lower() == "c" then press("C") end
  elseif e == "key" and a == keys.enter then
    press("=")
  elseif e == "key" and a == keys.backspace then
    press("<")
  end
end
