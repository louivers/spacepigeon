-- Bridge to the `spacectl` helper binary (installed at ~/.hammerspoon/bin/spacectl).
--
-- spacectl moves windows between Spaces and switches Spaces instantly, with
-- SIP enabled, using private macOS calls that work on macOS 26.4 and newer.
-- Every function here verifies the result and falls back to plain
-- Hammerspoon when the helper is missing or a call fails.

local log = require("lua.log")

local M = {}

M.path = hs.configdir .. "/bin/spacectl"

local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Runs spacectl with the given arguments. Returns ok, stdout, ms.
-- A quiet run logs a failure as debug instead of warn: for first tries that
-- have a planned retry.
local function exec(quiet, ...)
  local args = { ... }
  local parts = { shellQuote(M.path) }
  for _, a in ipairs(args) do
    table.insert(parts, shellQuote(a))
  end
  local started = log.clock()
  local output, ok = hs.execute(table.concat(parts, " ") .. " 2>&1")
  local ms = log.since(started)
  output = output or ""
  local what = "spacectl " .. table.concat(args, " ")
  if ok then
    log.debug(what, { ms = math.floor(ms + 0.5) })
  else
    local level = quiet and log.debug or log.warn
    level(what .. " failed" .. (quiet and " (will retry)" or ""), {
      ms = math.floor(ms + 0.5), output = (output:gsub("%s+$", "")),
    })
  end
  return ok == true, output, ms
end

local function run(...)
  return exec(false, ...)
end

local capabilities = nil

-- Returns a table like { move = true, focus = true, macos = "26.7.1" },
-- or an empty table when the helper is missing. Cached per Hammerspoon load.
function M.capabilities()
  if capabilities then return capabilities end
  capabilities = {}

  if not hs.fs.attributes(M.path) then
    log.warn("Helper not found at " .. M.path .. "; falling back to Mission Control and relaunching apps")
    return capabilities
  end

  local _, output = run("check")
  local decoded = hs.json.decode(output:match("{.*}") or "")
  if type(decoded) == "table" then
    capabilities = decoded
  else
    log.error("Helper check failed", { output = output })
  end
  return capabilities
end

function M.canMove()
  return M.capabilities().move == true
end

function M.canFocus()
  return M.capabilities().focus == true
end

-- Space ids a window is on, read from macOS (works for windows on any Space).
local function windowIsOnSpace(winId, spaceId)
  for _, sid in ipairs(hs.spaces.windowSpaces(winId) or {}) do
    if sid == spaceId then return true end
  end
  return false
end
M.windowIsOnSpace = windowIsOnSpace

-- Moves a window (hs.window or window id) to a desktop Space.
-- Returns true only when macOS reports the window on that Space.
-- opts.quiet: log a failure as debug (the caller retries).
-- opts.timeoutMs: how long spacectl waits for the move.
function M.moveWindowToSpace(win, spaceId, opts)
  opts = opts or {}
  local winId = type(win) == "number" and win or win:id()
  if not winId or not spaceId then return false end
  if windowIsOnSpace(winId, spaceId) then return true end

  if M.canMove() then
    local args = { "move", winId, spaceId }
    if opts.timeoutMs then table.insert(args, math.floor(opts.timeoutMs)) end
    local ok = exec(opts.quiet, table.unpack(args))
    -- The old Hammerspoon call below does nothing on macOS 15 and newer, so
    -- with a working helper it would only add a pointless wait.
    return ok
  end

  -- Old path: works on Sonoma and on Hammerspoon's own windows. It reports
  -- success even when nothing happens on Sequoia and newer, so verify.
  hs.spaces.moveWindowToSpace(winId, spaceId)
  for _ = 1, 8 do
    if windowIsOnSpace(winId, spaceId) then
      log.info("Moved window " .. winId .. " with the old Hammerspoon call")
      return true
    end
    hs.timer.usleep(100000)
  end
  log.warn("Window " .. winId .. " did not move to space " .. spaceId)
  return false
end

-- Switches to a Space without opening Mission Control.
-- Returns true when the switch was confirmed.
function M.focusSpace(spaceId, timeoutMs, quiet)
  if not M.canFocus() then return false end
  if timeoutMs then
    return (exec(quiet, "focus", spaceId, math.floor(timeoutMs)))
  end
  return (exec(quiet, "focus", spaceId))
end

local function decodeList(output)
  local decoded = hs.json.decode(output:match("%[.*%]") or "")
  return type(decoded) == "table" and decoded or {}
end

-- Windows of an app on any Space, front to back, as a list of
-- { id = <window id>, spaces = {...}, fullscreen = bool, x, y, w, h }.
-- Accessibility often cannot see windows on inactive Spaces; this can.
function M.windowsForApp(application)
  if not application or not M.canMove() then return {} end
  local ok, output = run("windows", application:pid())
  if not ok then return {} end
  return decodeList(output)
end

-- Every normal window on any Space, front to back, as a list of
-- { id, pid, spaces, fullscreen, x, y, w, h } (x and y from helper 1.2), or
-- nil when the helper is unavailable. One call, no Accessibility needed.
function M.allWindows()
  if not M.canMove() then return nil end
  local ok, output = run("windows")
  if not ok then return nil end
  return decodeList(output)
end

-- Set of process ids that own at least one normal window on any Space, or
-- nil when the helper is unavailable.
function M.pidsWithWindows()
  local list = M.allWindows()
  if not list then return nil end
  local pids = {}
  for _, w in ipairs(list) do
    if w.pid then pids[w.pid] = true end
  end
  return pids
end

return M
