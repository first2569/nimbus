-- Nimbus scheduler: one coroutine per process, each drawing into its own terminal.
local sched = { procs = {}, resumes = 0 }
local nextPid = 1

-- Creates a process but does not run it; the caller resumes it once it is wired up.
function sched.spawn(name, target, fn)
  local p = { pid = nextPid, name = name, term = target, co = coroutine.create(fn), resumes = 0 }
  nextPid = nextPid + 1
  sched.procs[#sched.procs + 1] = p
  return p
end

-- Hands one event to a process if it is waiting for it (same filter rule as multishell).
function sched.resume(p, event, ...)
  if p.dead or coroutine.status(p.co) ~= "suspended" then return end
  if p.filter ~= nil and p.filter ~= event and event ~= "terminate" then return end
  local prevTerm, prevProc = term.redirect(p.term), sched.current
  sched.current = p
  local ok, res = coroutine.resume(p.co, event, ...)
  sched.current = prevProc
  p.term = term.redirect(prevTerm) -- keep whatever the program redirected to
  p.resumes = p.resumes + 1
  sched.resumes = sched.resumes + 1
  if coroutine.status(p.co) == "dead" then
    p.dead = true
    if not ok then p.err = res end
  else
    p.filter = res
  end
end

function sched.broadcast(...)
  for i = 1, #sched.procs do sched.resume(sched.procs[i], ...) end
end

function sched.reap()
  for i = #sched.procs, 1, -1 do
    if sched.procs[i].dead then table.remove(sched.procs, i) end
  end
end

return sched
