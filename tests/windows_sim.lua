-- Several windows of one app, custom positions and saving the current
-- layout, against a fake macOS with a working helper.
-- Run from the project root: lua tests/windows_sim.lua
package.path = "./?.lua;" .. package.path

local clock = 0
-- Desktops 1 and 2, and a fullscreen app (not in the preset) after them.
local spacesList = { { id = 1, type = "user" }, { id = 2, type = "user" }, { id = 3, type = "fullscreen" } }
local current = 1
local windows, zorder, apps, byPid = {}, {}, {}, {}
local alerts, keys, menus, settings, urls = {}, {}, {}, {}, {}
local hotkeys = {}
local nextWin, nextPid = 500, 100

local screen = {
  id = function() return 1 end,
  name = function() return "Sim Display" end,
  frame = function() return { x = 0, y = 0, w = 1000, h = 800 } end,
}

local function spaceById(id)
  for i, s in ipairs(spacesList) do if s.id == id then return s, i end end
end

local function toFront(id)
  for i, other in ipairs(zorder) do if other == id then table.remove(zorder, i) break end end
  table.insert(zorder, 1, id)
end

local function newWindow(appRec, sid, title, frame)
  nextWin = nextWin + 1
  local w = { _id = nextWin, _app = appRec, space = sid, _title = title or "Untitled",
    f = frame or { x = 100, y = 100, w = 600, h = 400 } }
  function w:id() return self._id end
  function w:title() return self._title end
  function w:isStandard() return true end
  function w:isMinimized() return false end
  function w:subrole() return "AXStandardWindow" end
  function w:focus() toFront(self._id) end
  function w:screen() return screen end
  function w:application() return self._app end
  function w:frame() return { x = self.f.x, y = self.f.y, w = self.f.w, h = self.f.h } end
  function w:setFrame(f) self.f = { x = f.x, y = f.y, w = f.w, h = f.h } end
  windows[w._id] = w
  toFront(w._id)
  return w
end

-- The app's windows front to back, optionally only those on one Space.
local function windowsOf(a, sid)
  local out = {}
  for _, id in ipairs(zorder) do
    local w = windows[id]
    if w._app == a and (sid == nil or w.space == sid) then table.insert(out, w) end
  end
  return out
end

local function newApp(name, opts)
  opts = opts or {}
  nextPid = nextPid + 1
  local a = { _name = name, _running = true, _pid = nextPid, _menu = opts.menu or {}, _cmdN = opts.cmdN ~= false,
    _path = "/Applications/" .. (opts.file or name) .. ".app", _bundle = opts.bundle or ("com.example." .. name) }
  function a:name() return self._name end
  function a:pid() return self._pid end
  function a:kind() return 1 end
  function a:path() return self._path end
  function a:bundleID() return self._bundle end
  function a:isRunning() return self._running end
  function a:isHidden() return false end
  function a:unhide() end
  -- Like real Accessibility: only windows on the active Space are visible.
  function a:mainWindow() return windowsOf(self, current)[1] end
  function a:allWindows() return windowsOf(self, current) end
  -- macOS switches to the Space of the app's frontmost window.
  function a:activate()
    local front = windowsOf(self)[1]
    if front then current = front.space end
  end
  function a:selectMenuItem(path)
    local key = type(path) == "table" and table.concat(path, " > ") or path
    table.insert(menus, self._name .. ": " .. key)
    local fn = self._menu[key]
    if not fn then return nil end
    fn(self)
    return true
  end
  function a:kill() self._running = false end
  function a:kill9() self:kill() end
  apps[name] = a
  byPid[a._pid] = a
  return a
end

-- Just enough JSON for the log and the capture file.
local function encode(v)
  local t = type(v)
  if t == "table" then
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n == #v then
      local parts = {}
      for _, x in ipairs(v) do table.insert(parts, encode(x)) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keysSorted = {}
    for k in pairs(v) do table.insert(keysSorted, tostring(k)) end
    table.sort(keysSorted)
    local parts = {}
    for _, k in ipairs(keysSorted) do
      local x = v[k]
      if x == nil then x = v[tonumber(k)] end
      table.insert(parts, string.format("%q:%s", k, encode(x)))
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then
    return string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    return tostring(v)
  end
  return "null"
end

local dir = "/tmp/spacepigeon-winsim"
os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir)

hs = {
  configdir = dir,
  fs = { attributes = function() return nil end },
  execute = function(cmd) return (cmd:find("mru%-spaces") and "0\n" or ""), true end,
  json = { encode = encode, decode = function() return nil end },
  alert = { show = function(m) table.insert(alerts, m) end },
  inspect = function(t) return tostring(t) end,
  settings = {
    get = function(k) return settings[k] end,
    set = function(k, v) settings[k] = v end,
    clear = function(k) settings[k] = nil end,
  },
  timer = {
    usleep = function(us) clock = clock + us / 1e6 end,
    secondsSinceEpoch = function() return clock end,
    doAfter = function() return { stop = function() end } end,
  },
  eventtap = {
    keyStroke = function(mods, key, _, target)
      table.insert(keys, table.concat(mods, "+") .. "+" .. key .. "@" .. (target and target:name() or "?"))
      if target and key == "n" and mods[1] == "cmd" and target._cmdN then
        newWindow(target, current, "Untitled")
      end
    end,
  },
  axuielement = {
    windowElement = function() return { attributeValue = function() return {} end } end,
  },
  menubar = {
    new = function()
      local m = {}
      function m:setTitle() end
      function m:setTooltip() end
      function m:setMenu() end
      return m
    end,
  },
  urlevent = { bind = function(name, fn) urls[name] = fn end },
  -- `open -a Name` starts the app right away in this fake.
  task = {
    new = function(_, _, args)
      return { start = function() hs.application.launchOrFocus(args[2]) end }
    end,
  },
  osascript = { applescript = function() return true end },
  window = {
    get = function(id) return windows[id] end,
    allWindows = function()
      local out = {}
      for _, id in ipairs(zorder) do if windows[id].space == current then table.insert(out, windows[id]) end end
      return out
    end,
  },
  screen = {
    primaryScreen = function() return screen end,
    allScreens = function() return { screen } end,
  },
  application = {
    runningApplications = function()
      local out = {}
      for _, a in pairs(apps) do if a._running then table.insert(out, a) end end
      return out
    end,
    applicationForPID = function(pid) return byPid[pid] end,
    launchOrFocus = function(name)
      local a = apps[name] or newApp(name)
      a._running = true
      if #windowsOf(a) == 0 then newWindow(a, current, name) end
    end,
  },
  spaces = {
    spacesForScreen = function()
      local out = {}
      for _, s in ipairs(spacesList) do table.insert(out, s.id) end
      return out
    end,
    spaceType = function(id) local s = spaceById(id); return s and s.type end,
    windowSpaces = function(wid) return windows[wid] and { windows[wid].space } or {} end,
    windowsForSpace = function(sid)
      local out = {}
      for id, w in pairs(windows) do if w.space == sid then table.insert(out, id) end end
      return out
    end,
    activeSpaceOnScreen = function() return current end,
    focusedSpace = function() return current end,
    gotoSpace = function(sid) current = sid end,
    moveWindowToSpace = function(wid, sid) windows[wid].space = sid end,
    addSpaceToScreen = function() error("no desktops should be added") end,
    removeSpace = function() error("no desktops should be removed") end,
    closeMissionControl = function() end,
  },
}
coroutine.applicationYield = nil

package.preload["hs.spaces"] = function() return hs.spaces end
package.preload["hs.application"] = function() return hs.application end
package.preload["hs.hotkey"] = function()
  return { bind = function(_, key, fn) hotkeys[key] = fn end }
end

-- The helper as on macOS 26.4: it sees windows on every Space.
local spacesSeen = {}
package.preload["lua.helper"] = function()
  local M = { path = dir .. "/bin/spacectl" }
  local function info(w)
    return { id = w._id, pid = w._app._pid, spaces = { w.space }, fullscreen = spaceById(w.space).type == "fullscreen",
      x = w.f.x, y = w.f.y, w = w.f.w, h = w.f.h }
  end
  function M.capabilities() return { move = true, focus = true, macos = "26.4" } end
  function M.canMove() return true end
  function M.canFocus() return true end
  function M.windowIsOnSpace(wid, sid) return windows[wid] ~= nil and windows[wid].space == sid end
  function M.moveWindowToSpace(win, sid)
    local id = type(win) == "number" and win or win:id()
    windows[id].space = sid
    return true
  end
  function M.focusSpace(sid)
    current = sid
    spacesSeen[sid] = true
    return true
  end
  function M.windowsForApp(a)
    local out = {}
    for _, w in ipairs(windowsOf(a)) do table.insert(out, info(w)) end
    return out
  end
  function M.allWindows()
    local out = {}
    for _, id in ipairs(zorder) do table.insert(out, info(windows[id])) end
    return out
  end
  function M.pidsWithWindows()
    local pids = {}
    for _, w in pairs(windows) do pids[w._app._pid] = true end
    return pids
  end
  return M
end

package.preload["lua.config"] = function()
  local presets = {
    work = {
      name = "Work",
      spaces = { main = 2 },
      layout = {
        -- Two Terminal windows side by side; Terminal has one open.
        { name = "Terminal", monitor = "main", space = 1, pos = "left" },
        { name = "Terminal", monitor = "main", space = 1, pos = "right" },
        -- Chrome by window title. Only the Personal window is open (on
        -- desktop 1, which is not showing); the Work one opens from a menu.
        { name = "Google Chrome", monitor = "main", space = 2, pos = "left", window = "personal" },
        { name = "Google Chrome", monitor = "main", space = 2, pos = "right", window = "Work",
          newWindow = { "Profiles", "Work" } },
        -- Not running yet; an exact frame.
        { name = "Notes", monitor = "main", space = 2, pos = "custom", frame = { 0.25, 0.1, 0.5, 0.8 } },
        -- Twice, but Cmd+N does nothing in it: one window is placed, the
        -- other is reported and the run goes on.
        { name = "Mute", monitor = "main", space = 1, pos = "max" },
        { name = "Mute", monitor = "main", space = 1, pos = "max" },
      },
    },
  }
  return {
    keepAlive = {}, saveBeforeQuit = {}, quitOthers = false, killFallback = true,
    numbering = "position", menubar = false, presets = presets,
    bindings = { { mods = { "cmd" }, key = "W", preset = presets.work } },
  }
end

local terminal = newApp("Terminal")
local term1 = newWindow(terminal, 2, "zsh")
local chrome = newApp("Google Chrome", { menu = {
  ["Profiles > Work"] = function(a) newWindow(a, current, "New Tab - Work") end,
} })
local personal = newWindow(chrome, 1, "Inbox - Personal")
local mute = newApp("Mute", { cmdN = false })
newWindow(mute, 2, "Mute")
local movie = newApp("Movie")
local movieWin = newWindow(movie, 3, "Movie", { x = 0, y = 0, w = 1000, h = 800 })
local pigeon = newApp("SpacePigeon", { bundle = "com.louivers.spacepigeon" })
newWindow(pigeon, 2, "SpacePigeon Configuration")
-- An app that runs as "Code" but is named by its file name in presets.
local code = newApp("Code", { file = "Visual Studio Code" })
newWindow(code, 2, "main.lua", { x = 100, y = 50, w = 300, h = 200 })
current = 2

dofile("lua/init.lua")
hotkeys["W"]()

local checks = {}
local function check(name, ok) table.insert(checks, { name, ok and true or false }) end

local terms = windowsOf(terminal)
local term2
for _, w in ipairs(terms) do if w ~= term1 then term2 = w end end
check("Terminal got a second window with Cmd+N", #terms == 2 and #keys == 2 and keys[1] == "cmd+n@Terminal")
check("first Terminal entry keeps the open window, on the left of desktop 1", term1.space == 1 and term1.f.x == 0 and term1.f.w == 500)
check("second Terminal entry gets the new window, on the right", term2 and term2.space == 1 and term2.f.x == 500 and term2.f.w == 500)

local chromeWins = windowsOf(chrome)
local work
for _, w in ipairs(chromeWins) do if w ~= personal then work = w end end
check("Chrome's title was read on the desktop it is on", spacesSeen[1] == true)
check("Chrome Work window opened from Profiles > Work", #chromeWins == 2 and work and work._title == "New Tab - Work"
  and menus[1] == "Google Chrome: Profiles > Work")
check("Chrome Personal window (by title) on the left of desktop 2", personal.space == 2 and personal.f.x == 0 and personal.f.w == 500)
check("Chrome Work window on the right of desktop 2", work and work.space == 2 and work.f.x == 500)

local notesWin = apps.Notes and windowsOf(apps.Notes)[1]
check("Notes launched and placed at its custom frame", notesWin and notesWin.space == 2 and notesWin.f.x == 250
  and notesWin.f.y == 80 and notesWin.f.w == 500 and notesWin.f.h == 640)

check("Mute keeps one window, placed", #windowsOf(mute) == 1 and windowsOf(mute)[1].space == 1)
check("a missing window is reported and the run goes on", alerts[#alerts] == "Work workspace ready, 1 app(s) not placed")
check("the fullscreen app outside the preset is left alone", movieWin.space == 3)

-- Running it again (with the right Terminal in front now) keeps every
-- window where it is and opens nothing new.
term2:focus()
local keysBefore, menusBefore = #keys, #menus
hotkeys["W"]()
check("second run opens no Terminal or Chrome window", #windowsOf(terminal) == 2 and #windowsOf(chrome) == 2
  and #menus == menusBefore and keys[keysBefore + 1] == "cmd+n@Mute" and #keys == keysBefore + 1)
check("second run does not swap the Terminal windows", term1.f.x == 0 and term2.f.x == 500)

-- Snapping a frame to a named position.
local layout = require("lua.layout")
local s = screen.frame()
local function snapped(x, y, w, h) return (layout.snap({ x = x, y = y, w = w, h = h }, s)) end
check("snap: left half", snapped(0, 0, 500, 800) == "left")
check("snap: a Terminal a few points short is still the left half", snapped(0, 0, 493, 789) == "left")
check("snap: whole screen is max", snapped(0, 0, 1000, 800) == "max")
check("snap: center third", snapped(333, 0, 334, 800) == "center-third")
check("snap: bottom right quarter", snapped(500, 400, 500, 400) == "bottom-right")
local pos, frame = layout.snap({ x = 100, y = 50, w = 300, h = 200 }, s)
check("snap: anything else is custom, as fractions", pos == "custom" and frame[1] == 0.1 and frame[2] == 0.063
  and frame[3] == 0.3 and frame[4] == 0.25)

-- Saving the current layout.
local result = require("lua.capture").read()
local byName = {}
for _, e in ipairs(result.apps) do
  byName[e.name] = byName[e.name] or {}
  table.insert(byName[e.name], e)
end
check("capture: one monitor with 3 spaces", #result.monitors == 1 and result.monitors[1].spaces == 3)
check("capture: two Terminal entries, left then right, on space 1", byName.Terminal and #byName.Terminal == 2
  and byName.Terminal[1].pos == "left" and byName.Terminal[2].pos == "right" and byName.Terminal[1].space == 1)
check("capture: Chrome left then right on space 2", byName["Google Chrome"] and byName["Google Chrome"][1].pos == "left"
  and byName["Google Chrome"][2].pos == "right" and byName["Google Chrome"][1].space == 2)
check("capture: Notes as a custom frame", byName.Notes and byName.Notes[1].pos == "custom"
  and byName.Notes[1].frame[1] == 0.25 and byName.Notes[1].frame[4] == 0.8)
check("capture: the fullscreen app at space 3", byName.Movie and byName.Movie[1].pos == "fullscreen" and byName.Movie[1].space == 3)
check("capture: apps by file name", byName["Visual Studio Code"] ~= nil and byName.Code == nil)
check("capture: SpacePigeon itself is left out", byName.SpacePigeon == nil)
check("capture: sorted by space, then left to right", result.apps[1].space == 1 and result.apps[1].name == "Terminal"
  and result.apps[#result.apps].name == "Movie")

-- The URL event the config editor uses writes the file, and remembers the
-- windows so setting the preset up does not swap them.
settings["spacepigeon.windows"] = nil
urls.captureLayout()
local f = io.open(dir .. "/spacepigeon_capture.json")
local text = f and f:read("a") or ""
if f then f:close() end
check("capture file written", text:find('"pos":"custom"') ~= nil and text:find('"monitors":%[{"spaces":3}%]') ~= nil)
check("capture file has no window ids", text:find('"id"') == nil)
local memory = settings["spacepigeon.windows"] or {}
check("capture remembers each Terminal window in order", memory.terminal and memory.terminal[1] == term1._id
  and memory.terminal[2] == term2._id)

-- Quitting other apps keeps an app the preset names by its file name.
local quit = require("lua.config")
quit.quitOthers = true
quit.presets.work.layout = { { name = "Visual Studio Code", monitor = "main", space = 2, pos = "max" } }
hotkeys["W"]()
check("an app named by its file name is not quit", code._running and not terminal._running)

local failed = 0
for _, c in ipairs(checks) do
  print((c[2] and "PASS  " or "FAIL  ") .. c[1])
  if not c[2] then failed = failed + 1 end
end
print("alerts: " .. table.concat(alerts, " | "))
print(failed == 0 and "\nwindow checks pass" or ("\n" .. failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
