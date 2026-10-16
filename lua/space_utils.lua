local spaces = require("hs.spaces")
local helper = require("lua.helper")
local log = require("lua.log")

-- How long hs.spaces waits for Mission Control to open before it removes a
-- desktop. removeDesktops() lowers it while Mission Control is already open.
local MC_WAIT_FIRST = 0.8
local MC_WAIT_OPEN = 0.15
local MC_WAIT_RETRY = 1.2
hs.spaces.MCwaitTime = MC_WAIT_FIRST

local M = {}

-- Small sleep that keeps Hammerspoon responsive when called from a coroutine
-- (the whole workspace setup runs in one), and blocks otherwise.
function M.sleep(seconds)
  if coroutine.isyieldable() and coroutine.applicationYield then
    coroutine.applicationYield(seconds)
  else
    hs.timer.usleep(math.floor(seconds * 1000000))
  end
end

-- Waits until fn() returns a truthy value or the timeout passes.
function M.waitFor(fn, timeout, interval)
  interval = interval or 0.1
  local deadline = hs.timer.secondsSinceEpoch() + (timeout or 3)
  repeat
    local value = fn()
    if value then return value end
    M.sleep(interval)
  until hs.timer.secondsSinceEpoch() > deadline
  return fn()
end

-- Primary screen first, then the others from left to right.
function M.getOrderedScreens()
  local primary = hs.screen.primaryScreen()
  local others = {}

  for _, s in ipairs(hs.screen.allScreens()) do
    if s:id() ~= primary:id() then
      table.insert(others, s)
    end
  end

  table.sort(others, function(a, b)
    return a:frame().x < b:frame().x
  end)

  local result = { primary }
  for _, s in ipairs(others) do
    table.insert(result, s)
  end
  return result
end

-- Monitor number in the config: "main" (or nil) is 1, "secondary" is 2, and
-- monitors 3 to 10 are their number ("3" or 3).
function M.monitorIndex(monitor)
  if monitor == nil or monitor == "main" then return 1 end
  if monitor == "secondary" then return 2 end
  local n = math.tointeger(tonumber(monitor))
  if n and n >= 1 then return n end
  return 1
end

-- The screen for a monitor in the config, or nil when it is not connected.
function M.screenForMonitor(monitorType)
  return M.getOrderedScreens()[M.monitorIndex(monitorType)]
end

-- Normal desktops only. Fullscreen app Spaces are left out, so "space 2" in
-- the config always means the second desktop, whatever fullscreen apps exist.
function M.userSpacesForScreen(screen)
  local result = {}
  if not screen then return result end
  for _, sid in ipairs(spaces.spacesForScreen(screen) or {}) do
    if spaces.spaceType(sid) == "user" then
      table.insert(result, sid)
    end
  end
  return result
end

-- Fullscreen app Spaces on a screen, left to right.
function M.fullscreenSpacesForScreen(screen)
  local result = {}
  if not screen then return result end
  for _, sid in ipairs(spaces.spacesForScreen(screen) or {}) do
    if spaces.spaceType(sid) == "fullscreen" then
      table.insert(result, sid)
    end
  end
  return result
end

function M.getSpacesForMonitor(monitorType)
  return M.userSpacesForScreen(M.screenForMonitor(monitorType))
end

function M.getSpaces()
  local all = {}
  for _, s in ipairs(M.getOrderedScreens()) do
    for _, sid in ipairs(M.userSpacesForScreen(s)) do
      table.insert(all, sid)
    end
  end
  return all
end

function M.getScreenForSpace(spaceId)
  for _, s in ipairs(hs.screen.allScreens()) do
    for _, sid in ipairs(spaces.spacesForScreen(s) or {}) do
      if sid == spaceId then
        return s
      end
    end
  end
  return nil
end

local function ensureSpacesForScreen(screen, n)
  if not screen then return false end

  local maxTries = 40
  local function mySpaces()
    return M.userSpacesForScreen(screen)
  end

  local tries = 0
  local s = mySpaces()
  while #s < n and tries < maxTries do
    spaces.addSpaceToScreen(screen)
    M.sleep(0.6)
    s = mySpaces()
    tries = tries + 1
  end

  if #s < n then
    hs.alert.show("Could not create enough spaces (have " .. #s .. ", need " .. n .. ")")
    return false
  end

  -- Remove extra desktops from the end. Windows on a removed desktop are
  -- moved by macOS to another desktop; the layout step places them after.
  tries = 0
  s = mySpaces()
  local removed = false
  while #s > n and tries < maxTries do
    spaces.removeSpace(s[#s], false)
    removed = true
    M.sleep(0.4)
    s = mySpaces()
    tries = tries + 1
  end
  if removed then
    spaces.closeMissionControl()
    M.sleep(0.5)
  end

  s = mySpaces()
  if #s ~= n then
    hs.alert.show("Could not enforce exact space count (have " .. #s .. ", need " .. n .. ")")
    return false
  end
  return true
end

function M.ensureSpaces(monitorType, n)
  local screen = M.screenForMonitor(monitorType)

  if not screen then
    if M.monitorIndex(monitorType) > 1 and n == 0 then
      return true
    end
    hs.alert.show("Monitor " .. monitorType .. " not found")
    return false
  end

  return ensureSpacesForScreen(screen, n)
end

function M.ensureMainSpaces(n)
  return M.ensureSpaces("main", n)
end

-- Switches to a Space and waits until it is active. Uses the helper's
-- instant switch first and Mission Control only when that fails.
function M.gotoSpaceAndWait(spaceId)
  local screen = M.getScreenForSpace(spaceId)
  local function arrived()
    return screen and spaces.activeSpaceOnScreen(screen) == spaceId
  end

  if arrived() then return true end

  local started = log.clock()
  if helper.canFocus() then
    -- The swipe is sometimes ignored, for example while an app is still
    -- animating into fullscreen. One quick retry is much cheaper than
    -- falling back to Mission Control.
    for attempt = 1, 2 do
      if helper.focusSpace(spaceId, attempt == 1 and 800 or 1200, attempt == 1) and M.waitFor(arrived, 0.5, 0.05) then
        log.debug("Switched to space " .. spaceId, {
          via = "helper", attempt = attempt, ms = math.floor(log.since(started)),
        })
        return true
      end
      if attempt == 1 then M.sleep(0.3) end
    end
    log.warn("Instant switch to space " .. spaceId .. " failed twice; using Mission Control")
  else
    log.debug("Switching to space " .. spaceId .. " via Mission Control (no helper)")
  end
  spaces.gotoSpace(spaceId)
  if not screen then
    M.sleep(0.5)
    return false
  end
  local ok = M.waitFor(arrived, 5, 0.1) and true or false
  if ok then
    log.info("Switched to space " .. spaceId .. " via Mission Control", { ms = math.floor(log.since(started)) })
  else
    log.error("Could not switch to space " .. spaceId)
  end
  return ok
end

-- Adds a desktop at the end of a screen's Spaces (Mission Control "+").
-- Returns the new space id, or nil.
function M.addDesktop(screen)
  local before = {}
  for _, sid in ipairs(M.userSpacesForScreen(screen)) do before[sid] = true end

  local done = log.step("Add desktop")
  local function newDesktop()
    for _, sid in ipairs(M.userSpacesForScreen(screen)) do
      if not before[sid] then return sid end
    end
    return nil
  end
  -- hs.spaces.addSpaceToScreen can throw, and returns false when Mission
  -- Control did not open in time (seen right after an app animated into
  -- fullscreen). So: protected call, and one retry after a short pause.
  local function try()
    local called, ok, err = pcall(spaces.addSpaceToScreen, screen, true)
    if not called then return false, ok end
    return ok, err
  end

  -- The result is judged by whether a new desktop shows up; a false return
  -- only shortens the wait.
  local ok, err = try()
  local newId = M.waitFor(newDesktop, ok and 1.5 or 0.3, 0.05)
  if not newId then
    log.debug("Adding a desktop did not work; trying again", { error = tostring(err) })
    spaces.closeMissionControl()
    M.sleep(0.6)
    ok, err = try()
    newId = M.waitFor(newDesktop, ok and 2 or 0.5, 0.05)
  end

  if newId then
    local all = spaces.spacesForScreen(screen) or {}
    local pos
    for i, sid in ipairs(all) do if sid == newId then pos = i end end
    done("Added desktop " .. newId, { position = pos, of = #all })
  else
    done("Could not add a desktop", { error = tostring(err) }, "error")
  end
  return newId
end

-- Removes desktops (Mission Control). Windows on them are moved by macOS to
-- another desktop; the layout step places them afterwards.
function M.removeDesktops(spaceIds)
  if #spaceIds == 0 then return true end
  local done = log.step("Remove desktops")
  local failed = {}

  local function gone(sid)
    return M.getScreenForSpace(sid) == nil
  end

  for i, sid in ipairs(spaceIds) do
    local started = log.clock()
    -- The first removal waits for Mission Control to open; after that it is
    -- already open, so only a short wait is needed.
    hs.spaces.MCwaitTime = (i == 1) and MC_WAIT_FIRST or MC_WAIT_OPEN
    -- hs.spaces.removeSpace can throw (not just return false) when Mission
    -- Control is not fully drawn yet, so it is always called through pcall.
    local function try()
      local called, ok, err = pcall(spaces.removeSpace, sid, false)
      if not called then return false, ok end
      return ok, err
    end
    local ok, err = try()
    if not ok then
      log.debug("Removing desktop " .. sid .. " failed; trying again", { error = tostring(err) })
      M.sleep(0.4)
      hs.spaces.MCwaitTime = MC_WAIT_RETRY
      ok, err = try()
    end
    local confirmed = ok and M.waitFor(function() return gone(sid) end, 1.5, 0.05)
    if ok and confirmed then
      log.debug("Removed desktop " .. sid, { ms = math.floor(log.since(started)) })
    else
      table.insert(failed, tostring(sid) .. ": " .. tostring(err or "still there"))
    end
  end
  hs.spaces.MCwaitTime = MC_WAIT_FIRST
  spaces.closeMissionControl()
  M.sleep(0.3)

  if #failed > 0 then
    done("Removed " .. (#spaceIds - #failed) .. " of " .. #spaceIds .. " desktops", { failed = failed }, "warn")
    return false
  end
  done("Removed " .. #spaceIds .. " desktop(s)", { spaces = spaceIds })
  return true
end

return M
