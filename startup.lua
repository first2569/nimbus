-- Nimbus bootloader. Press 2 within two seconds for safe mode, 3 for plain CraftOS.
-- Once accounts exist, both ask for an admin's password.
local pullEvent = os.pullEvent
os.pullEvent = os.pullEventRaw -- Ctrl+T in here would otherwise drop straight to a shell

term.clear()
term.setCursorPos(1, 1)

-- Install an update the updater finished downloading. Safe to repeat if power is lost half way.
local READY, STAGE = "/.nimbus/update.ready", "/.nimbus/update/"
if fs.exists(READY) then
  local f = fs.open(READY, "r")
  local files = textutils.unserialize(f.readAll()) or {}
  f.close()
  for _, path in ipairs(files) do
    if fs.exists(STAGE .. path) then
      fs.delete(path)
      fs.move(STAGE .. path, path)
    end
  end
  fs.delete(READY)
  fs.delete(STAGE)
  print("Nimbus was updated (" .. #files .. " files).")
end

print("Nimbus  [1] Start  [2] Safe mode  [3] CraftOS")
local pick, timer = "1", os.startTimer(2)
while true do
  local e, a = os.pullEvent()
  if e == "timer" and a == timer then break end
  if e == "char" and (a == "1" or a == "2" or a == "3") then pick = a break end
end

if pick ~= "1" then
  package.path = "/nimbus/?.lua;" .. package.path
  local ok, users = pcall(require, "lib.users")
  if ok and #users.list() > 0 then -- a broken install still lets you in to repair it
    write("Admin name: ")
    local name = read()
    write("Password: ")
    local pw = read("*")
    local admin = false
    for _, u in ipairs(users.list()) do
      if u.name == name and u.admin then admin = true end
    end
    if not (admin and users.check(name, pw)) then
      print("Access denied. Starting Nimbus.")
      sleep(1)
      pick = "1"
    end
  end
end

os.pullEvent = pullEvent
if pick == "1" then
  shell.run("/nimbus/init.lua")
elseif pick == "2" then
  shell.run("/nimbus/recovery.lua")
end
