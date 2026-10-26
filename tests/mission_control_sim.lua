-- Tests switching, adding and removing Spaces (lua/space_utils.lua) against
-- a fake Mission Control in both places it lives: the Dock up to macOS 26,
-- used through hs.spaces, and WindowManager on macOS 27, where SpacePigeon
-- presses the buttons itself (lua/mission_control.lua).
-- Run from the project root: lua tests/mission_control_sim.lua
package.path = "./?.lua;" .. package.path

local clock = 0
local spacesList, current = {}, nil -- { id, type }, left to right
local nextId = 100
local mcOpen = false
local layout = "windowmanager"       -- or "dock"
local hsSpacesCalls = 0
local ignorePresses = 0              -- presses Mission Control ignores (still opening)

local screen = {
  id = function() return 1 end,
  name = function() return "Sim Display" end,
  frame = function() return { x = 0, y = 0, w = 1600, h = 900 } end,
}

local function indexOf(sid)
  for i, s in ipairs(spacesList) do
    if s.id == sid then return i end
  end
end

local function addDesktopAtEnd()
  nextId = nextId + 1
  table.insert(spacesList, { id = nextId, type = "user" })
end

local function remove(sid)
  local i = indexOf(sid)
  if not i or spacesList[i].type ~= "user" or sid == current then return false end
  table.remove(spacesList, i)
  return true
end

local function element(fields, childrenFn)
  return setmetatable(fields, {
    __index = function(_, key)
      if key == "AXChildren" then return childrenFn and childrenFn() or {} end
      return nil
    end,
  })
end

-- One button per Space, like Mission Control's Spaces bar.
local function spaceButton(s)
  return {
    AXDescription = s.type == "user" and "exit to Desktop" or "exit to full screen",
    performAction = function(self, action)
      if not mcOpen then return nil end
      if ignorePresses > 0 then
        ignorePresses = ignorePresses - 1
        return false
      end
      if action == "AXPress" then
        current = s.id
        mcOpen = false
        return self
      elseif action == "AXRemoveDesktop" then
        return remove(s.id) and self or false
      end
      return nil
    end,
  }
end

local list = element({ AXIdentifier = "mc.spaces.list" }, function()
  local out = {}
  for _, s in ipairs(spacesList) do table.insert(out, spaceButton(s)) end
  return out
end)
local addButton = {
  AXIdentifier = "mc.spaces.add",
  performAction = function(self)
    if not mcOpen then return nil end
    addDesktopAtEnd() -- macOS 27 puts it at the very end
    return self
  end,
}
local display = element({ AXIdentifier = "mc.display", AXDisplayID = 1 }, function()
  return {
    element({ AXIdentifier = "com.apple.mail.space.1" }), -- a window thumbnail
    element({ AXIdentifier = "mc.spaces" }, function() return { list, addButton } end),
  }
end)
local mc = element({ AXIdentifier = "mc" }, function() return layout == "dock" and { display } or {} end)
local dock = element({}, function() return mcOpen and { mc } or {} end)
local windowManager = element({}, function()
  return (mcOpen and layout == "windowmanager") and { display } or {}
end)

-- hs.spaces works with the Dock's elements only, like the real one. When a
-- call fails it closes Mission Control again, unless asked to leave it open.
local function viaDock(fn)
  return function(arg, closeMC)
    hsSpacesCalls = hsSpacesCalls + 1
    mcOpen = true
    local err = nil
    if layout ~= "dock" then
      err = "no display with specified id found"
    elseif ignorePresses > 0 then
      ignorePresses = ignorePresses - 1
      err = "Mission Control is still opening"
    end
    if err then
      if closeMC ~= false then mcOpen = false end
      return nil, err
    end
    return fn(arg, closeMC)
  end
end

os.execute("mkdir -p /tmp/spacepigeon-mcsim2")
hs = {
  configdir = "/tmp/spacepigeon-mcsim2",
  fs = { attributes = function() return nil end },
  execute = function() return "", false end,
  json = { decode = function() return nil end, encode = function(t) return tostring(t.msg) end },
  settings = { get = function() return nil end, set = function() end },
  alert = { show = function() end },
  timer = {
    usleep = function(us) clock = clock + us / 1e6 end,
    secondsSinceEpoch = function() return clock end,
  },
  screen = { allScreens = function() return { screen } end, primaryScreen = function() return screen end },
  application = {
    get = function(id)
      return (id == "com.apple.dock" or id == "com.apple.WindowManager") and { bundleID = id } or nil
    end,
  },
  spaces = {
    spacesForScreen = function()
      local out = {}
      for _, s in ipairs(spacesList) do table.insert(out, s.id) end
      return out
    end,
    spaceType = function(sid) local i = indexOf(sid); return i and spacesList[i].type end,
    activeSpaceOnScreen = function() return current end,
    openMissionControl = function() mcOpen = true end,
    closeMissionControl = function() mcOpen = false end,
    gotoSpace = viaDock(function(sid) current = sid; mcOpen = false; return true end),
    removeSpace = viaDock(function(sid, closeMC)
      if closeMC ~= false then mcOpen = false end
      return remove(sid) or nil
    end),
    addSpaceToScreen = viaDock(function()
      addDesktopAtEnd()
      mcOpen = false
      return true
    end),
  },
}
package.preload["hs.spaces"] = function() return hs.spaces end
package.preload["hs.axuielement"] = function()
  return {
    applicationElement = function(app) return app.bundleID == "com.apple.dock" and dock or windowManager end,
  }
end

local missionControl = require("lua.mission_control")
local spaceUtils = require("lua.space_utils")

-- "D D a" style: D = desktop, other tokens = fullscreen apps. Returns ids by
-- token ("D1", "D2", "a", ...); the first desktop is showing.
local function setup(pattern)
  spacesList, current, mcOpen, hsSpacesCalls, ignorePresses = {}, nil, false, 0, 0
  local ids, d = {}, 0
  for token in pattern:gmatch("%S+") do
    nextId = nextId + 1
    local kind = token == "D" and "user" or "fullscreen"
    table.insert(spacesList, { id = nextId, type = kind })
    if kind == "user" then
      d = d + 1
      ids["D" .. d] = nextId
      current = current or nextId
    else
      ids[token] = nextId
    end
  end
  return ids
end

local function show()
  local out = {}
  for _, s in ipairs(spacesList) do
    local name = s.type == "user" and "D" or "F"
    table.insert(out, s.id == current and ("[" .. name .. "]") or name)
  end
  return table.concat(out, " ")
end

local failures = 0
local function check(title, ok, wantShow)
  local got = show()
  local pass = ok and (not wantShow or got == wantShow) and not mcOpen
  if not pass then failures = failures + 1 end
  print(string.format("%s  %-48s %s", pass and "PASS" or "FAIL", title, got))
  if not pass then print("      expected " .. tostring(wantShow) .. ", Mission Control open: " .. tostring(mcOpen)) end
end

local function run(label)
  local ids = setup("D a D D b")
  check(label .. ": switch to a fullscreen app", spaceUtils.gotoSpaceAndWait(ids.a), "D [F] D D F")
  check(label .. ": switch to a desktop", spaceUtils.gotoSpaceAndWait(ids.D3), "D F D [D] F")

  ids = setup("D a D")
  ignorePresses = 1
  check(label .. ": press ignored once: tried again", spaceUtils.gotoSpaceAndWait(ids.a), "D [F] D")

  ids = setup("D a")
  local new = spaceUtils.addDesktop(screen)
  check(label .. ": add a desktop", new ~= nil and indexOf(new) == 3, "[D] F D")

  ids = setup("D a D D b")
  check(label .. ": remove two desktops", spaceUtils.removeDesktops({ ids.D2, ids.D3 }), "[D] F F")

  ids = setup("D D a")
  local refused = not spaceUtils.removeDesktops({ ids.D1 })
  check(label .. ": the showing desktop is not removed", refused, "[D] D F")
end

missionControl.inWindowManager = true
layout = "windowmanager"
run("macOS 27")
if hsSpacesCalls > 0 then
  failures = failures + 1
  print("FAIL  macOS 27 used hs.spaces " .. hsSpacesCalls .. " time(s)")
end

missionControl.inWindowManager = false
layout = "dock"
run("macOS 26")

-- What 2.1.0 did on macOS 27: hs.spaces cannot find Mission Control.
layout = "windowmanager"
local ids = setup("D a")
local switched = spaceUtils.gotoSpaceAndWait(ids.a)
check("hs.spaces on macOS 27 cannot switch", not switched, "[D] F")

print(failures == 0 and "\nall Mission Control cases pass" or ("\n" .. failures .. " case(s) failed"))
os.exit(failures == 0 and 0 or 1)
