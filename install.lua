-- Nimbus online installer. On an advanced computer:
--   wget run https://raw.githubusercontent.com/OWNER/NAME/main/install.lua OWNER/NAME
-- The argument is where to download from: a GitHub "owner/name" (or "owner/name@branch"),
-- a full URL, or a local folder such as /disk. It is remembered as the source for updates
-- and the Store. Nothing is written until every file has arrived and passed its checksum.
local source = ...
if not source then
  print("Usage: install <owner/name | url | folder>")
  return
end

local base = source
if not source:match("^https?://") and source:sub(1, 1) ~= "/" then
  local repo, branch = source:match("^([%w_.-]+/[%w_.-]+)@?([%w_./-]*)$")
  if not repo then error("Not a GitHub repository: " .. source, 0) end
  base = "https://raw.githubusercontent.com/" .. repo .. "/" .. (branch ~= "" and branch or "main")
end

local function fetch(path)
  if base:sub(1, 1) == "/" then
    local f = fs.open(fs.combine(base, path), "rb")
    if not f then error("Not found: " .. fs.combine(base, path), 0) end
    local body = f.readAll() or ""
    f.close()
    return body
  end
  if not http then error("HTTP is disabled on this server. Use the offline installer instead.", 0) end
  local res, err = http.get(base .. "/" .. path, nil, true)
  if not res then error("Could not download " .. path .. ": " .. tostring(err), 0) end
  local body = res.readAll() or ""
  res.close()
  return body
end

local manifest = textutils.unserializeJSON(fetch("build/manifest.json"))
if type(manifest) ~= "table" or type(manifest.files) ~= "table" then error("The manifest is not valid", 0) end
local free = fs.getFreeSpace("/")
if type(free) == "number" and type(manifest.size) == "number" and manifest.size > free then
  error(("Not enough space: Nimbus needs %d KB and %d KB is free"):format(manifest.size / 1024, free / 1024), 0)
end

local paths = {}
for path in pairs(manifest.files) do
  -- the manifest is downloaded: only let it name Nimbus's own files
  if path ~= "startup.lua" and not (path:match("^nimbus/[%w_%-%./]+$") and not path:find("..", 1, true)) then
    error("The manifest names a file outside Nimbus: " .. path, 0)
  end
  paths[#paths + 1] = path
end
table.sort(paths)

-- The checksum code is fetched first; it then checks every file, itself included.
local sha256 = (loadstring or load)(fetch("nimbus/lib/sha256.lua"), "sha256")()

print("Installing Nimbus " .. tostring(manifest.version))
local width = term.getSize() - 2
local _, row = term.getCursorPos()
local bodies = {}
for i, path in ipairs(paths) do
  local body = fetch(path)
  if sha256(body) ~= manifest.files[path] then error("Checksum mismatch: " .. path, 0) end
  bodies[path] = body
  local filled = math.floor(i / #paths * width)
  term.setCursorPos(1, row)
  term.write("[" .. ("="):rep(filled) .. (" "):rep(width - filled) .. "]")
  sleep(0) -- hashing is slow: yield so the computer isn't stopped for hogging
end
print()

for _, path in ipairs(paths) do
  local f, err = fs.open(path, "wb")
  if not f then error("Could not write " .. path .. ": " .. tostring(err), 0) end
  f.write(bodies[path])
  f.close()
end
settings.set("nimbus.repo", base)
settings.save()

print("Nimbus is installed.")
write("Restart now? (y/n) ")
if read():lower() ~= "n" then os.reboot() end
