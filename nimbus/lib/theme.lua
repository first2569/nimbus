-- Theme: every piece of Nimbus draws with these tokens instead of fixed colours.
-- theme.c is one table that is updated in place, so modules can keep a reference to it.
local theme = { c = {}, accents = { "blue", "cyan", "green", "purple", "magenta", "red", "brown" } }

local MODES = {
  dark = {
    bar = "gray", barText = "white", barDim = "lightGray", -- taskbar, active title bar, panels
    card = "lightGray", cardText = "black", cardDim = "gray", -- buttons, menus, toasts
    idle = "lightGray", idleText = "gray", -- inactive title bar
    view = "black", viewText = "white", -- app content
  },
  light = {
    bar = "lightGray", barText = "black", barDim = "gray",
    card = "white", cardText = "black", cardDim = "gray",
    idle = "white", idleText = "lightGray",
    view = "white", viewText = "black",
  },
}

-- desk is the accent: desktop background and selection, always drawn with white text.
function theme.apply(mode, accent)
  for token, name in pairs(MODES[mode] or MODES.dark) do theme.c[token] = colors[name] end
  theme.c.desk = colors.blue
  for _, name in ipairs(theme.accents) do
    if name == accent then theme.c.desk = colors[name] end
  end
end

theme.apply()
return theme
