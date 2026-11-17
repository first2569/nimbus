-- Installer test for CraftOS-PC: runs both installers on an empty computer.
-- tests/run.sh starts it with the repo mounted read-only at /proj.
local results = {}

local function check(cond, what)
  if not cond then error("FAIL: " .. what, 0) end
  results[#results + 1] = "ok   " .. what
end

local function read(path)
  local f = fs.open(path, "rb")
  if not f then return nil end
  local body = f.readAll()
  f.close()
  return body
end

-- True when every file in the manifest is on disk and identical to the repo's.
local function installed()
  local manifest = textutils.unserializeJSON(read("/proj/build/manifest.json"))
  for path in pairs(manifest.files) do
    if read("/" .. path) ~= read("/proj/" .. path) then return false end
  end
  return true
end

-- Runs a program and answers its "Restart now?" with n.
local function run(...)
  local args, ok = { ... }, nil
  parallel.waitForAny(function() ok = shell.run(table.unpack(args)) end, function()
    while true do
      sleep(0.3)
      os.queueEvent("char", "n")
      os.queueEvent("key", keys.enter)
    end
  end)
  return ok
end

local ok, err = pcall(function()
  check(not fs.exists("/nimbus") and not fs.exists("/startup.lua"), "the computer starts empty")
  check(not run("/proj/install.lua", "/nowhere") and not fs.exists("/nimbus") and not fs.exists("/startup.lua"),
    "a download that fails installs nothing")
  check(not run("/proj/install.lua", "not a repo"), "a malformed repository name is refused")
  check(run("/proj/install.lua", "/proj"), "the online installer runs (from a folder source)")
  check(installed(), "every installed file matches the manifest")
  check(settings.get("nimbus.repo") == "/proj", "the source is remembered for updates and the Store")
  check(loadfile("/startup.lua") and loadfile("/nimbus/init.lua"), "the installed system compiles")

  fs.delete("/nimbus")
  fs.delete("/startup.lua")
  fs.copy("/proj/dist/nimbus-setup.lua", "/setup.lua")
  check(run("/setup.lua"), "the offline bundle runs")
  check(installed(), "it unpacks every file, identical to the repo")
  check(not fs.exists("/setup.lua"), "and removes itself afterwards")
end)

for _, line in ipairs(results) do print(line) end
if ok then print("INSTALL PASSED (" .. #results .. " checks)") else printError(err) end
os.shutdown()
