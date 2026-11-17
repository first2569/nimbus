-- Small drawing and input helpers for Nimbus apps. Everything draws on the current terminal.
local c = require("lib.theme").c
local ui = {}

-- One full-width row of text.
function ui.row(y, text, bg, fg)
  local w = term.getSize()
  term.setCursorPos(1, y)
  term.setBackgroundColor(bg)
  term.setTextColor(fg)
  term.write((text .. (" "):rep(w)):sub(1, w))
end

-- A row of buttons. Returns hit regions; ui.hit(regions, x) gives the button index.
function ui.buttons(y, labels, bg, fg)
  ui.row(y, "", bg, fg)
  local hits, x = {}, 1
  for i, label in ipairs(labels) do
    term.setCursorPos(x + 1, y)
    term.write(label)
    hits[i] = { x, x + #label + 1 }
    x = x + #label + 1
  end
  return hits
end

function ui.hit(hits, x)
  for i, h in ipairs(hits) do
    if x >= h[1] and x <= h[2] then return i end
  end
end

-- One-line text input on row y; mask ("*") hides what is typed. Returns nil for an empty answer.
function ui.prompt(y, label, default, mask)
  ui.row(y, label, c.card, c.cardText)
  term.setCursorPos(#label + 1, y)
  local text = read(mask, nil, nil, default)
  return text ~= "" and text or nil
end

-- Context menu at the mouse. Returns the picked index, or nil if dismissed.
function ui.menu(labels)
  nimbus.menu(labels)
  local _, i = os.pullEvent("nimbus_menu")
  return i
end

-- A scrollable, selectable list starting at column x, row y1. Without a width it runs
-- to the right edge of the window.
function ui.list(x, y1, width)
  local l = { items = {}, sel = 1, off = 0, rows = 1, w = 1, last = -1 }

  -- Draws rows y1..y2; render(item) returns the row's text.
  function l.draw(y2, render)
    l.w = width or term.getSize() - x + 1
    l.rows = y2 - y1 + 1
    l.sel = math.max(1, math.min(#l.items, l.sel))
    if l.sel <= l.off then l.off = l.sel - 1
    elseif l.sel > l.off + l.rows then l.off = l.sel - l.rows end
    for r = 1, l.rows do
      local i = l.off + r
      local item = l.items[i]
      term.setCursorPos(x, y1 + r - 1)
      local picked = item and i == l.sel
      term.setBackgroundColor(picked and c.desk or c.view)
      term.setTextColor(picked and colors.white or c.viewText)
      term.write(((item and render(item) or "") .. (" "):rep(l.w)):sub(1, l.w))
    end
    -- page arrows at the right edge, for touch screens that have no wheel
    l.up, l.down = l.off > 0, l.off + l.rows < #l.items
    term.setBackgroundColor(c.card)
    term.setTextColor(c.cardText)
    if l.down then
      term.setCursorPos(x + l.w - 1, y2)
      term.write("\31")
    end
    if l.up then
      term.setCursorPos(x + l.w - 1, y1)
      term.write("\30")
    end
  end

  -- Returns "open", item on double-click or Enter; "menu", item-or-nil on right-click;
  -- true when it only used the event.
  function l.event(e, a, mx, my)
    local inside = (e == "mouse_click" or e == "mouse_scroll")
      and mx >= x and mx < x + l.w and my >= y1 and my < y1 + l.rows
    if e == "mouse_click" and inside and mx == x + l.w - 1 and ((my == y1 and l.up) or (my ~= y1 and my == y1 + l.rows - 1 and l.down)) then
      -- an arrow: move the selection just past the view, which scrolls it by a page
      l.sel = my == y1 and math.max(1, l.off - l.rows + 2) or math.min(#l.items, l.off + 2 * l.rows - 1)
      return true
    elseif e == "mouse_click" and inside then
      local i = l.off + my - y1 + 1
      local item = l.items[i]
      if item then
        local double = a == 1 and i == l.sel and os.clock() - l.last < 0.5
        l.sel, l.last = i, double and -1 or os.clock()
        if double then return "open", item end
      end
      if a == 2 then return "menu", item end
      return true
    elseif e == "mouse_scroll" and inside then
      l.sel = l.sel + a
      return true
    elseif e == "key" then
      if a == keys.up then l.sel = l.sel - 1 return true end
      if a == keys.down then l.sel = l.sel + 1 return true end
      if a == keys.enter and l.items[l.sel] then return "open", l.items[l.sel] end
    end
  end

  return l
end

return ui
