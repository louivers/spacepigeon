-- Structured log for SpacePigeon.
--
-- Every line of ~/.hammerspoon/spacepigeon.log is one JSON object:
--   ts    seconds since epoch (with milliseconds)
--   run   id of the workspace run this belongs to ("app" outside a run)
--   lvl   "debug", "info", "warn" or "error"
--   ev    "log", "step", "run_start" or "run_end"
--   msg   human readable message
--   ms    duration in milliseconds (steps and run_end)
--   step  step name (steps)
--   data  extra details (table)
-- The SpacePigeon app's log window reads this file. Lines are also printed
-- to the Hammerspoon Console.

local M = {}

local profileOk, profile = pcall(require, "lua.profile")
M.path = ((profileOk and profile.dir) or hs.configdir) .. "/spacepigeon.log"

local MAX_BYTES = 2 * 1024 * 1024
local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

local runId = nil
local runName = nil
local runStarted = nil
local worst = "info"
local counts = { warn = 0, error = 0 }

local function now()
  return hs.timer.secondsSinceEpoch()
end

local function rotateIfNeeded()
  local attr = hs.fs.attributes(M.path)
  if attr and attr.size and attr.size > MAX_BYTES then
    os.remove(M.path .. ".1")
    os.rename(M.path, M.path .. ".1")
  end
end

local function write(entry)
  entry.ts = entry.ts or now()
  entry.run = entry.run or runId or "app"
  entry.lvl = entry.lvl or "info"
  entry.ev = entry.ev or "log"

  if runId and LEVELS[entry.lvl] and LEVELS[entry.lvl] > LEVELS[worst] then
    worst = entry.lvl
  end
  if counts[entry.lvl] then
    counts[entry.lvl] = counts[entry.lvl] + 1
  end

  local ok, line = pcall(hs.json.encode, entry)
  if ok and line then
    local f = io.open(M.path, "a")
    if f then
      f:write(line, "\n")
      f:close()
    end
  end

  local suffix = entry.ms and string.format(" (%d ms)", math.floor(entry.ms + 0.5)) or ""
  print(string.format("SpacePigeon %-5s %s%s", entry.lvl, entry.msg or "", suffix))
end

local function logAt(level)
  return function(msg, data)
    write({ lvl = level, msg = msg, data = data })
  end
end

M.debug = logAt("debug")
M.info = logAt("info")
M.warn = logAt("warn")
M.error = logAt("error")

-- Starts a step and returns a function that ends it:
--   local done = log.step("Quit other apps")
--   ...
--   done("Quit 3 apps", { apps = names })      -- logged with its duration
--   done("Gave up", nil, "warn")               -- optional level
function M.step(name)
  local started = now()
  return function(msg, data, level)
    write({
      ev = "step",
      step = name,
      lvl = level or "info",
      msg = msg or name,
      ms = (now() - started) * 1000,
      data = data,
    })
  end
end

-- Milliseconds since `since` (a value from M.clock()).
function M.clock()
  return now()
end

function M.since(since)
  return (now() - since) * 1000
end

function M.startRun(name, data)
  rotateIfNeeded()
  runId = os.date("%Y%m%d-%H%M%S") .. string.format("-%03d", math.random(0, 999))
  runName = name
  runStarted = now()
  worst = "info"
  counts = { warn = 0, error = 0 }
  write({ ev = "run_start", msg = "Workspace \"" .. name .. "\" started", name = name, data = data })
  return runId
end

function M.endRun(msg, data)
  if not runId then return end
  local level = worst
  write({
    ev = "run_end",
    lvl = level,
    msg = msg or ("Workspace \"" .. tostring(runName) .. "\" finished"),
    ms = (now() - runStarted) * 1000,
    data = data,
  })
  runId, runName, runStarted = nil, nil, nil
end

function M.inRun()
  return runId ~= nil
end

function M.counts()
  return { warn = counts.warn, error = counts.error }
end

return M
