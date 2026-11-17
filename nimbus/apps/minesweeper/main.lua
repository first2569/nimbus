-- Minesweeper for Nimbus. Left click reveals, right click flags; the first click is always safe.
-- The board fills the window, so resizing starts a new game.
local ui, c = nimbus.ui, nimbus.theme
local cols, rows, mines, grid, state, hidden, flags, planted

local function new()
  local w, h = term.getSize()
  cols, rows = math.max(2, math.floor(w / 2)), math.max(1, h - 1)
  mines = math.max(1, math.floor(cols * rows * 0.15))
  grid, state, hidden, flags, planted = {}, "play", cols * rows - mines, 0, false -- hidden: safe cells left
  for i = 1, cols * rows do grid[i] = { n = 0 } end
end

local function around(i, fn)
  local x, y = (i - 1) % cols, math.floor((i - 1) / cols)
  for dy = -1, 1 do
    for dx = -1, 1 do
      local nx, ny = x + dx, y + dy
      if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < cols and ny >= 0 and ny < rows then fn(ny * cols + nx + 1) end
    end
  end
end

local function plant(safe) -- runs on the first click, so that cell is never a mine
  local placed = 0
  while placed < mines do
    local i = math.random(cols * rows)
    if i ~= safe and not grid[i].mine then
      grid[i].mine, placed = true, placed + 1
      around(i, function(j) grid[j].n = grid[j].n + 1 end)
    end
  end
  planted = true
end

local function reveal(i)
  local stack = { i }
  while #stack > 0 do
    local j = table.remove(stack)
    local cell = grid[j]
    if not cell.open and not cell.flag then
      cell.open = true
      if cell.mine then state = "lost" return end
      hidden = hidden - 1
      if cell.n == 0 then around(j, function(k) stack[#stack + 1] = k end) end
    end
  end
  if hidden == 0 then state = "won" end
end

local function draw()
  local result = state == "won" and "  You win!" or state == "lost" and "  Boom!" or ""
  ui.row(1, " Mines: " .. mines - flags .. "   [New]" .. result, c.bar, c.barText)
  for i, cell in ipairs(grid) do
    local text, bg, fg = "  ", c.card, c.cardText
    if cell.mine and state == "lost" then text, bg, fg = "* ", colors.red, colors.white
    elseif cell.flag then text, bg, fg = "F ", colors.orange, colors.black
    elseif cell.open then text, bg, fg = (cell.n > 0 and cell.n or " ") .. " ", c.view, c.viewText end
    term.setCursorPos((i - 1) % cols * 2 + 1, math.floor((i - 1) / cols) + 2)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.write(text)
  end
end

new()
term.setBackgroundColor(c.view)
term.clear()
while true do
  draw()
  local e, button, x, y = os.pullEvent()
  if e == "term_resize" or (e == "mouse_click" and y == 1) then
    new()
    term.setBackgroundColor(c.view)
    term.clear()
  elseif e == "mouse_click" and state == "play" then
    local cx, cy = math.floor((x - 1) / 2), y - 2
    local cell = cx < cols and cy < rows and grid[cy * cols + cx + 1]
    if cell and button == 1 and not cell.flag then
      if not planted then plant(cy * cols + cx + 1) end
      reveal(cy * cols + cx + 1)
    elseif cell and button == 2 and not cell.open then
      cell.flag = not cell.flag
      flags = flags + (cell.flag and 1 or -1)
    end
  end
end
