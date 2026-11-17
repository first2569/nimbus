-- Updater: compares every file with the SHA-256 in <repo>/build/manifest.json, downloads the
-- ones that differ into a staging folder, and leaves a marker. The bootloader moves them into
-- place on the next boot, so a download that fails half way changes nothing.
-- shortcut: files that were removed upstream are not deleted here; add that when one matters.
local sha256 = require("lib.sha256")
local fetch = require("lib.fetch")

local update = {}
local STAGE, READY = "/.nimbus/update", "/.nimbus/update.ready"

local function managed(path) -- the manifest is downloaded, so its paths are checked before use
  return type(path) == "string" and not path:find("..", 1, true)
    and (path == "startup.lua" or path:match("^nimbus/[%w_%-%./]+$") ~= nil)
end

-- Returns { version, files = { paths that differ }, hashes }, or nil and a reason.
function update.check()
  local repo = settings.get("nimbus.repo")
  local body, err = fetch(repo, "build/manifest.json")
  local manifest = body and textutils.unserializeJSON(body)
  if not manifest or type(manifest.files) ~= "table" then return nil, err or "The manifest is not valid" end
  local changed = {}
  for path, hash in pairs(manifest.files) do
    if not managed(path) then return nil, "The manifest names a file outside Nimbus" end
    local f = fs.open(path, "rb")
    local have = f and sha256(f.readAll() or "")
    if f then f.close() end
    if have ~= hash then changed[#changed + 1] = path end
    sleep(0) -- hashing is slow: yield between files so the computer isn't killed for hogging
  end
  table.sort(changed)
  return { version = manifest.version, files = changed, hashes = manifest.files }
end

-- Downloads what check() found. Returns true, or false and a reason (nothing is staged then).
function update.download(result)
  local repo = settings.get("nimbus.repo")
  local ok, err = pcall(function()
    fs.delete(READY)
    fs.delete(STAGE)
    for _, path in ipairs(result.files) do
      local body, why = fetch(repo, path)
      if not body then error(why, 0) end
      if sha256(body) ~= result.hashes[path] then error("Checksum mismatch: " .. path, 0) end
      local f, denied = fs.open(STAGE .. "/" .. path, "wb")
      if not f then error(denied, 0) end
      f.write(body)
      f.close()
      sleep(0)
    end
    local f = fs.open(READY, "w") -- written last: the bootloader only acts on a complete download
    f.write(textutils.serialize(result.files))
    f.close()
  end)
  if not ok then pcall(fs.delete, STAGE) end
  return ok, err
end

return update
