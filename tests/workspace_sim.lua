-- Smoke test of the whole workspace flow against a fake macOS.
-- Run from the project root: lua tests/workspace_sim.lua
package.path = "./?.lua;" .. package.path

local clock = 0
local spacesList = { { id = 1, type = "user" }, { id = 2, type = "user" } }
local current = 1
local winSpace, windows, apps = {}, {}, {}
local hotkeys, alerts, killed, keys = {}, {}, {}, {}
local settings, timers = {}, {}
local menu, screenChanged
local nextWin = 500

local screen = {
  id = function() return 1 end,
  name = function() return "Sim Display" end,
  frame = function() return { x = 0, y = 0, w = 1000, h = 800 } end,
}

local function spaceById(id)
  for i, s in ipairs(spacesList) do if s.id == id then return s, i end end
end

local focusedWin
local function newWindow(appRec, sid)
  nextWin = nextWin + 1
  local w = { _id = nextWin, _app = appRec, frame = nil }
  function w:id() return self._id end
  function w:isStandard() return true end
  function w:isMinimized() return false end
  function w:subrole() return "AXStandardWindow" end
  function w:focus() focusedWin = self end
  function w:screen() return screen end
  function w:application() return self._app end
  function w:setFrame(f) self.frame = f end
  function w:setFullScreen() error("not used in this test") end
  windows[w._id] = w
  winSpace[w._id] = sid
  table.insert(appRec._wins, w)
  return w
end

local function newApp(name, running)
  local a = { _name = name, _wins = {}, _running = running }
  function a:name() return self._name end
  function a:pid() return 42 end
  function a:kind() return 1 end
  function a:isRunning() return self._running end
  function a:isHidden() return false end
  -- Like real Accessibility: only windows on the active Space are visible.
  function a:mainWindow()
    for _, w in ipairs(self._wins) do if winSpace[w._id] == current then return w end end
    return nil
  end
  function a:allWindows()
    local out = {}
    for _, w in ipairs(self._wins) do if winSpace[w._id] == current then table.insert(out, w) end end
    return out
  end
  -- macOS with "switch to a Space with open windows" jumps to the app's Space.
  function a:activate() if self._wins[1] then current = winSpace[self._wins[1]._id] end end
  function a:kill() self._running = false; table.insert(killed, self._name) end
  function a:kill9() self:kill() end
  apps[name] = a
  return a
end

os.execute("rm -rf /tmp/spacepigeon-wsim && mkdir -p /tmp/spacepigeon-wsim")

hs = {
  configdir = "/tmp/spacepigeon-wsim",
  fs = { attributes = function() return nil end },
  execute = function(cmd) return (cmd:find("mru%-spaces") and "0\n" or ""), false end,
  json = {
    decode = function() return nil end,
    encode = function(t) return "{\"lvl\":\"" .. tostring(t.lvl) .. "\",\"ev\":\"" .. tostring(t.ev) .. "\",\"msg\":\"" .. tostring(t.msg):gsub('"', "'") .. "\"}" end,
  },
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
    doAfter = function(_, fn)
      table.insert(timers, fn)
      return { stop = function() end }
    end,
  },
  eventtap = {
    keyStroke = function(mods, key, _, target)
      table.insert(keys, table.concat(mods, "+") .. "+" .. key .. "@" .. (target and target:name() or "?"))
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
      function m:setMenu(fn) menu = fn end
      return m
    end,
  },
  urlevent = { bind = function() end },
  -- `open -a Name` starts the app right away in this fake.
  task = {
    new = function(_, _, args)
      return { start = function() hs.application.launchOrFocus(args[#args]) end }
    end,
  },
  osascript = { applescript = function() return true end },
  window = { get = function(id) return windows[id] end },
  screen = {
    primaryScreen = function() return screen end,
    allScreens = function() return { screen } end,
    watcher = {
      new = function(fn)
        screenChanged = fn
        return { start = function() end }
      end,
    },
  },
  application = {
    get = function(name)
      local a = apps[name]
      if a and a._running then return a end
      -- Like the real one, it can return an app whose name only starts the same.
      for n, other in pairs(apps) do
        if other._running and n:sub(1, #name) == name then return other end
      end
      return nil
    end,
    runningApplications = function()
      local out = {}
      for _, a in pairs(apps) do if a._running then table.insert(out, a) end end
      return out
    end,
    launchOrFocus = function(name)
      local a = apps[name] or newApp(name, true)
      a._running = true
      if #a._wins == 0 then newWindow(a, current) end
    end,
  },
  spaces = {
    spacesForScreen = function()
      local out = {}
      for _, s in ipairs(spacesList) do table.insert(out, s.id) end
      return out
    end,
    spaceType = function(id) local s = spaceById(id); return s and s.type end,
    windowSpaces = function(wid) return winSpace[wid] and { winSpace[wid] } or {} end,
    windowsForSpace = function(sid)
      local out = {}
      for wid, s in pairs(winSpace) do if s == sid then table.insert(out, wid) end end
      return out
    end,
    activeSpaceOnScreen = function() return current end,
    focusedSpace = function() return current end,
    gotoSpace = function(sid) current = sid end,
    moveWindowToSpace = function(wid, sid) winSpace[wid] = sid end,
    addSpaceToScreen = function()
      table.insert(spacesList, { id = #spacesList + 100, type = "user" })
    end,
    removeSpace = function(sid) local _, i = spaceById(sid); table.remove(spacesList, i); return true end,
    closeMissionControl = function() end,
  },
}
coroutine.applicationYield = nil
math.randomseed(1)

package.preload["hs.spaces"] = function() return hs.spaces end
package.preload["hs.application"] = function() return hs.application end
package.preload["hs.hotkey"] = function()
  return { bind = function(mods, key, fn) hotkeys[key] = fn end }
end

-- Config: Notes is already running on desktop 1 but belongs on desktop 3;
-- Terminal is not running and belongs on desktop 2; Discord is running and
-- not in the preset, so it should be quit. Notes is set on the second
-- monitor, which is not connected: its one space goes after the main
-- monitor's two, so Notes still ends up on desktop 3.
package.preload["lua.config"] = function()
  local presets = {
    -- Only here so the menu bar has two presets to sort.
    chill = {
      name = "Chill",
      spaces = { main = 1 },
      layout = { { name = "Discord", monitor = "main", space = 1, pos = "max" } },
    },
    work = {
      name = "Work",
      spaces = { main = 2, secondary = 1 },
      layout = {
        { name = "Terminal", monitor = "main", space = 2, pos = "left" },
        { name = "Notes",    monitor = "secondary", space = 1, pos = "max" },
      },
      -- Only one monitor is connected, so this mode must be ignored.
      modes = {
        { monitors = 2, spaces = { main = 1, secondary = 1 }, layout = {
          { name = "Terminal", monitor = "main", space = 1, pos = "max" },
        } },
      },
    },
  }
  return {
    keepAlive = {},
    saveBeforeQuit = { "Discord" },
    quitOthers = true,
    followMonitors = true,
    killFallback = true,
    numbering = "position",
    presets = presets,
    bindings = { { mods = { "cmd" }, key = "W", preset = presets.work } },
  }
end

local notes = newApp("Notes", true)
local notesWin = newWindow(notes, 1)
local discord = newApp("Discord", true)
newWindow(discord, 1)
-- A background service whose name starts like an app in the preset (like
-- Apple's CursorUIViewService next to the Cursor editor). It must not be
-- mistaken for Terminal, and it must not be quit.
local service = newApp("TerminalUIViewService", true)
function service:kind() return 0 end
newWindow(service, 1)

dofile("lua/init.lua")
assert(hotkeys["W"], "hotkey was not bound")
hotkeys["W"]()

local desktops = {}
for _, s in ipairs(spacesList) do if s.type == "user" then table.insert(desktops, s.id) end end

local checks = {
  { "three desktops exist", #desktops == 3 },
  { "Discord was quit", killed[1] == "Discord" and #killed == 1 },
  { "Notes kept running (not relaunched)", notes._running and #notes._wins == 1 },
  { "Notes window moved to desktop 3", winSpace[notesWin._id] == desktops[3] },
  { "Notes window maximized", notesWin.frame and notesWin.frame.w == 1000 },
  { "Terminal launched on desktop 2", apps.Terminal and winSpace[apps.Terminal._wins[1]._id] == desktops[2] },
  { "service with a similar name left alone", service._running and winSpace[service._wins[1]._id] == 1 },
  { "Terminal on left half", apps.Terminal and apps.Terminal._wins[1].frame.w == 500 },
  { "ends on desktop 1", current == desktops[1] },
  { "reported ready", alerts[#alerts]:find("ready") ~= nil },
  { "Cmd+S sent to Discord before quitting it", keys[1] == "cmd+s@Discord" and #keys == 1 },
}

-- Menu bar: one item per preset, sorted by name; the last one set up is checked.
local items = menu and menu() or {}
table.insert(checks, { "menu bar lists presets by name, last one checked",
  items[1] and items[1].title == "Chill" and not items[1].checked
  and items[2] and items[2].title == "Work" and items[2].checked == true })

-- A monitor was unplugged (the last run had 2): the preset is set up again,
-- without quitting the app that was opened since.
local slack = newApp("Slack", true)
newWindow(slack, current)
local runsBefore = #alerts
require("lua.workspaces").lastRunScreens = 2
screenChanged()
timers[#timers]()
table.insert(checks, { "monitor change sets up the preset again", #alerts > runsBefore and alerts[#alerts]:find("ready") ~= nil })
table.insert(checks, { "monitor change does not quit apps", slack._running })

-- Same count again: nothing happens.
local runsAfter = #alerts
screenChanged()
timers[#timers]()
table.insert(checks, { "no rerun when the count is unchanged", #alerts == runsAfter })

local pickMode = require("lua.workspaces").pickMode
local work = require("lua.config").presets.work
local n1, s1, l1 = pickMode(work, 1)
local n2, s2, l2 = pickMode(work, 2)
table.insert(checks, { "no mode for 1 monitor: preset layout used", n1 == "Work" and s1 == work.spaces and l1 == work.layout })
table.insert(checks, { "2 monitors: the 2-monitor mode is used", n2 == "Work (2 monitors)" and s2 == work.modes[1].spaces and l2 == work.modes[1].layout })
table.insert(checks, { "alerts name the preset without a mode", alerts[1] == "Setting up Work workspace..." })

-- A focus app: the setup ends on its space with its window focused, also
-- when it is not on the main monitor's first space.
work.focus = "Notes"
local _, _, _, f1 = pickMode(work, 1)
table.insert(checks, { "pickMode returns the preset's focus app", f1 == "Notes" })
hotkeys["W"]()
table.insert(checks, { "focus app: ends on its space", current == winSpace[notesWin._id] and current ~= desktops[1] })
table.insert(checks, { "focus app: its window is focused", focusedWin == notesWin })

local logText = io.open("/tmp/spacepigeon-wsim/spacepigeon.log"):read("a")
table.insert(checks, { "log has a run start and end", logText:find('"run_start"') ~= nil and logText:find('"run_end"') ~= nil })
table.insert(checks, { "log names the quit app", logText:find("Discord") ~= nil })

local failed = 0
for _, c in ipairs(checks) do
  print((c[2] and "PASS  " or "FAIL  ") .. c[1])
  if not c[2] then failed = failed + 1 end
end
print("alerts: " .. table.concat(alerts, " | "))
print(failed == 0 and "\nworkspace flow passes" or ("\n" .. failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
