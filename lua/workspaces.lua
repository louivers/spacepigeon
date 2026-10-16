local app    = require("hs.application")
local hotkey = require("hs.hotkey")
local spaceUtils = require("lua.space_utils")
local layout     = require("lua.layout")
local structure  = require("lua.structure")
local slots      = require("lua.slots")
local helper     = require("lua.helper")
local config     = require("lua.config")
local log        = require("lua.log")

local M = {}

local systemKeep = {
  ["Finder"]      = true,
  ["Hammerspoon"] = true,
  ["SpacePigeon"] = true,
}

-- Quits apps that have a window and are neither in the preset nor in the keep
-- list. Apps that are in the preset keep running: their windows get moved.
--
-- Only regular Dock apps are considered, and which ones have windows comes
-- from one helper call. Asking every running process over Accessibility
-- (the old way) can hang for seconds on background processes.
local function quitOtherApps(layoutConfig, keepExtra)
  local done = log.step("Quit other apps")

  local keep = {}
  for _, name in ipairs(keepExtra or {}) do keep[name] = true end
  for _, entry in ipairs(layoutConfig) do keep[entry.name] = true end

  local pids = helper.pidsWithWindows()
  local targets, names = {}, {}
  for _, a in ipairs(app.runningApplications()) do
    local name = a:name()
    if name and a:kind() == 1 and not systemKeep[name] and not keep[name] then
      local hasWindow
      if pids then
        hasWindow = pids[a:pid()] == true
      else
        hasWindow = a:mainWindow() ~= nil
      end
      if hasWindow then
        table.insert(targets, a)
        table.insert(names, name)
      end
    end
  end

  if #targets == 0 then
    done("No other apps to quit", { via = pids and "helper" or "accessibility" })
    return true
  end
  log.info("Quitting " .. #targets .. " app(s): " .. table.concat(names, ", "))

  local saveSet = {}
  for _, name in ipairs(config.saveBeforeQuit or {}) do saveSet[name] = true end
  for i, a in ipairs(targets) do
    if saveSet[names[i]] then layout.saveDocuments(a, names[i]) end
  end

  local started = log.clock()
  for _, a in ipairs(targets) do a:kill() end

  local quitTimes, remaining = {}, {}
  for i, a in ipairs(targets) do remaining[i] = a end

  local deadline = hs.timer.secondsSinceEpoch() + 8
  while next(remaining) and hs.timer.secondsSinceEpoch() < deadline do
    for i, a in pairs(remaining) do
      if not a:isRunning() then
        quitTimes[names[i]] = math.floor(log.since(started))
        remaining[i] = nil
      end
    end
    if next(remaining) then spaceUtils.sleep(0.1) end
  end

  -- Force quitting an app that is asking about unsaved changes would lose
  -- them, so those (and apps in saveBeforeQuit) are left running.
  local forced, asking = {}, {}
  for i, a in pairs(remaining) do
    if saveSet[names[i]] or layout.isAsking(a) then
      table.insert(asking, names[i])
    else
      table.insert(forced, names[i])
      a:kill9()
    end
  end
  if #asking > 0 then
    log.warn("Not force quitting app(s) that may have unsaved changes: " .. table.concat(asking, ", "))
  end
  if #forced > 0 then
    log.warn("Force quitting app(s) that did not quit within 8 s: " .. table.concat(forced, ", "))
    spaceUtils.waitFor(function()
      for _, a in pairs(remaining) do
        if a:isRunning() then return false end
      end
      return true
    end, 3, 0.1)
  end

  local still = {}
  for i, a in pairs(remaining) do
    if a:isRunning() then table.insert(still, names[i]) end
  end
  if #still > 0 then
    done("Could not close: " .. table.concat(still, ", "), { quitAfterMs = quitTimes, forced = forced, asking = asking }, "error")
    if #asking > 0 then
      hs.alert.show("Save or close your work in " .. table.concat(asking, ", ") .. ", then try again", 5)
    else
      hs.alert.show("Apps could not be closed: " .. table.concat(still, ", "))
    end
    return false
  end

  done("Quit " .. #targets .. " app(s)", { quitAfterMs = quitTimes, forced = forced },
    #forced > 0 and "warn" or "info")
  return true
end

local function focusFirstApp(layoutConfig)
  for _, entry in ipairs(layoutConfig) do
    if entry.pos ~= "fullscreen" then
      local a = layout.findApp(entry.name)
      local w = a and a:mainWindow()
      if w then w:focus() end
      return
    end
  end
end

-- Goes to the space of the preset's focus app and focuses its frontmost
-- window. Returns false when the app has no window, so the caller can fall
-- back to the default focus.
local function focusApp(name)
  local a = layout.findApp(name)
  if not a then
    log.warn("Focus app " .. name .. " is not running")
    return false
  end

  -- Accessibility often cannot see windows on other Spaces; the helper can.
  local main = a:mainWindow()
  local wid = main and main:id()
  local sid
  if wid then
    sid = (hs.spaces.windowSpaces(wid) or {})[1]
  else
    local list = helper.windowsForApp(a)
    if list[1] then
      wid = list[1].id
      sid = (list[1].spaces or {})[1] or (hs.spaces.windowSpaces(wid) or {})[1]
    end
  end

  if sid then
    spaceUtils.gotoSpaceAndWait(sid)
  elseif not wid then
    -- No helper: activating the app makes macOS switch to a Space with its
    -- windows.
    a:activate()
  end

  local win = spaceUtils.waitFor(function()
    local w = (wid and hs.window.get and hs.window.get(wid)) or a:mainWindow()
    return (w and w:isStandard()) and w or nil
  end, 1.5, 0.1)
  if not win then
    log.warn("Focus app " .. name .. " has no window")
    return false
  end
  win:focus()
  log.debug("Focused " .. name, { window = win:id(), space = sid })
  return true
end

-- Spaces per monitor, as a list: { main, secondary, [3], ... }. A plain
-- number is the main monitor's count.
local function desktopCounts(targetSpaces)
  local totals = {}
  if type(targetSpaces) ~= "table" then
    totals[1] = targetSpaces or 0
    return totals
  end
  totals[1] = targetSpaces.main or targetSpaces[1] or 0
  totals[2] = targetSpaces.secondary or targetSpaces[2] or 0
  for k, v in pairs(targetSpaces) do
    if math.type(k) == "integer" and k > 2 then totals[k] = v end
  end
  return totals
end

local function monitorName(i)
  if i == 1 then return "main" end
  if i == 2 then return "secondary" end
  return i .. (i == 3 and "rd" or "th")
end

local function runSetup(modeName, targetSpaces, layoutConfig, opts)
  hs.alert.show("Setting up " .. modeName .. " workspace...")
  -- Let the alert draw before the work starts.
  spaceUtils.sleep(0.05)

  if opts.keepApps then
    log.debug("Not quitting other apps (" .. tostring(opts.keepApps) .. ")")
  elseif config.quitOthers ~= false then
    if not quitOtherApps(layoutConfig, config.keepAlive) then
      hs.alert.show("Aborting " .. modeName .. " setup (could not close all apps)")
      log.endRun("Aborted: some apps could not be closed")
      return
    end
  else
    log.debug("Not quitting other apps (quitOthers is off)")
  end

  -- Start every app that is not running yet, all at once.
  layout.prelaunch(layoutConfig)

  -- Turn the preset's space numbers into desktops and fullscreen positions,
  -- per monitor. The entries are copied so the preset itself is unchanged:
  -- in a copy, `space` is the desktop number (normal apps) or the desktop a
  -- fullscreen app comes after (0 = before desktop 1); `slot` is the number
  -- from the preset.
  local totals = desktopCounts(targetSpaces)
  local screens = spaceUtils.getOrderedScreens()

  local last = #screens
  for i in pairs(totals) do if i > last then last = i end end
  for _, entry in ipairs(layoutConfig) do
    local i = spaceUtils.monitorIndex(entry.monitor)
    if i > last then last = i end
  end
  for i = 1, last do totals[i] = totals[i] or 0 end

  -- A monitor that is not connected: its spaces go after the main monitor's,
  -- in the same order, and its apps move along with them.
  local entries = layoutConfig
  for i = 2, last do
    local used = totals[i] > 0
    for _, entry in ipairs(entries) do
      if spaceUtils.monitorIndex(entry.monitor) == i then used = true end
    end
    if not screens[i] and used then
      local folded, movedApps = {}, {}
      for _, entry in ipairs(entries) do
        if spaceUtils.monitorIndex(entry.monitor) == i then
          local c = {}
          for k, v in pairs(entry) do c[k] = v end
          c.monitor = "main"
          c.space = (tonumber(entry.space) or 1) + totals[1]
          table.insert(folded, c)
          table.insert(movedApps, entry.name)
        else
          table.insert(folded, entry)
        end
      end
      log.info(string.format("No %s monitor: its %d space(s) go after the %d of the main monitor",
        monitorName(i), totals[i], totals[1]), { apps = movedApps })
      entries = folded
      totals[1] = totals[1] + totals[i]
      totals[i] = 0
    end
  end

  local monitors = {}
  for i = 1, last do
    monitors[i] = { key = monitorName(i), total = totals[i], screen = screens[i], fullscreen = {} }
  end

  for i, m in ipairs(monitors) do
    local mine = {}
    for _, entry in ipairs(entries) do
      if spaceUtils.monitorIndex(entry.monitor) == i then table.insert(mine, entry) end
    end
    m.resolved = slots.resolve(mine, m.total, config.numbering)
    m.count = m.resolved.desktops
    for _, w in ipairs(m.resolved.warnings) do log.warn(w) end
    if m.resolved.picture ~= "" then
      log.info("Layout (" .. m.key .. "): " .. m.resolved.picture, { desktops = m.count })
    end
  end

  local function copyWith(entry, space)
    local c = {}
    for k, v in pairs(entry) do c[k] = v end
    c.slot = entry.space
    c.space = space
    return c
  end

  local normalEntries = {}
  for _, entry in ipairs(entries) do
    local m = monitors[spaceUtils.monitorIndex(entry.monitor)] or monitors[1]
    if entry.pos == "fullscreen" then
      table.insert(m.fullscreen, copyWith(entry, m.resolved.afterOf[entry]))
    else
      table.insert(normalEntries, copyWith(entry, m.resolved.desktopOf[entry] or entry.space))
    end
  end

  -- Desktops and fullscreen apps, per monitor.
  for _, m in ipairs(monitors) do
    if m.count > 0 and not m.screen then
      log.warn("Preset wants " .. m.count .. " desktop(s) on the " .. m.key .. " monitor, but it is not connected")
    elseif m.count > 0 then
      local items = {}
      local prep = log.step("Prepare fullscreen apps (" .. m.key .. ")")
      for _, entry in ipairs(m.fullscreen) do
        local item = layout.prepareFullscreen(entry, m.count)
        if item then
          table.insert(items, item)
        else
          log.error("Could not prepare " .. entry.name .. " for fullscreen")
        end
      end
      prep(#items .. " fullscreen app(s) ready")
      structure.build(m.screen, m.count, items, { reorder = config.reorderFullscreen ~= false })
    end
  end

  -- Normal windows on their desktops.
  local failures = 0
  for _, entry in ipairs(normalEntries) do
    if not layout.placeNormal(entry) then
      failures = failures + 1
    end
  end

  if not (opts.focus and focusApp(opts.focus)) then
    local first = spaceUtils.getSpacesForMonitor("main")[1]
    if first then
      spaceUtils.gotoSpaceAndWait(first)
      focusFirstApp(layoutConfig)
    end
  end

  local counts = log.counts()
  local summary = string.format("%s workspace ready", modeName)
  if failures > 0 then
    summary = string.format("%s workspace ready, %d app(s) not placed", modeName, failures)
  elseif counts.error > 0 or counts.warn > 0 then
    summary = string.format("%s workspace ready (%d warning(s), %d error(s))", modeName, counts.warn, counts.error)
  end
  log.endRun(summary, { failures = failures, warnings = counts.warn, errors = counts.error })
  hs.alert.show(summary)
end

local running = false

-- opts.keepApps: a reason not to quit other apps this run (the monitor
-- count changed, so this only rearranges).
-- opts.focus: the app to focus when done; without it, the first app on the
-- main monitor's first space.
local function setupWorkspace(modeName, targetSpaces, layoutConfig, trigger, opts)
  opts = opts or {}
  if running then
    hs.alert.show("SpacePigeon is still setting up a workspace")
    log.warn("Ignored " .. tostring(trigger or "trigger") .. ": a workspace setup is already running")
    return
  end
  running = true
  M.lastRunScreens = #hs.screen.allScreens()

  local caps = helper.capabilities()
  log.startRun(modeName, {
    trigger = trigger,
    helperMove = caps.move == true,
    helperFocus = caps.focus == true,
    macos = caps.macos,
    apps = #layoutConfig,
  })

  -- One coroutine for the whole setup: waits yield to Hammerspoon instead of
  -- freezing it, and the steps can be written in order.
  coroutine.wrap(function()
    local ok, err = xpcall(runSetup, debug.traceback, modeName, targetSpaces, layoutConfig, opts)
    running = false
    if not ok then
      log.error("Setup crashed", { error = tostring(err) })
      log.endRun("Setup crashed")
      hs.alert.show("SpacePigeon error - check the log window")
    end
  end)()
end

-- A preset can have a mode per number of connected monitors, each with its
-- own spaces and layout:
--   modes = { { monitors = 1, spaces = { main = 6 }, layout = { ... } } }
-- The mode for the current monitor count is used; without one, the preset's
-- own spaces and layout. The fourth result is the app to focus when done
-- (`focus` on the mode, else on the preset), or nil.
local function pickMode(preset, screenCount)
  for _, mode in ipairs(preset.modes or {}) do
    if mode.monitors == screenCount then
      local label = string.format("%s (%d monitor%s)", preset.name, screenCount, screenCount == 1 and "" or "s")
      return label, mode.spaces or preset.spaces, mode.layout or preset.layout, mode.focus or preset.focus
    end
  end
  return preset.name, preset.spaces, preset.layout, preset.focus
end

local function presetKey(preset)
  for key, p in pairs(config.presets or {}) do
    if p == preset then return key end
  end
end

-- The last preset that was set up, kept across reloads (saving the config
-- reloads Hammerspoon).
local function lastPreset()
  local key = hs.settings.get("spacepigeon.lastPreset")
  return key and config.presets and config.presets[key]
end

local function setupPreset(preset, trigger, opts)
  local name, spaces, layoutConfig, focus = pickMode(preset, #hs.screen.allScreens())
  local key = presetKey(preset)
  if key then hs.settings.set("spacepigeon.lastPreset", key) end
  opts = opts or {}
  if focus and focus ~= "" and opts.focus == nil then
    local o = { focus = focus }
    for k, v in pairs(opts) do o[k] = v end
    opts = o
  end
  setupWorkspace(name, spaces, layoutConfig, trigger, opts)
end

-- Menu bar icon with one item per preset (config.menubar, on by default).
local menubar
local function startMenubar()
  if config.menubar == false or not hs.menubar then return end
  menubar = hs.menubar.new()
  if not menubar then return end
  menubar:setTitle("🐦")
  menubar:setTooltip("SpacePigeon")
  menubar:setMenu(function()
    local list = {}
    for _, preset in pairs(config.presets or {}) do table.insert(list, preset) end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)

    local current = lastPreset()
    local items = {}
    for _, preset in ipairs(list) do
      table.insert(items, {
        title = preset.name,
        checked = preset == current,
        disabled = running,
        fn = function() setupPreset(preset, "menu bar") end,
      })
    end
    table.insert(items, { title = "-" })
    table.insert(items, { title = "Edit Config…", fn = function()
      hs.task.new("/usr/bin/open", nil, { "-a", "SpacePigeon" }):start()
    end })
    table.insert(items, { title = "View Logs…", fn = function()
      hs.task.new("/usr/bin/open", nil, { "-a", "SpacePigeon", "--args", "--logs" }):start()
    end })
    return items
  end)
end

-- Plugging in or unplugging a monitor sets up the last preset again for the
-- new monitor count (config.followMonitors, off by default). Other apps are
-- not quit: this only moves windows. macOS reports a monitor change in
-- several steps, so it waits until the count is stable for a few seconds.
local screenWatcher, screenTimer
local function startScreenWatcher()
  if not config.followMonitors or not (hs.screen and hs.screen.watcher) then return end
  M.lastRunScreens = M.lastRunScreens or #hs.screen.allScreens()

  local function check()
    local count = #hs.screen.allScreens()
    if count == M.lastRunScreens then return end
    local preset = lastPreset()
    if not preset then
      log.debug("Monitor count changed, but no preset was set up yet")
      M.lastRunScreens = count
      return
    end
    if running then
      screenTimer = hs.timer.doAfter(3, check)
      return
    end
    log.info(string.format("Monitors changed from %d to %d: setting up %s again",
      M.lastRunScreens, count, tostring(preset.name)))
    setupPreset(preset, "monitors changed", { keepApps = "monitors changed" })
  end

  screenWatcher = hs.screen.watcher.new(function()
    if screenTimer then screenTimer:stop() end
    screenTimer = hs.timer.doAfter(3, check)
  end)
  screenWatcher:start()
end

local function bindWorkspaceHotkeys()
  for _, binding in ipairs(config.bindings) do
    if binding.preset then
      local trigger = "hotkey " .. table.concat(binding.mods, "+") .. "+" .. binding.key
      hotkey.bind(binding.mods, binding.key, function()
        setupPreset(binding.preset, trigger)
      end)
    end
  end
end

M.setupWorkspace = setupWorkspace
M.setupPreset = setupPreset
M.pickMode = pickMode
M.bindWorkspaceHotkeys = bindWorkspaceHotkeys
M.startMenubar = startMenubar
M.startScreenWatcher = startScreenWatcher

return M
