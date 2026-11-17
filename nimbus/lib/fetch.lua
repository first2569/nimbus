-- Reads <base>/<path>, where base is an http(s) URL or a local folder (a disk, a test fixture).
-- Returns the raw bytes, or nil and a reason.
return function(base, path)
  if not base then return nil, "No source set. Run: set nimbus.repo <url>" end
  if base:match("^https?://") then
    if not http then return nil, "HTTP is disabled on this server" end
    local res, err = http.get(base .. "/" .. path, nil, true)
    if not res then return nil, tostring(err) end
    local body = res.readAll() or ""
    res.close()
    return body
  end
  local f = fs.open(fs.combine(base, path), "rb")
  if not f then return nil, "Not found: " .. path end
  local body = f.readAll() or ""
  f.close()
  return body
end
