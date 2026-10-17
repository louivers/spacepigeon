-- === SpacePigeon ===

-- A profile (lua/profile.lua) brings its own config instead of lua/config.lua.
local profileOk, profile = pcall(require, "lua.profile")
if profileOk and profile.name then
  local cfgOk, cfg = pcall(dofile, profile.dir .. "/config.lua")
  if cfgOk and type(cfg) == "table" then
    package.loaded["lua.config"] = cfg
  else
    print("SpacePigeon: could not load profile " .. profile.name .. ": " .. tostring(cfg))
  end
end

-- Bind reload config URL event.
-- Some URL dispatchers can lowercase the event name, so accept both.
local function reloadConfigEvent()
  hs.reload()
end

hs.urlevent.bind("reloadConfig", reloadConfigEvent)
hs.urlevent.bind("reloadconfig", reloadConfigEvent)

-- Drag test (lua/dragbench.lua): open "hammerspoon://dragbench".
hs.urlevent.bind("dragbench", function(_, params)
  require("lua.dragbench").run(params)
end)

local logOk, log = pcall(require, "lua.log")
if not logOk then
  log = { info = print, warn = print, error = print, debug = function() end }
end

-- Load main workspace module after registering reload handlers so URL reload
-- keeps working even if workspace setup has an error.
local ok, workspacesOrErr = pcall(require, "lua.workspaces")
if not ok then
  log.error("Init error loading workspaces", { error = tostring(workspacesOrErr) })
  hs.alert.show("SpacePigeon init error - check the log window")
  return
end

local bindOk, bindErr = pcall(function()
  workspacesOrErr.bindWorkspaceHotkeys()
end)
if not bindOk then
  log.error("Init error binding hotkeys", { error = tostring(bindErr) })
  hs.alert.show("SpacePigeon hotkey error - check the log window")
end

for _, start in ipairs({ "startMenubar", "startScreenWatcher" }) do
  local startOk, startErr = pcall(workspacesOrErr[start])
  if not startOk then
    log.error("Init error in " .. start, { error = tostring(startErr) })
  end
end

-- Report what the helper can do on this macOS.
local helperOk, helper = pcall(require, "lua.helper")
local caps = helperOk and helper.capabilities() or {}

-- "Automatically rearrange Spaces based on most recent use" shuffles Spaces
-- and changes where new ones appear, which breaks the ordering. Point it out.
local mru = hs.execute("defaults read com.apple.dock mru-spaces 2>/dev/null") or ""
local mruOff = mru:match("^%s*0") ~= nil

if profileOk and profile.name then
  hs.alert.show("SpacePigeon: using the " .. profile.name .. " profile", 3)
end

log.info("SpacePigeon loaded", {
  profile = profileOk and profile.name or nil,
  helperMove = caps.move == true,
  helperFocus = caps.focus == true,
  macos = caps.macos,
  rearrangeSpacesOff = mruOff,
})

if not mruOff then
  log.warn("\"Automatically rearrange Spaces based on most recent use\" is on: Space order will not stick. Turn it off in System Settings > Desktop & Dock.")
  if not hs.settings.get("spacepigeon.mruHintShown") then
    hs.settings.set("spacepigeon.mruHintShown", true)
    hs.alert.show("SpacePigeon tip: turn off \"Automatically rearrange Spaces\" in Desktop & Dock settings", 6)
  end
end
