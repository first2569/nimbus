-- Acceptance test for real CC: Tweaked (CraftOS-PC or in-game). Boots the whole desktop
-- on an off-screen 51x19 display and drives it with queued events.
-- Emulator, from the project root:  sh tests/run.sh
-- In-game, with the project files at the computer's root:  tests/acceptance
-- Needs a factory-fresh scratch computer: it runs first-boot setup and creates the accounts
-- "tester" and "kid". In-game, also copy the repo's store folder to /store.
local args = { ... }
local proj = fs.exists("/proj/startup.lua") and "/proj" or "" -- the emulator run mounts the repo at /proj
local screen = window.create(term.current(), 1, 1, 51, 19, false)
local results = {}

local function tick(n) -- raw wait: the "terminate" this test queues must not kill the test itself
  for _ = 1, n or 1 do
    local timer = os.startTimer(0.15)
    repeat local e, id = os.pullEventRaw() until e == "timer" and id == timer
  end
end
local function ev(...) os.queueEvent(...) tick() end
local function click(x, y, button)
  ev("mouse_click", button or 1, x, y)
  ev("mouse_up", button or 1, x, y)
end
local function rclick(x, y) click(x, y, 2) end
local function double(x, y)
  os.queueEvent("mouse_click", 1, x, y)
  os.queueEvent("mouse_up", 1, x, y)
  click(x, y)
end
local function typed(text)
  for c in text:gmatch(".") do os.queueEvent("char", c) end
  tick()
end
local function enter() ev("key", keys.enter) end
local function check(cond, what)
  if not cond then error("FAIL: " .. what, 0) end
  results[#results + 1] = "ok   " .. what
end
local function find(target, text) -- x, y of text in a window buffer
  local _, h = target.getSize()
  for y = 1, h do
    local x = target.getLine(y):find(text, 1, true)
    if x then return x, y end
  end
end
local function win(title)
  for _, w in ipairs(nimbus.wm.wins) do
    if w.title == title then return w end
  end
end
local function inWin(w, text) -- screen position of text inside a window's body
  local x, y = find(w.body, text)
  if x then return w.x + x - 1, w.y + y end
end

local function waitFor(target, text) -- for slow steps: up to about six seconds
  for _ = 1, 40 do
    if find(target, text) then return true end
    tick()
  end
end

-- Sends a test command to the second computer and returns its answer.
local function tell(cmd, wait)
  rednet.send(1, cmd, "nimbus.test")
  if wait == false then return end
  local _, reply = rednet.receive("nimbus.test", 3)
  return reply
end

-- The second computer in the network tests runs this: it sets itself up, shares a file,
-- then does what the first computer tells it over the "nimbus.test" protocol.
local function peer()
  periphemu.create("top", "modem")
  parallel.waitForAny(function() shell.run("/nimbus/init.lua") end, function()
    tick(3)
    for _, text in ipairs({ "peer", "pw", "pw" }) do
      typed(text)
      enter()
    end
    local f = fs.open("/shared/hello.txt", "w")
    f.write("hello from the peer")
    f.close()
    while true do
      local from, cmd = rednet.receive("nimbus.test")
      if cmd == "ping" then
        rednet.send(from, nimbus.user and "pong" or "booting", "nimbus.test")
      elseif cmd == "pin" then
        rednet.send(from, nimbus.net.shareStart(), "nimbus.test")
      elseif cmd == "say" then
        nimbus.net.say("hello from peer", from)
      elseif cmd == "heard" then
        local last = nimbus.net.chat[#nimbus.net.chat]
        rednet.send(from, last and last.text or "", "nimbus.test")
      elseif cmd == "quit" then
        os.shutdown()
      end
    end
  end)
end

local function test()
  tick(3)
  local wm = nimbus.wm
  check(loadfile(proj .. "/startup.lua") and loadfile("/nimbus/recovery.lua"), "bootloader and safe mode compile")
  package.path = "/nimbus/?.lua;" .. package.path
  check(require("lib.sha256")("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    "SHA-256 matches the NIST vector on this runtime")

  -- first boot
  check(find(screen, "create your account") and #nimbus.users.list() == 0, "first boot asks for an account")
  typed("tester")
  enter()
  typed("one")
  enter()
  typed("two")
  enter()
  check(find(screen, "Passwords don't match"), "setup rejects mismatched passwords")
  enter()
  typed("secret")
  enter()
  typed("secret")
  enter()
  check(nimbus.users.current().admin and nimbus.home == "/home/tester", "the first account is an admin and is signed in")
  check(settings.get("shell.allow_disk_startup") == false, "booting from a disk is switched off")
  check(#wm.wins == 0 and find(screen, "Files") and find(screen, "Terminal"), "then comes a desktop with icons and a taskbar")
  check(find(screen, "Welcome, tester"), "and a welcome notification")

  -- taskbar
  local fx = screen.getLine(19):find("Files", 1, true)
  click(fx, 19)
  local files = wm.wins[1]
  check(files and files.title == "Files" and files.app == "explorer", "the taskbar launches a pinned app")
  click(fx, 19)
  check(files.minimized, "its taskbar button minimizes the focused window")
  click(fx, 19)
  check(not files.minimized and wm.focused() == files, "and restores it")
  rclick(fx, 19)
  check(#wm.wins == 2, "right-click opens a second window")
  wm.close(wm.focused())
  tick()

  -- Files
  check(find(files.body, "Desktop/"), "Files lists the home folder")
  double(inWin(files, "Desktop/"))
  check(find(files.body, "Files.lnk"), "double-click opens a folder")
  click(inWin(files, "+File"))
  typed("nimbus_test.txt")
  enter()
  check(fs.exists("/home/tester/Desktop/nimbus_test.txt") and find(files.body, "nimbus_test.txt"), "the toolbar creates a file")
  click(inWin(files, "nimbus_test.txt"))
  click(inWin(files, "Copy"))
  click(inWin(files, "Up"))
  click(inWin(files, "Paste"))
  check(fs.exists("/home/tester/nimbus_test.txt"), "copy and paste between folders")
  rclick(inWin(files, "nimbus_test.txt"))
  local mx, my = find(screen, " Open ")
  check(mx, "right-click opens a context menu")
  click(mx, my + 4) -- Open, Rename, Copy, Cut, Del
  typed("y")
  enter()
  check(not fs.exists("/home/tester/nimbus_test.txt"), "context menu > Del deletes after confirming")
  double(inWin(files, "Desktop/"))
  double(inWin(files, "nimbus_test.txt"))
  check(win("edit"), "double-click opens a file in the editor")
  typed("hello")
  check(find(win("edit").body, "hello") and not find(files.body, "hello"), "typing reaches only the focused window")

  -- Start menu and Task Manager
  click(screen.getLine(19):find("\4", 1, true), 19)
  check(find(screen, "Search:") and find(screen, "Shut down") and find(screen, " Notepad"), "Start opens with the app grid")
  typed("tas")
  check(find(screen, "Search: tas") and not find(screen, " Notepad"), "typing filters the apps")
  enter()
  local tasks = win("Tasks")
  check(tasks and tasks.app == "taskmgr" and not find(screen, "Search:"), "Enter launches the match and closes Start")
  check(find(tasks.body, "PID") and find(tasks.body, "edit"), "Task Manager lists the running programs")
  click(inWin(tasks, "edit"))
  click(inWin(tasks, "End task"))
  check(not win("edit") and #wm.wins == 2, "End task closes the selected program")

  -- window manager, with stock programs
  wm.run("worm")
  tick()
  check(win("worm"), "worm runs in a window")
  ev("terminate")
  check(not win("worm") and #wm.wins == 2, "Ctrl+T closes only the focused program")
  wm.focus(tasks)
  tick()
  local x, y = tasks.x, tasks.y
  ev("mouse_click", 1, x + 1, y)
  ev("mouse_drag", 1, x + 4, y + 2)
  ev("mouse_up", 1, x + 4, y + 2)
  check(tasks.x == x + 3 and tasks.y == y + 2, "title-bar drag moves a window")
  click(tasks.x + tasks.w - 5, tasks.y)
  check(tasks.w == 51 and tasks.body.getSize() == 51, "maximize resizes the program's terminal")
  check(find(tasks.body, "PID"), "the program redraws after the resize")

  -- shortcuts
  os.queueEvent("key", keys.leftCtrl)
  ev("key", keys.tab)
  check(wm.focused() == files, "Ctrl+Tab switches windows")
  os.queueEvent("key", keys.leftShift)
  ev("key", keys.delete)
  os.queueEvent("key_up", keys.leftCtrl)
  ev("key_up", keys.leftShift)
  check(#wm.wins == 3 and wm.focused().app == "taskmgr", "Ctrl+Shift+Delete opens Task Manager")
  check(fs.exists("/home/tester/Desktop/nimbus_test.txt"), "and the Delete key was not passed on to Files")
  wm.close(wm.focused())
  tick()

  -- notifications
  nimbus.notify("Test note", "from the test")
  tick()
  check(find(screen, "Test note"), "a notification shows a toast")
  click(50, 19)
  check(find(screen, "Notifications"), "the tray opens the notification center")
  click(1, 1)
  check(not find(screen, "Notifications"), "a click outside closes it")

  -- desktop
  for _, w in ipairs({ table.unpack(wm.wins) }) do wm.minimize(w) end
  tick(8)
  check(find(screen, "nimbus_te"), "a file created in Desktop shows up as an icon")
  double(find(screen, "Terminal"))
  check(wm.focused() and wm.focused().app == "terminal", "double-clicking a desktop icon opens it")
  typed("id")
  enter()
  check(find(wm.focused().body, "computer #"), "the Terminal runs commands")
  wm.minimize(wm.focused())
  tick()
  rclick(30, 10)
  check(find(screen, "Refresh"), "right-click on the desktop opens its menu")
  click(1, 1)

  local f = fs.open("/home/tester/nimbus_test.nfp", "w")
  f.write("ee\nee")
  f.close()
  nimbus.setPref("wallpaper", "/home/tester/nimbus_test.nfp")
  tick(2)
  local _, _, bg = screen.getLine(1)
  check(bg:sub(1, 2) == "ee", "an .nfp wallpaper is drawn")

  -- Settings
  local set = nimbus.apps.launch("settings")
  tick()
  click(inWin(set, "light"))
  check(nimbus.prefs.theme == "light" and nimbus.theme.view == colors.white, "Settings switches the theme")
  click(inWin(set, "dark"))
  click(inWin(set, "Accounts"))
  check(find(set.body, "(you)"), "Accounts lists the signed-in user")
  click(inWin(set, "Add user"))
  typed("kid")
  enter()
  typed("kidpw")
  enter()
  check(#nimbus.users.list() == 2 and find(set.body, "standard"), "an admin can add a standard user")

  -- bundled apps
  wm.close(set)
  tick()
  local function finish(w) -- close a test window; fails if the program had already crashed
    check(w.proc and not w.proc.dead, w.title .. " is still running")
    wm.close(w)
    tick()
  end
  click(screen.getLine(19):find("\4", 1, true), 19)
  check(find(screen, " Calculator") and find(screen, " Minesweeper") and find(screen, " Store"), "Start lists the new apps")
  click(1, 1)

  local calc = nimbus.apps.launch("calculator")
  tick()
  local extra = { wm.run("worm"), wm.run("worm"), wm.run("worm") }
  wm.focus(calc)
  tick()
  check(screen.getLine(19):find(" Cal", 1, true) and select(2, screen.getLine(19):gsub(" wo", "")) == 3,
    "the taskbar shortens titles so every window keeps a button")
  for _, w in ipairs(extra) do wm.close(w) end
  tick()
  check(calc.w == 22 and calc.h == 11, "an app can ask for its own window size")
  typed("2+3*4")
  enter()
  check(calc.body.getLine(1):find("14", 1, true), "Calculator respects operator precedence")
  click(inWin(calc, " C "))
  click(inWin(calc, " 7 "))
  click(inWin(calc, " / "))
  click(inWin(calc, " 0 "))
  check(calc.body.getLine(1):find("7/0", 1, true), "its keys can be clicked")
  typed("x")
  typed("=")
  check(not calc.body.getLine(1):find("x", 1, true), "and it ignores anything that isn't arithmetic")
  finish(calc)

  local mines = nimbus.apps.launch("minesweeper")
  tick()
  click(mines.x + 10, mines.y + 5)
  check(find(mines.body, "Mines:") and not find(mines.body, "Boom"), "Minesweeper's first click is safe")
  rclick(mines.x, mines.y + 2)
  click(inWin(mines, "[New]"))
  finish(mines)

  local clock = nimbus.apps.launch("clock")
  tick()
  click(inWin(clock, "Add alarm"))
  typed("06:30")
  enter()
  check(find(clock.body, "6:30") and nimbus.prefs.alarms[1] == 6.5, "Clock saves an alarm")
  click(inWin(clock, "Add timer"))
  typed("0.01")
  enter()
  tick(8)
  check(find(screen, "Timer done"), "a finished timer raises a notification")
  click(inWin(clock, "Alarm"))
  click(inWin(clock, "Remove"))
  check(#nimbus.prefs.alarms == 0, "alarms can be removed")
  finish(clock)

  if periphemu then -- CraftOS-PC only: plug in an emulated drive
    periphemu.create("left", "drive")
    local per = nimbus.apps.launch("peripherals")
    tick()
    check(find(per.body, "drive") and find(per.body, "ejectDisk"), "Peripherals lists a device and its methods")
    click(inWin(per, "Eject"))
    check(find(per.body, "No disk in the drive"), "and runs its quick action")
    periphemu.remove("left")
    tick()
    check(find(per.body, "Nothing attached"), "and notices when it is unplugged")
    finish(per)
  end

  settings.set("nimbus.store", proj .. "/store")
  local store = nimbus.apps.launch("store")
  tick()
  check(find(store.body, "Dice") and find(store.body, "Roll two dice"), "Store lists the catalog")
  click(inWin(store, "Install"))
  tick()
  check(fs.exists("/nimbus/apps/dice/main.lua") and nimbus.apps.byId.dice and nimbus.apps.byId.dice.store, "it installs an app")
  check(find(store.body, "installed"), "and shows it as installed")
  local dice = nimbus.apps.launch("dice")
  tick()
  check(find(dice.body, "You rolled"), "the installed app runs")
  finish(dice)
  click(inWin(store, "Uninstall"))
  check(not fs.exists("/nimbus/apps/dice") and not nimbus.apps.byId.dice, "and can be uninstalled")
  finish(store)
  set = nimbus.apps.launch("settings")
  tick()

  -- monitors. Headless CraftOS-PC has none, so a stand-in peripheral is patched in: a window
  -- that changes size with its text scale, the way a real monitor does.
  do
    local mon = window.create(term.native(), 1, 1, 26, 12, false)
    function mon.setTextScale(scale) mon.reposition(1, 1, math.floor(130 / scale), math.floor(60 / scale)) end
    local real = { getNames = peripheral.getNames, getType = peripheral.getType, wrap = peripheral.wrap }
    peripheral.getNames = function()
      local names = real.getNames()
      names[#names + 1] = "monitor_9"
      return names
    end
    peripheral.getType = function(name) return name == "monitor_9" and "monitor" or real.getType(name) end
    peripheral.wrap = function(name) return name == "monitor_9" and mon or real.wrap(name) end
    local function tap(x, y) ev("monitor_touch", "monitor_9", x, y) end

    ev("peripheral", "monitor_9")
    check(wm.touchMode and #wm.displays() == 1 and mon.getLine(19):find("Files", 1, true), "a monitor copies the screen by default")
    tap(screen.getLine(19):find("Files", 1, true), 19)
    check(wm.focused() and wm.focused().app == "explorer", "a tap on the copy acts on the computer's screen")
    wm.minimize(wm.focused())
    click(inWin(set, "Display"))
    check(find(set.body, "monitor_9 (copy)"), "Settings lists the monitor")

    check(nimbus.display.setMode("extend"), "an admin can change the monitor mode")
    tick()
    local d2 = wm.displays()[2]
    check(d2 and d2.name == "monitor_9" and d2.W == 52 and d2.H == 24, "extend gives the monitor its own desktop, at the largest text that fits one")
    check(mon.getLine(24):find("Files", 1, true) and find(mon, "Terminal"), "with its own taskbar and icons")
    tap(30, 12)
    local far = nimbus.apps.launch("terminal")
    tick()
    check(far.display == d2 and find(mon, "CraftOS") and not find(screen, "CraftOS"), "apps open on the display that was tapped")
    tap(far.x + 2, far.y)
    local mx2, my2 = find(mon, "To screen")
    check(mx2 and far.display == d2, "tapping a title bar opens the window menu")
    tap(mx2, my2)
    check(far.display == wm.displays()[1] and find(screen, "CraftOS"), "which can send the window to the other display")
    tap(3, 24)
    tap(30, 12)
    check(find(mon, "Refresh") and not find(screen, "Refresh"), "the taskbar's right-click button makes the next tap a right-click")
    tap(1, 1)
    typed("id")
    enter()
    check(find(far.body, "computer #"), "the keyboard still reaches the focused window")
    finish(far)

    peripheral.getNames, peripheral.getType, peripheral.wrap = real.getNames, real.getType, real.wrap
    ev("peripheral_detach", "monitor_9")
    check(#wm.displays() == 1 and not wm.touchMode, "unplugging the monitor removes its desktop")
    nimbus.display.setMode("duplicate")
  end

  -- networking (CraftOS-PC only: a second emulated computer runs this same script as the peer)
  if periphemu then
    periphemu.create("top", "modem")
    tick()
    check(nimbus.net.online, "a modem plugged in later is opened")
    periphemu.create(1, "computer")
    local up
    for _ = 1, 60 do
      up = tell("ping") == "pong"
      if up then break end
      tick(2)
    end
    check(up, "a second computer boots Nimbus")

    local chat = nimbus.apps.launch("chat")
    tick()
    typed("hi there")
    enter()
    check(find(chat.body, "me: hi there") and tell("heard") == "hi there", "Chat delivers a message")
    wm.minimize(chat)
    tick()
    tell("say", false)
    tick(2)
    check(find(screen, "Chat: ") and find(chat.body, "hello from peer"), "an incoming message is logged and raises a notification")
    finish(chat)

    local share = nimbus.apps.launch("share")
    tick()
    click(inWin(share, "Refresh"))
    tick(8)
    check(find(share.body, "#1"), "File Share finds the other computer")
    click(inWin(share, "#1"))
    tick(2)
    check(find(share.body, "hello.txt"), "and lists its shared files")
    click(inWin(share, "hello.txt"))
    click(inWin(share, "Download"))
    tick(2)
    local f = fs.open("/home/tester/Downloads/hello.txt", "r")
    check(f and f.readAll() == "hello from the peer", "and downloads one into Downloads")
    f.close()
    rednet.send(1, { type = "get", name = "../startup.lua" }, "nimbus")
    local _, reply = rednet.receive("nimbus", 2)
    check(type(reply) == "table" and reply.type == "error", "a request for a file outside the shared folder is refused")
    finish(share)

    local pin = tell("pin")
    check(type(pin) == "string" and #pin == 4, "the other computer starts sharing its screen")
    check(not nimbus.net.connect(1, pin == "0000" and "1111" or "0000"), "Remote Desktop refuses a wrong PIN")
    check(nimbus.net.connect(1, pin), "and pairs with the right one")
    tick(3)
    click(screen.getLine(19):find("\4", 1, true), 19)
    tick(3)
    check(find(screen, " peer "), "the viewer sees and controls the other desktop")
    ev("key", keys.f12)
    check(not wm.modal() and not find(screen, " peer "), "F12 disconnects")
    tell("quit", false)
  end

  -- updater, through Settings (the repo mounted at /proj is the update source)
  if proj ~= "" then
    settings.set("nimbus.repo", proj)
    click(inWin(set, "Update"))
    click(inWin(set, "Check"))
    check(waitFor(set.body, "up to date"), "a fresh install is up to date")
    local f = fs.open("/nimbus/apps/calculator/main.lua", "a")
    f.write("-- edited")
    f.close()
    fs.delete("/nimbus/apps/worm/app.json")
    click(inWin(set, "Check"))
    check(waitFor(set.body, "2 files to update"), "the updater spots a changed and a missing file")
    click(inWin(set, "Download"))
    check(waitFor(set.body, "Restart to finish") and fs.exists("/.nimbus/update.ready"), "and stages the download for the next boot")
    check(not fs.exists("/nimbus/apps/worm/app.json"), "without touching the installed files yet")
  end

  -- lock
  nimbus.session.lock()
  tick()
  check(find(screen, "Locked") and not find(screen, "Accounts"), "the lock screen covers the desktop")
  typed("nope")
  enter()
  check(find(screen, "Wrong password"), "a wrong password stays locked")
  os.queueEvent("key", keys.leftCtrl)
  ev("key", keys.tab)
  ev("key_up", keys.leftCtrl)
  ev("terminate")
  check(wm.focused() == set, "shortcuts and Ctrl+T are blocked while locked")
  typed("secret")
  enter()
  check(not find(screen, "Locked"), "the right password unlocks")

  -- sign out, sign in as the standard user
  nimbus.session.signOut()
  tick()
  check(#wm.wins == 0 and find(screen, "Sign in") and find(screen, " kid ") and find(screen, " tester "),
    "sign out closes every program and offers each account")
  typed("kidpw")
  enter()
  check(nimbus.home == "/home/kid" and fs.isDir("/home/kid/Desktop"), "a standard user signs in to their own home")
  check(fs.open("/startup.lua", "w") == nil and fs.isReadOnly("/nimbus/init.lua"), "standard users can't write system files")
  check(not pcall(fs.delete, "/home/tester/Desktop/Files.lnk") and fs.exists("/home/tester/Desktop/Files.lnk"),
    "or another user's home")
  fs.open("/home/kid/nimbus_test.txt", "w").close()
  check(fs.exists("/home/kid/nimbus_test.txt"), "but can write in their own")
  check(nimbus.users.add("evil", "x", true) == false and nimbus.users.setAdmin("kid", true) == false,
    "and can't make themselves admin")
end

-- Runs the bootloader, picks plain CraftOS and answers the admin prompt.
-- Returns true if the bootloader let it through (it returns instead of starting Nimbus).
local function boot(name, pw)
  local through = false
  parallel.waitForAny(function()
    shell.run(proj .. "/startup.lua")
    through = true
  end, function()
    tick(2)
    typed("3")
    typed(name)
    enter()
    typed(pw)
    enter()
    tick(3)
  end)
  return through
end

local native = term.redirect(screen)
if os.getComputerID() ~= 0 then return peer() end
local ok, err
parallel.waitForAny(function() shell.run("/nimbus/init.lua") end, function() ok, err = pcall(test) end)
if ok then
  ok, err = pcall(function()
    nimbus.users.logout() -- this run never rebooted: without it the last user's file guard would still apply
    check(boot("tester", "secret"), "the bootloader lets an admin reach CraftOS")
    if proj ~= "" then
      local function read(path)
        local f = fs.open(path, "rb")
        local body = f.readAll()
        f.close()
        return body
      end
      check(read("/nimbus/apps/calculator/main.lua") == read(proj .. "/nimbus/apps/calculator/main.lua")
        and fs.exists("/nimbus/apps/worm/app.json") and not fs.exists("/.nimbus/update.ready"),
        "the bootloader installs the staged update")
    end
    check(not boot("kid", "kidpw") and find(screen, "Access denied"), "and refuses a standard user")
  end)
end
term.redirect(native)

for _, line in ipairs(results) do print(line) end
if ok then
  print("ACCEPTANCE PASSED (" .. #results .. " checks)")
else
  printError(err or "Nimbus exited before the test finished")
  for y = 1, 19 do print((screen.getLine(y):gsub("[^\32-\126]", "?"))) end -- what was on screen
end
if args[1] == "--shutdown" then os.shutdown() end -- for headless emulator runs
