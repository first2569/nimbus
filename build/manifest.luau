-- Writes build/manifest.json: the version and a SHA-256 for every file the updater manages.
-- Run from the project root after changing anything in nimbus/ or startup.lua:
--   lune run build/manifest.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local sha256 = luau.load(fs.readFile("nimbus/lib/sha256.lua"), { debugName = "sha256" })()

local paths = { "startup.lua" }
local function walk(dir)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then walk(path) else table.insert(paths, path) end
	end
end
walk("nimbus")
table.sort(paths) -- stable order, so the file only changes when a hash does

local version = assert(fs.readFile("nimbus/init.lua"):match('version = "([^"]+)"'), "no version in nimbus/init.lua")
local lines, size = {}, 0
for i, path in paths do
	local body = fs.readFile(path)
	size += #body
	assert(not body:find("\r"), path .. " has CRLF line endings; GitHub would serve it with different bytes")
	lines[i] = `    "{path}": "{sha256(body)}"`
end
fs.writeFile("build/manifest.json", `\{\n  "version": "{version}",\n  "size": {size},\n  "files": \{\n{table.concat(lines, ",\n")}\n  }\n}\n`)
print(`manifest: version {version}, {#paths} files`)
