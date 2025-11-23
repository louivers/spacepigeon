-- === Workspace automation for PhD vs Chill ===

local spaces = require("hs.spaces")
local app    = require("hs.application")
local screen = hs.screen.mainScreen()

-- Make gotoSpace wait a bit longer internally (Mission Control)
hs.spaces.MCwaitTime = 1.0

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

-- All space IDs for the main screen
local function getSpaces()
  return spaces.spacesForScreen(screen) or {}
end

-- Ensure we have EXACTLY n spaces
local function ensureExactSpaces(n)
  local maxTries = 40

  -- Ensure at least n
  local tries = 0
  local s = getSpaces()
  while #s < n and tries < maxTries do
    spaces.addSpaceToScreen(screen)
    hs.timer.usleep(600000) -- 0.6s
    s = getSpaces()
    tries = tries + 1
  end

  if #s < n then
    hs.alert.show("Could not create enough spaces (have " .. #s .. ", need " .. n .. ")")
    return false
  end

  -- Remove extras from the end
  s = getSpaces()
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
  s = getSpaces()
  while #s > n and tries < maxTries do
    local lastSpaceId = s[#s]
    if lastSpaceId then
      spaces.removeSpace(lastSpaceId)
      hs.timer.usleep(800000)
    end
    s = getSpaces()
    tries = tries + 1
  end

  if #s ~= n then
    hs.alert.show("Could not enforce exact space count (have " .. #s .. ", need " .. n .. ")")
    return false
  end

  return true
end

-- Wait until an app has a main window, then call callback(win)
local function waitForMainWindow(appName, callback)
  local tries    = 0
  local maxTries = 40  -- 10 seconds
  local t

  t = hs.timer.doEvery(0.25, function()
    local a   = app.get(appName)
    local win = a and a:mainWindow()

    if win then
      t:stop()
      callback(win)
    else
      tries = tries + 1
      if tries >= maxTries then
        t:stop()
        hs.alert.show("No window for " .. appName)
        callback(nil)
      end
    end
  end)
end

-- Switch to a space and block until it's definitely active
local function gotoSpaceAndWait(spaceId)
  spaces.gotoSpace(spaceId)

  local tries    = 0
  local maxTries = 50

  while spaces.activeSpaceOnScreen(screen) ~= spaceId and tries < maxTries do
    hs.timer.usleep(100000) -- 0.1s
    tries = tries + 1
  end
end

-- Deep quit all apps except a keep list.
-- Only considers apps that actually have a main window.
local function deepQuitAllApps(keepExtra)
  local keep = {}

  if keepExtra then
    for _, name in ipairs(keepExtra) do
      keep[name] = true
    end
  end

  local systemKeep = {
    ["Finder"]      = true,
    ["Hammerspoon"] = true,
  }

  local function isKept(name)
    return systemKeep[name] or keep[name]
  end

  local function remainingRealApps()
    local result = {}
    for _, a in ipairs(hs.application.runningApplications()) do
      local name = a:name()
      if name
         and not isKept(name)
         and a:mainWindow() ~= nil   -- ignore menu bar helpers / agents
      then
        table.insert(result, a)
      end
    end
    return result
  end

  -- Phase 1: graceful quit
  for _, a in ipairs(remainingRealApps()) do
    a:kill()
  end

  local maxSoftTries = 40
  local tries = 0
  while #remainingRealApps() > 0 and tries < maxSoftTries do
    hs.timer.usleep(250000)
    tries = tries + 1
  end

  local rem = remainingRealApps()
  if #rem == 0 then
    return true
  end

  -- Phase 2: force quit
  for _, a in ipairs(rem) do
    a:kill9()
  end

  local maxHardTries = 40
  tries = 0
  while #remainingRealApps() > 0 and tries < maxHardTries do
    hs.timer.usleep(250000)
    tries = tries + 1
  end

  rem = remainingRealApps()
  if #rem > 0 then
    local names = {}
    for _, a in ipairs(rem) do
      table.insert(names, a:name() or "<?>")
    end
    hs.alert.show("Apps could not be killed: " .. table.concat(names, ", "))
    return false
  end

  return true
end

------------------------------------------------------------
-- Layout application (single-phase with verification + retries)
------------------------------------------------------------

-- For each entry { name = "App", space = 1 }, we:
--  1) goto that space
--  2) launch app
--  3) wait for window
--  4) verify window is in that space
--  5) if not, kill app and retry (up to maxAttempts)
local function applyLayoutWithChecks(layout, done)
  local index = 1

  local function nextApp()
    if index > #layout then
      if done then done() end
      return
    end

    local entry = layout[index]
    index = index + 1

    local s = getSpaces()
    local spaceId = s[entry.space]
    if not spaceId then
      hs.alert.show("Missing space index " .. tostring(entry.space) .. " for " .. entry.name)
      nextApp()
      return
    end

    local maxAttempts = 3

    local function placeApp(attempt)
      attempt = attempt or 1
      if attempt > maxAttempts then
        hs.alert.show("Failed to place " .. entry.name .. " in space " .. tostring(entry.space))
        nextApp()
        return
      end

      -- 1. Go to target space and wait
      gotoSpaceAndWait(spaceId)

      -- 2. Launch/focus the app
      hs.application.launchOrFocus(entry.name)

      -- 3. Wait for main window
      waitForMainWindow(entry.name, function(win)
        if not win then
          -- retry from scratch
          placeApp(attempt + 1)
          return
        end

        -- small extra wait so macOS finishes assigning space
        hs.timer.doAfter(0.5, function()
          local ws = spaces.windowSpaces(win) or {}
          local inTarget = false
          for _, sid in ipairs(ws) do
            if sid == spaceId then
              inTarget = true
              break
            end
          end

          if inTarget then
            -- Maximize on its screen and focus
            local scr = win:screen()
            if scr then
              win:setFrame(scr:frame())
            end
            win:focus()
            nextApp()
          else
            -- Kill app and try again in this space
            local a = win:application()
            if a then
              a:kill9()
              hs.timer.doAfter(1.0, function()
                placeApp(attempt + 1)
              end)
            else
              placeApp(attempt + 1)
            end
          end
        end)
      end)
    end

    placeApp(1)
  end

  nextApp()
end

------------------------------------------------------------
-- Core workspace setup helper
------------------------------------------------------------

local function setupWorkspace(modeName, targetSpaces, layout)
  hs.alert.show("Setting up " .. modeName .. " workspace...")

  -- Step 1: Deep quit apps
  local okQuit = deepQuitAllApps()
  if not okQuit then
    hs.alert.show("Aborting " .. modeName .. " setup (could not close all apps)")
    return
  end

  -- Step 2: Enforce exact spaces
  local okSpaces = ensureExactSpaces(targetSpaces)
  if not okSpaces then
    hs.alert.show("Aborting " .. modeName .. " setup (spaces not correct)")
    return
  end

  -- Step 3: Apply layout with verification & retries
  applyLayoutWithChecks(layout, function()
    -- End on space 1 with first app focused
    local s = getSpaces()
    if s[1] then
      gotoSpaceAndWait(s[1])
      local first = layout[1]
      if first then
        local a = app.get(first.name)
        local w = a and a:mainWindow()
        if w then w:focus() end
      end
    end
    hs.alert.show(modeName .. " workspace ready")
  end)
end

------------------------------------------------------------
-- PhD workspace  ⌘⌥⌃P
------------------------------------------------------------

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "P", function()
  local phdLayout = {
    { name = "Brave Browser", space = 1 },
    { name = "Zotero",        space = 2 },
    { name = "Obsidian",      space = 3 },
    { name = "Mattermost", space = 4},
    { name = "Mail",          space = 5 },
    { name = "Calendar",      space = 6 },
    -- 7 intentionally left empty
    { name = "Marta",         space = 8 },
    { name = "Spotify",       space = 9 },
  }

  setupWorkspace("PhD", 9, phdLayout)
end)

------------------------------------------------------------
-- Chill workspace  ⌘⌥⌃C
------------------------------------------------------------

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "C", function()
  local chillLayout = {
    { name = "Brave Browser", space = 1 },
    -- 2 and 3 empty
    { name = "Marta",         space = 4 },
  }

  setupWorkspace("Chill", 4, chillLayout)
end)

------------------------------------------------------------
-- Casual coding workspace  ⌘⌥⌃D
------------------------------------------------------------

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "D", function()
  local codingLayout = {
    { name = "Brave Browser", space = 1 },
    { name = "Cursor",        space = 2 },
    -- 3 empty on purpose
    { name = "Marta",         space = 4 },
    { name = "Spotify",       space = 5 },
  }

  setupWorkspace("Casual Coding", 5, codingLayout)
end)
