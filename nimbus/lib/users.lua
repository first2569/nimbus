-- Accounts, the signed-in session, and the file guard for standard users.
-- Passwords are stored as sha256(salt .. password) in /.nimbus/users.db.
-- This is soft security: anyone with the world files, or the debug library, can get past it.
local sha256 = require("lib.sha256")

local users = {}
local DB = ".nimbus/users.db" -- outside /nimbus so the code tree can stay read-only and be replaced by updates
local raw = {} -- the unguarded fs functions; only this module keeps them
for k, v in pairs(fs) do raw[k] = v end

local db, session = {}, nil -- session is a local on purpose: programs can't sign themselves in by editing a table

local function save()
  local f = raw.open(DB, "w")
  f.write(textutils.serialize(db))
  f.close()
end

do
  local f = raw.open(DB, "r")
  if f then
    db = textutils.unserialize(f.readAll()) or {}
    f.close()
  end
end

local function admins()
  local n = 0
  for _, u in pairs(db) do
    if u.admin then n = n + 1 end
  end
  return n
end

-- Before any account exists (first-boot setup) everything is allowed.
local function isAdmin()
  return next(db) == nil or (session ~= nil and db[session] ~= nil and db[session].admin)
end

local function setPassword(u, pw)
  local salt = ""
  for _ = 1, 16 do salt = salt .. ("%x"):format(math.random(0, 15)) end
  u.salt, u.hash = salt, sha256(salt .. pw)
end

function users.list()
  local out = {}
  for name, u in pairs(db) do out[#out + 1] = { name = name, admin = u.admin } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function users.current()
  if session and db[session] then return { name = session, admin = db[session].admin } end
end

function users.check(name, pw)
  local u = db[name]
  return u ~= nil and sha256(u.salt .. pw) == u.hash
end

function users.login(name, pw)
  if not users.check(name, pw) then return false end
  session = name
  return true
end

function users.logout() session = nil end

function users.add(name, pw, admin)
  if not isAdmin() then return false, "Admins only" end
  if not name:match("^[%l%d_]+$") or #name > 12 then return false, "Name: 1-12 of a-z, 0-9, _" end
  if db[name] then return false, "That name is taken" end
  db[name] = { admin = admin and true or false }
  setPassword(db[name], pw)
  save()
  return true
end

function users.setPassword(name, pw)
  if not db[name] then return false, "No such user" end
  if not (isAdmin() or name == session) then return false, "Admins only" end
  setPassword(db[name], pw)
  save()
  return true
end

function users.setAdmin(name, admin)
  if not isAdmin() then return false, "Admins only" end
  if not db[name] then return false, "No such user" end
  if db[name].admin and not admin and admins() == 1 then return false, "There must be an admin" end
  db[name].admin = admin and true or false
  save()
  return true
end

-- Removes the account; the home folder is left alone.
function users.remove(name)
  if not isAdmin() then return false, "Admins only" end
  if not db[name] then return false, "No such user" end
  if name == session then return false, "You can't remove yourself" end
  db[name] = nil
  save()
  return true
end

-- True when the signed-in standard user may not write to this path.
local function denied(path)
  local user = session and db[session]
  if not user or user.admin then return false end
  -- lower-case: on a Windows-hosted server /NIMBUS is the same folder as /nimbus
  local top, second = raw.combine(path, ""):lower():match("^([^/]*)/?([^/]*)")
  return top == "nimbus" or top == ".nimbus" or top == ".settings" or top == "startup" or top == "startup.lua"
    or (top == "home" and second ~= session)
end

-- Replaces the global fs write functions, so every program (and io) goes through the guard.
function users.protect()
  fs.open = function(path, mode)
    if mode ~= "r" and mode ~= "rb" and denied(path) then return nil, "/" .. raw.combine(path, "") .. ": Access denied" end
    return raw.open(path, mode)
  end
  for name, checkFirst in pairs({ delete = true, makeDir = true, move = true, copy = false }) do
    fs[name] = function(a, b)
      if (checkFirst and denied(a)) or (b and denied(b)) then error("Access denied", 2) end
      return raw[name](a, b)
    end
  end
  fs.isReadOnly = function(path) return denied(path) or raw.isReadOnly(path) end
end

return users
