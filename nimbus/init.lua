-- Nimbus entry point: load the kernel and the desktop shell, then run the event loop.
local wm = require("kernel.wm")
local apps = require("lib.apps")
local users = require("lib.users")
local theme = require("lib.theme")
local net = require("lib.net")
local display = require("kernel.display")
local notify = require("shell.notify")
local session = require("shell.session")
wm.desktop = require("shell.desktop")
require("shell.taskbar")

-- The API programs see. user, home and prefs are filled in at sign-in; they are for
-- convenience only - permissions are decided inside lib/users, not from these fields.
_G.nimbus = {
  version = "1.0",
  wm = wm, sched = require("kernel.sched"), apps = apps, users = users, session = session, net = net, display = display,
  ui = require("lib.ui"), theme = theme.c, accents = theme.accents, prefs = {},
  fetch = require("lib.fetch"), update = require("lib.update"),
  open = apps.open, notify = notify.push, menu = wm.menu, setPref = session.setPref,
}

-- Ctrl+Shift+Delete opens Task Manager (Esc and Ctrl+Alt+Del never reach the computer).
wm.on(function(e, key)
  local held = wm.held
  if e == "key" and key == keys.delete and (held[keys.leftCtrl] or held[keys.rightCtrl])
    and (held[keys.leftShift] or held[keys.rightShift]) and not wm.modal() then
    apps.launch("taskmgr")
    return true
  end
end)

wm.init(term.current())
display.refresh()
net.start()
users.protect()
if #users.list() == 0 then session.setup() else session.signIn() end

local _, err = pcall(wm.loop) -- the loop only returns by crashing

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
printError("Nimbus crashed: " .. tostring(err))
print("Reboot and press 2 for safe mode.")
