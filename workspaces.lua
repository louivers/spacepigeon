local app    = require("hs.application")
local hotkey = require("hs.hotkey")
local spaceUtils = require("space_utils")
local layout     = require("layout")
local config     = require("config")

local M = {}

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

local function focusFirstApp(layoutConfig)
  local first = layoutConfig[1]
  if not first then return end

  local a = app.get(first.name)
  local w = a and a:mainWindow()
  if w then w:focus() end
end

local function setupWorkspace(modeName, targetSpaces, layoutConfig)
  hs.alert.show("Setting up " .. modeName .. " workspace...")

  -- Step 1: Deep quit apps
  local okQuit = deepQuitAllApps()
  if not okQuit then
    hs.alert.show("Aborting " .. modeName .. " setup (could not close all apps)")
    return
  end

  -- Step 2: Enforce exact spaces
  -- Handle new config format (table with main/secondary) or legacy (number)
  local mainSpaces = 0
  local secondarySpaces = 0

  if type(targetSpaces) == "table" then
    mainSpaces = targetSpaces.main or 0
    secondarySpaces = targetSpaces.secondary or 0
  else
    mainSpaces = targetSpaces
  end

  -- Main Monitor
  local okMain = spaceUtils.ensureSpaces("main", mainSpaces)
  if not okMain then
    hs.alert.show("Aborting " .. modeName .. " setup (main spaces not correct)")
    return
  end

  -- Secondary Monitor (if requested and monitor exists)
  if secondarySpaces > 0 then
    local okSec = spaceUtils.ensureSpaces("secondary", secondarySpaces)
    -- If secondary monitor is missing, we might just warn instead of aborting?
    -- For now, if enforce fails (e.g. screen present but can't add space), we abort.
    -- If screen is missing, ensureSpaces returns false/warns.
    if not okSec then
       hs.alert.show("Secondary monitor setup failed (continuing with main only)")
    end
  end

  -- Step 3: Apply layout with verification & retries
  layout.applyLayoutWithChecks(layoutConfig, function()
    -- End on space 1 with first app focused
    local s = spaceUtils.getSpacesForMonitor("main")
    if s[1] then
      spaceUtils.gotoSpaceAndWait(s[1])
      focusFirstApp(layoutConfig)
    end
    hs.alert.show(modeName .. " workspace ready")
  end)
end

local function bindWorkspaceHotkeys()
  for _, binding in ipairs(config.bindings) do
    hotkey.bind(binding.mods, binding.key, function()
      setupWorkspace(binding.preset.name, binding.preset.spaces, binding.preset.layout)
    end)
  end
end

M.setupWorkspace = setupWorkspace
M.bindWorkspaceHotkeys = bindWorkspaceHotkeys

return M
