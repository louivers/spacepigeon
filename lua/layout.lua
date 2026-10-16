-- Places the apps of a preset.
--
-- Apps that are already running keep running: their window is moved to the
-- target Space (spacectl helper, SIP stays on). Apps that are not running are
-- launched on the target Space. Fullscreen entries are only prepared here;
-- structure.lua puts them in place.
--
-- Runs inside the coroutine started by workspaces.lua, so all waits yield.

local spaces = require("hs.spaces")
local helper = require("lua.helper")
local spaceUtils = require("lua.space_utils")
local fullscreen = require("lua.fullscreen")
local config = require("lua.config")
local log = require("lua.log")

local M = {}

-- Part of the screen per position: x, y, width, height as fractions.
-- Anything not listed (and "max") fills the screen.
local regions = {
  ["left"]             = { 0,   0,   1/2, 1 },
  ["right"]            = { 1/2, 0,   1/2, 1 },
  ["top"]              = { 0,   0,   1,   1/2 },
  ["bottom"]           = { 0,   1/2, 1,   1/2 },
  ["left-third"]       = { 0,   0,   1/3, 1 },
  ["center-third"]     = { 1/3, 0,   1/3, 1 },
  ["right-third"]      = { 2/3, 0,   1/3, 1 },
  ["left-two-thirds"]  = { 0,   0,   2/3, 1 },
  ["right-two-thirds"] = { 1/3, 0,   2/3, 1 },
  ["top-left"]         = { 0,   0,   1/2, 1/2 },
  ["top-right"]        = { 1/2, 0,   1/2, 1/2 },
  ["bottom-left"]      = { 0,   1/2, 1/2, 1/2 },
  ["bottom-right"]     = { 1/2, 1/2, 1/2, 1/2 },
  ["center"]           = { 1/6, 1/8, 2/3, 3/4 },
}
M.regions = regions

local function applyWindowPosition(win, pos, screen)
  local scr = screen or win:screen()
  if not scr then return end
  local f = scr:frame()

  local r = regions[pos]
  if r then
    f.x = f.x + f.w * r[1]
    f.y = f.y + f.h * r[2]
    f.w = f.w * r[3]
    f.h = f.h * r[4]
  end
  win:setFrame(f, 0)
end

-- Browsers: open the URL in a single fresh window and close the others.
-- Only used for apps SpacePigeon just launched, so no open work is closed.
local function openUrlCleanly(appName, url)
  appName = appName:match("^%s*(.-)%s*$")
  local script = nil

  if appName == "Safari" then
    script = string.format([[
        tell application "Safari"
            activate
            set newDoc to make new document with properties {URL:"%s"}
            set newWin to window 1
            set allWins to every window
            repeat with w in allWins
                if (id of w) is not (id of newWin) then
                    close w
                end if
            end repeat
        end tell
     ]], url)
  elseif appName == "Google Chrome" or appName == "Arc" or appName == "Brave Browser" or appName == "Microsoft Edge" then
    script = string.format([[
        tell application "%s"
            activate
            set newWin to make new window
            set URL of active tab of newWin to "%s"
            set allWins to every window
            repeat with w in allWins
                if (id of w) is not (id of newWin) then
                    close w
                end if
            end repeat
        end tell
     ]], appName, url)
  end

  if script then
    local ok, _, err = hs.osascript.applescript(script)
    if ok then return end
    log.warn("Opening URL in " .. appName .. " with AppleScript failed", { error = tostring(err) })
  end
  hs.execute(string.format("open -a %q %q", appName, url))
end

-- For an app that was already running: just open the URL (new tab/window),
-- without closing anything the user has open.
local function openUrlGently(appName, url)
  hs.execute(string.format("open -a %q %q", appName, url))
end

local function openUrl(entry, launchedNow)
  if not entry.url then return end
  if launchedNow then
    openUrlCleanly(entry.name, entry.url)
  else
    openUrlGently(entry.name, entry.url)
  end
  log.info("Opened " .. entry.url .. " in " .. entry.name)
end

local function resolveSpace(entry)
  if entry.monitor and entry.space then
    return spaceUtils.getSpacesForMonitor(entry.monitor)[entry.space]
  elseif entry.space then
    return spaceUtils.getSpaces()[entry.space]
  end
  return nil
end

-- The running app with exactly this name (case does not matter), or nil.
-- hs.application.get can return another app: for "Cursor" it returned
-- Apple's CursorUIViewService while the Cursor editor was not running.
-- The running app with this name. The name in a preset can also be the
-- app's file name, which the app picker uses and `open -a` understands, but
-- which is not always the name the app runs under ("Visual Studio Code" runs
-- as "Code").
local function findApp(name)
  if not name then return nil end
  local wanted = name:lower()
  local other, byFile = nil, nil
  for _, a in ipairs(hs.application.runningApplications()) do
    local n = a:name()
    if n and n:lower() == wanted then
      if a:kind() == 1 then return a end
      other = other or a
    elseif not byFile and a.path and a:kind() == 1 then
      local file = (a:path() or ""):match("([^/]+)%.app/?$")
      if file and file:lower() == wanted then byFile = a end
    end
  end
  return other or byFile
end
M.findApp = findApp

-- The window to place for a running app: its main window when Accessibility
-- can see it, otherwise its frontmost window on any Space (from the helper).
-- Returns id, hs.window-or-nil, isFullscreen, how.
local function pickWindow(application)
  local main = application:mainWindow()
  if main and main:isStandard() and main:id() then
    return main:id(), main, fullscreen.fullscreenSpaceOf(main:id()) ~= nil, "main window"
  end

  local list = helper.windowsForApp(application)
  for _, w in ipairs(list) do
    if not w.fullscreen then return w.id, nil, false, "helper window list" end
  end
  if list[1] then return list[1].id, nil, true, "helper window list" end

  -- No helper, or it saw nothing: activating the app makes macOS switch to a
  -- Space with its windows, where Accessibility can see them.
  application:activate()
  local win = spaceUtils.waitFor(function()
    local w = application:mainWindow()
    return (w and w:isStandard()) and w or nil
  end, 1.5, 0.1)
  if win and win:id() then
    return win:id(), win, fullscreen.fullscreenSpaceOf(win:id()) ~= nil, "activate app"
  end
  return nil
end

-- Launches an app with the target Space active, so its window opens there.
local function launchOn(entry, spaceId)
  local done = log.step("Launch " .. entry.name)
  spaceUtils.gotoSpaceAndWait(spaceId)
  hs.application.launchOrFocus(entry.name)

  local win = spaceUtils.waitFor(function()
    local a = findApp(entry.name)
    local w = a and a:mainWindow()
    if w and w:isStandard() then return w end
    return nil
  end, 10, 0.25)

  if not win then
    done("No window for " .. entry.name .. " after launching it", nil, "error")
    hs.alert.show("No window for " .. entry.name)
    return nil
  end
  done("Launched " .. entry.name, { window = win:id() })
  return win:id(), win, win:application()
end

-- True when one of the app's windows (on the current Space) shows a sheet or
-- dialog, like a save panel or "Do you want to save the changes?": the app
-- is waiting for the user.
local function isAsking(a)
  local ok, result = pcall(function()
    for _, w in ipairs(a:allWindows()) do
      local sub = w:subrole()
      if sub == "AXDialog" or sub == "AXSystemDialog" then return true end
      local el = hs.axuielement.windowElement(w)
      for _, child in ipairs((el and el:attributeValue("AXChildren")) or {}) do
        if child:attributeValue("AXRole") == "AXSheet" then return true end
      end
    end
    return false
  end)
  return ok and result == true
end

-- Presses Cmd+S in each window of an app before it is quit
-- (config.saveBeforeQuit), going to each Space that has one of its windows.
-- A document that was never saved opens a save panel instead; that panel is
-- cancelled, so the app asks about the document itself when it quits.
local function saveDocuments(a, name)
  local done = log.step("Save " .. name)
  if a:isHidden() then a:unhide() end

  -- Spaces with a window of the app; without the helper, only the current one.
  local spaceIds, seen = {}, {}
  for _, w in ipairs(helper.windowsForApp(a)) do
    local sid = w.spaces and w.spaces[1]
    if sid and not seen[sid] then
      seen[sid] = true
      table.insert(spaceIds, sid)
    end
  end
  local start = spaces.focusedSpace()
  if #spaceIds == 0 then spaceIds = { start } end

  local saved, unsaved, visited = 0, 0, {}
  for _, sid in ipairs(spaceIds) do
    if sid ~= spaces.focusedSpace() then spaceUtils.gotoSpaceAndWait(sid) end
    for _, w in ipairs(a:allWindows()) do
      local id = w:id()
      if id and not visited[id] and w:isStandard() and not w:isMinimized() then
        visited[id] = true
        w:focus()
        spaceUtils.sleep(0.15)
        hs.eventtap.keyStroke({ "cmd" }, "s", 0, a)
        spaceUtils.sleep(0.4)
        if isAsking(a) then
          hs.eventtap.keyStroke({}, "escape", 0, a)
          spaceUtils.sleep(0.2)
          unsaved = unsaved + 1
        else
          saved = saved + 1
        end
      end
    end
  end
  if start and spaces.focusedSpace() ~= start then spaceUtils.gotoSpaceAndWait(start) end

  if unsaved > 0 then
    done(string.format("Saved %d window(s) of %s; %d never saved before, %s will ask about them",
      saved, name, unsaved, name), nil, "warn")
  else
    done(string.format("Saved %d window(s) of %s", saved, name))
  end
end

M.isAsking = isAsking
M.saveDocuments = saveDocuments

-- Last resort when a window refuses to move: quit the app (normally, so it can
-- ask to save) and launch it again on the target Space.
local function relaunchOn(entry, application, spaceId)
  if config.killFallback == false then
    log.warn("Not relaunching " .. entry.name .. " (killFallback is off)")
    return nil
  end
  local done = log.step("Relaunch " .. entry.name)

  for _, name in ipairs(config.saveBeforeQuit or {}) do
    if name == entry.name then saveDocuments(application, entry.name) end
  end
  application:kill()
  local gone = spaceUtils.waitFor(function()
    return not application:isRunning()
  end, 6, 0.25)
  if not gone then
    done(entry.name .. " did not quit; leaving it where it is", nil, "error")
    hs.alert.show(entry.name .. " did not quit; leaving it where it is")
    return nil
  end
  spaceUtils.sleep(0.5)
  done("Quit " .. entry.name .. " to relaunch it", nil, "warn")
  return launchOn(entry, spaceId)
end

-- Apps started by prelaunch() in this run (name -> true). They count as
-- "just launched", e.g. for opening a URL in a clean window.
M.justLaunched = {}

-- Starts every app of the preset that is not running yet, all at once, and
-- waits until each has a window (up to 15 s). One after another, launches
-- took most of a run (17 of 25 s with 8 apps); together they take about as
-- long as the slowest one. Windows open on the current desktop; the normal
-- steps after this move them to their place.
function M.prelaunch(entries)
  M.justLaunched = {}
  local names, seen = {}, {}
  for _, e in ipairs(entries) do
    if e.name and not seen[e.name] and not findApp(e.name) then
      seen[e.name] = true
      table.insert(names, e.name)
    end
  end
  if #names == 0 then return end

  local done = log.step("Launch apps")
  local started = log.clock()
  for _, name in ipairs(names) do
    M.justLaunched[name] = true
    hs.task.new("/usr/bin/open", nil, { "-a", name }):start()
  end

  local waiting, readyMs = {}, {}
  for _, name in ipairs(names) do waiting[name] = true end
  spaceUtils.waitFor(function()
    for name in pairs(waiting) do
      local a = findApp(name)
      local w = a and a:mainWindow()
      if w and w:isStandard() then
        waiting[name] = nil
        readyMs[name] = math.floor(log.since(started))
      end
    end
    return next(waiting) == nil
  end, 15, 0.2)

  local late = {}
  for name in pairs(waiting) do table.insert(late, name) end
  table.sort(late)
  if #late > 0 then
    done(string.format("Launched %d app(s); no window yet for: %s", #names, table.concat(late, ", ")),
      { readyAfterMs = readyMs }, "warn")
  else
    done(string.format("Launched %d app(s) at once", #names), { readyAfterMs = readyMs })
  end
end

-- Gets the entry's app running with one window, and returns
-- id, hs.window-or-nil, application, launchedNow, isFullscreen.
local function obtainWindow(entry, spaceId)
  local application = findApp(entry.name)
  if application then
    local wid, win, isFs, how = pickWindow(application)
    if wid then
      log.debug("Found " .. entry.name .. " window " .. wid, { via = how, fullscreen = isFs })
      return wid, win, application, M.justLaunched[entry.name] == true, isFs
    end
    log.info(entry.name .. " is running but has no window; launching it")
  end

  local wid, win, launchedApp = launchOn(entry, spaceId)
  if not wid then return nil end
  return wid, win, launchedApp, true, false
end

-- Places one normal (non-fullscreen) entry. Returns true when it ended up on
-- its Space.
function M.placeNormal(entry)
  local done = log.step("Place " .. entry.name)
  local screen = spaceUtils.screenForMonitor(entry.monitor or "main")
  local spaceId = resolveSpace(entry)
  if not spaceId then
    done("No desktop " .. tostring(entry.space) .. " for " .. entry.name, nil, "error")
    hs.alert.show("Missing space for " .. entry.name)
    return false
  end

  local wid, win, application, launchedNow, isFs = obtainWindow(entry, spaceId)
  if not wid then
    done("Could not get a window for " .. entry.name, nil, "error")
    return false
  end

  if isFs then
    log.info(entry.name .. " is fullscreen but should be on a desktop")
    fullscreen.exitFullscreen(application, wid)
  end

  local method = "moved"
  if launchedNow then
    method = M.justLaunched[entry.name] and "launched, then moved" or "launched there"
  end
  local placed = helper.moveWindowToSpace(wid, spaceId)

  if not placed then
    -- Moving across displays can fail; move it to the right screen first.
    win = win or fullscreen.findWindow(application, wid)
    if win and screen and win:screen() and win:screen():id() ~= screen:id() then
      log.info("Moving " .. entry.name .. " to the right screen first")
      win:moveToScreen(screen, false, true)
      spaceUtils.sleep(0.6)
      placed = helper.moveWindowToSpace(wid, spaceId)
    end
  end

  if not placed then
    local newId, newWin, newApp = relaunchOn(entry, application, spaceId)
    if not newId then
      done("Failed to place " .. entry.name, nil, "error")
      hs.alert.show("Failed to place " .. entry.name)
      return false
    end
    wid, win, application, launchedNow = newId, newWin, newApp, true
    method = "relaunched"
    placed = helper.windowIsOnSpace(wid, spaceId)
  end

  -- Position it. Accessibility needs the Space to be active to see the window.
  spaceUtils.gotoSpaceAndWait(spaceId)
  win = spaceUtils.waitFor(function()
    return fullscreen.findWindow(application, wid)
  end, 2, 0.1)
  if win then
    applyWindowPosition(win, entry.pos, screen)
  else
    log.warn("Could not reach " .. entry.name .. " to set its size")
  end

  openUrl(entry, launchedNow)

  local where = string.format("%s on desktop %s (%s)", entry.name, tostring(entry.space), entry.pos or "max")
  if entry.slot and entry.slot ~= entry.space then
    where = string.format("%s on desktop %s, space %s (%s)", entry.name, tostring(entry.space), tostring(entry.slot), entry.pos or "max")
  end
  if placed then
    done(where .. ": " .. method, { window = wid, space = spaceId })
  else
    done(where .. ": not on its desktop", { window = wid, space = spaceId }, "error")
  end
  return placed
end

-- Gets a fullscreen entry's app running with one window and returns the item
-- structure.build() needs. `after` is the desktop the Space should follow.
function M.prepareFullscreen(entry, desktopCount)
  local screen = spaceUtils.screenForMonitor(entry.monitor or "main")
  local desktops = spaceUtils.userSpacesForScreen(screen)
  local launchOnSpace = desktops[#desktops]
  if not launchOnSpace then return nil end

  local wid, _, application, launchedNow = obtainWindow(entry, launchOnSpace)
  if not wid then return nil end
  openUrl(entry, launchedNow)

  local after = tonumber(entry.space) or desktopCount
  return { app = application, id = wid, name = entry.name, after = after, screen = screen }
end

return M
