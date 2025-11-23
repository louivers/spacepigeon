local spaces = require("hs.spaces")
local screen = hs.screen.mainScreen()

-- Make gotoSpace wait a bit longer internally (Mission Control)
hs.spaces.MCwaitTime = 1.0

local M = {}

-- All space IDs for the main screen
function M.getSpaces()
  return spaces.spacesForScreen(screen) or {}
end

-- Ensure we have EXACTLY n spaces
function M.ensureExactSpaces(n)
  local maxTries = 40

  -- Ensure at least n
  local tries = 0
  local s = M.getSpaces()
  while #s < n and tries < maxTries do
    spaces.addSpaceToScreen(screen)
    hs.timer.usleep(600000) -- 0.6s
    s = M.getSpaces()
    tries = tries + 1
  end

  if #s < n then
    hs.alert.show("Could not create enough spaces (have " .. #s .. ", need " .. n .. ")")
    return false
  end

  -- Remove extras from the end
  s = M.getSpaces()
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
  s = M.getSpaces()
  while #s > n and tries < maxTries do
    local lastSpaceId = s[#s]
    if lastSpaceId then
      spaces.removeSpace(lastSpaceId)
      hs.timer.usleep(800000)
    end
    s = M.getSpaces()
    tries = tries + 1
  end

  if #s ~= n then
    hs.alert.show("Could not enforce exact space count (have " .. #s .. ", need " .. n .. ")")
    return false
  end

  return true
end

-- Switch to a space and block until it's definitely active
function M.gotoSpaceAndWait(spaceId)
  spaces.gotoSpace(spaceId)

  local tries    = 0
  local maxTries = 50

  while spaces.activeSpaceOnScreen(screen) ~= spaceId and tries < maxTries do
    hs.timer.usleep(100000) -- 0.1s
    tries = tries + 1
  end
end

return M
