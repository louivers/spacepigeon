local spaces = require("hs.spaces")

-- Make gotoSpace wait a bit longer internally (Mission Control)
hs.spaces.MCwaitTime = 1.0

local M = {}

-- Helper to get screens in a consistent order (Primary first, then left-to-right)
local function getOrderedScreens()
  local primary = hs.screen.primaryScreen()
  local all = hs.screen.allScreens()
  local others = {}
  
  for _, s in ipairs(all) do
    if s:id() ~= primary:id() then
      table.insert(others, s)
    end
  end
  
  -- Sort others by x position
  table.sort(others, function(a, b)
    return a:frame().x < b:frame().x
  end)
  
  local result = { primary }
  for _, s in ipairs(others) do
    table.insert(result, s)
  end
  
  return result
end

-- All space IDs for all screens, ordered by screen then space index
-- (Main Monitor spaces first, then Second Monitor spaces, etc.)
function M.getSpaces()
  local screens = getOrderedScreens()
  local allSpaces = {}
  
  for _, s in ipairs(screens) do
    local screenSpaces = spaces.spacesForScreen(s) or {}
    for _, spaceId in ipairs(screenSpaces) do
      table.insert(allSpaces, spaceId)
    end
  end
  
  return allSpaces
end

-- Ensure we have EXACTLY n spaces on the MAIN (Primary) screen only.
-- We do not touch spaces on secondary monitors as they are difficult to manage.
function M.ensureMainSpaces(n)
  local screen = hs.screen.primaryScreen()
  local maxTries = 40
  
  local function getMySpaces()
    return spaces.spacesForScreen(screen) or {}
  end

  -- Ensure at least n
  local tries = 0
  local s = getMySpaces()
  while #s < n and tries < maxTries do
    spaces.addSpaceToScreen(screen)
    hs.timer.usleep(600000) -- 0.6s
    s = getMySpaces()
    tries = tries + 1
  end

  if #s < n then
    hs.alert.show("Could not create enough spaces on main screen (have " .. #s .. ", need " .. n .. ")")
    return false
  end

  -- Remove extras from the end
  s = getMySpaces()
  local numToRemove = #s - n

  if numToRemove > 0 then
    local oldWait = hs.spaces.MCwaitTime
    hs.spaces.MCwaitTime = 0.4

    -- Open MC once (implicitly by first removeSpace) and keep it open
    for i = 0, numToRemove - 1 do
      local spaceIdToRemove = s[#s - i]
      if spaceIdToRemove then
        spaces.removeSpace(spaceIdToRemove, false)
        hs.timer.usleep(200000) -- 0.2s
      end
    end

    spaces.closeMissionControl()
    hs.spaces.MCwaitTime = oldWait
    hs.timer.usleep(500000)
  end

  -- Final verification (clean up any stragglers)
  tries = 0
  s = getMySpaces()
  while #s > n and tries < maxTries do
    local lastSpaceId = s[#s]
    if lastSpaceId then
      spaces.removeSpace(lastSpaceId)
      hs.timer.usleep(800000)
    end
    s = getMySpaces()
    tries = tries + 1
  end

  if #s ~= n then
    hs.alert.show("Could not enforce exact space count on main screen (have " .. #s .. ", need " .. n .. ")")
    return false
  end

  return true
end

-- Helper to find which screen a space belongs to
function M.getScreenForSpace(spaceId)
  for _, s in ipairs(hs.screen.allScreens()) do
    local screenSpaces = spaces.spacesForScreen(s) or {}
    for _, sid in ipairs(screenSpaces) do
      if sid == spaceId then
        return s
      end
    end
  end
  return nil
end

-- Switch to a space and block until it's definitely active
function M.gotoSpaceAndWait(spaceId)
  spaces.gotoSpace(spaceId)
  
  local targetScreen = M.getScreenForSpace(spaceId)
  if not targetScreen then
    -- Fallback: just wait a bit if we can't verify
    hs.timer.usleep(500000)
    return
  end

  local tries    = 0
  local maxTries = 50

  while spaces.activeSpaceOnScreen(targetScreen) ~= spaceId and tries < maxTries do
    hs.timer.usleep(100000) -- 0.1s
    tries = tries + 1
  end
end

return M
