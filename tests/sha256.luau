-- SHA-256 against the NIST example vectors.  lune run tests/sha256.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local sha256 = luau.load(fs.readFile("nimbus/lib/sha256.lua"), { debugName = "sha256" })()

local vectors = {
	[""] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
	["abc"] = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
	["abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"] = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
	[string.rep("a", 1000)] = "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
}
for input, want in vectors do
	local got = sha256(input)
	assert(got == want, `sha256 of {#input} bytes: got {got}, want {want}`)
end
print("sha256: 4 vectors match")
