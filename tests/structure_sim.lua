-- Simulated macOS Spaces to test lua/structure.lua without a Mac.
-- Models what Tahoe 26 did in the logs ("Automatically rearrange Spaces" off):
--   * a new desktop goes after the last desktop (before trailing fullscreen
--     Spaces)
--   * a new fullscreen Space goes at the very end
-- macOS 27 puts a new desktop at the very end too (newDesktopAtEnd).
-- Mission Control drags are faked here; tests/mcdrag_sim.lua covers them.
-- Run from the project root: lua tests/structure_sim.lua
package.path = "./?.lua;" .. package.path

local clock = 0
local spacesList, current = {}, nil
local winSpace, winOrigin, windows = {}, {}, {}
local nextSpaceId = 1000
local counts = { add = 0, remove = 0, fsIn = 0, fsOut = 0 }
local settingsStore = {}
local stubborn = {}   -- window ids that ignore the first fullscreen request
local newDesktopAtEnd = false -- macOS 27

local function spaceById(id)
  for i, s in ipairs(spacesList) do
    if s.id == id then return s, i end
  end
end

local function newSpace(kind, at)
  nextSpaceId = nextSpaceId + 1
  local s = { id = nextSpaceId, type = kind }
  table.insert(spacesList, at or (#spacesList + 1), s)
  return s
end

-- Index right after the last desktop.
local function desktopSlot()
  local last = 0
  for i, s in ipairs(spacesList) do if s.type == "user" then last = i end end
  return last + 1
end

local screen = {
  id = function() return 1 end,
  name = function() return "Sim Display" end,
  frame = function() return { x = 0, y = 0, w = 100, h = 100 } end,
}

local function firstDesktop()
  for _, s in ipairs(spacesList) do if s.type == "user" then return s.id end end
end

local function makeWindow(id, sid)
  local w = { _id = id }
  function w:id() return self._id end
  function w:isStandard() return true end
  function w:focus() end
  function w:screen() return screen end
  function w:moveToScreen() end
  function w:setFrame() end
  function w:raise() end
  function w:isFullScreen() return spaceById(winSpace[self._id]).type == "fullscreen" end
  function w:setFullScreen(on)
    local s, idx = spaceById(winSpace[self._id])
    if on and s.type == "fullscreen" then return end
    if on and stubborn[self._id] then stubborn[self._id] = nil; return end
    if on then
      assert(s.type == "user", "entering fullscreen from a fullscreen space")
      counts.fsIn = counts.fsIn + 1
      winOrigin[self._id] = s.id
      local new = newSpace("fullscreen")
      winSpace[self._id] = new.id
      current = new.id
    else
      assert(s.type == "fullscreen", "exiting fullscreen from a desktop")
      counts.fsOut = counts.fsOut + 1
      table.remove(spacesList, idx)
      local origin = spaceById(winOrigin[self._id]) and winOrigin[self._id] or firstDesktop()
      winSpace[self._id] = origin
      current = origin
    end
  end
  windows[id] = w
  winSpace[id] = sid
  return w
end

local function makeApp(name)
  local a = { _name = name }
  function a:allWindows()
    local out = {}
    for _, w in pairs(windows) do table.insert(out, w) end
    return out
  end
  function a:name() return self._name end
  function a:pid() return 1 end
  function a:activate() end
  return a
end

os.execute("mkdir -p /tmp/spacepigeon-sim")

hs = {
  configdir = "/tmp/spacepigeon-sim",
  fs = { attributes = function() return nil end },
  execute = function() return "", false end,
  json = {
    decode = function() return nil end,
    encode = function(t) return "{\"msg\":\"" .. tostring(t.msg):gsub('"', "'") .. "\"}" end,
  },
  alert = { show = function(m) print("  [alert] " .. m) end },
  settings = {
    get = function(k) return settingsStore[k] end,
    set = function(k, v) settingsStore[k] = v end,
    clear = function(k) settingsStore[k] = nil end,
  },
  timer = {
    usleep = function(us) clock = clock + us / 1e6 end,
    secondsSinceEpoch = function() return clock end,
  },
  window = { get = function(id) return windows[id] end },
  screen = {
    primaryScreen = function() return screen end,
    allScreens = function() return { screen } end,
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
      table.sort(out)
      return out
    end,
    activeSpaceOnScreen = function() return current end,
    gotoSpace = function(sid) current = sid end,
    moveWindowToSpace = function(wid, sid)
      assert(spaceById(sid).type == "user", "moving to a fullscreen space")
      assert(spaceById(winSpace[wid]).type == "user", "moving a fullscreen window")
      winSpace[wid] = sid
    end,
    addSpaceToScreen = function()
      counts.add = counts.add + 1
      newSpace("user", (not newDesktopAtEnd) and desktopSlot() or nil)
    end,
    removeSpace = function(sid)
      if sid == current then return false, "showing" end
      local s, i = spaceById(sid)
      assert(s and s.type == "user", "removing a non-desktop")
      assert(sid ~= current, "removing the showing desktop")
      counts.remove = counts.remove + 1
      table.remove(spacesList, i)
      for wid, ws in pairs(winSpace) do
        if ws == sid then winSpace[wid] = firstDesktop() end
      end
      return true
    end,
    closeMissionControl = function() end,
  },
}
math.randomseed(1)

package.preload["hs.spaces"] = function() return hs.spaces end

-- Mission Control drags are tested in tests/mcdrag_sim.lua; here a fake
-- moves the Spaces directly, the same way (left to right).
local drags = 0
package.preload["lua.mcdrag"] = function()
  return {
    reorder = function(_, wanted)
      local listed = {}
      for _, sid in ipairs(wanted) do listed[sid] = true end
      for t = 1, #wanted do
        local _, src = spaceById(wanted[t])
        local target, placed = 1, true
        local first = 1
        if t > 1 then local _, prev = spaceById(wanted[t - 1]); target = prev + 1; first = prev + 1; placed = src > prev end
        for i = first, src - 1 do
          if listed[spacesList[i].id] then placed = false end
        end
        if not placed then
          local s = table.remove(spacesList, src)
          table.insert(spacesList, target, s)
          drags = drags + 1
        end
      end
      return true
    end,
  }
end
local structure = require("lua.structure")

-- Build a starting state from a pattern like "D a D b c D" (D = desktop,
-- letters = fullscreen windows of configured apps, X = an unlisted app).
local ids = { a = 11, b = 12, c = 13, d = 14, X = 99 }
local names = {}
for k, v in pairs(ids) do names[v] = k end

local function setup(pattern, onDesktop)
  spacesList, winSpace, winOrigin, windows = {}, {}, {}, {}
  stubborn = {}
  counts = { add = 0, remove = 0, fsIn = 0, fsOut = 0 }
  local lastDesktop
  for token in pattern:gmatch("%S+") do
    if token == "D" then
      lastDesktop = newSpace("user").id
    else
      local s = newSpace("fullscreen")
      makeWindow(ids[token], s.id)
      winOrigin[ids[token]] = lastDesktop
    end
  end
  for token in (onDesktop or ""):gmatch("%S+") do
    makeWindow(ids[token], firstDesktop())
  end
  current = firstDesktop()
end

local function pattern()
  local out = {}
  for _, s in ipairs(spacesList) do
    if s.type == "user" then
      table.insert(out, "D")
    else
      for wid, sid in pairs(winSpace) do
        if sid == s.id then table.insert(out, names[wid]) end
      end
    end
  end
  return table.concat(out, " ")
end

local app = makeApp("App")
local function items(spec)
  -- spec like "a@1 b@1 c@2": window a after desktop 1, ...
  local list = {}
  for name, after in spec:gmatch("(%a)@(%d+)") do
    table.insert(list, { app = app, id = ids[name], name = name, after = tonumber(after) })
  end
  return list
end

local failures = 0
local function case(title, start, onDesktop, desktopCount, spec, expect, opts)
  opts = opts or {}
  settingsStore = {}
  setup(start, onDesktop)
  for token in (opts.stubborn or ""):gmatch("%S+") do stubborn[ids[token]] = true end
  drags = 0
  local ok = structure.build(screen, desktopCount, items(spec), { reorder = opts.reorder ~= false })
  local got = pattern()
  local pass = ok and got == expect
  if not pass then failures = failures + 1 end
  print(string.format("%s  %-48s %-18s -> %-20s add=%d remove=%d fs_in=%d fs_out=%d drags=%d",
    pass and "PASS" or "FAIL", title, start, got, counts.add, counts.remove, counts.fsIn, counts.fsOut, drags))
  if not pass then print("      expected: " .. expect) end
end

-- With dragging (the default).
case("already right: nothing happens", "D a D b D", "", 3, "a@1 b@2", "D a D b D")
case("the log's case: Claude after 3, Marta after 5", "D D D D D D D a b", "", 7, "a@3 b@5", "D D D a D D b D D")
case("not fullscreen yet, two after the same desktop", "D D", "a b", 2, "b@1 a@1", "D b a D")
case("missing desktops are added, then the drag", "D a", "", 3, "a@2", "D D a D")
case("extra desktops are removed", "D a D D D", "", 2, "a@1", "D a D")
case("fullscreen app left of desktop 1", "a D D", "", 2, "a@1", "D a D")
case("unlisted fullscreen app is left in place", "D X D", "a", 2, "a@1", "D a X D")
case("app that ignores the first request", "D D", "a", 2, "a@1", "D a D", { stubborn = "a" })
case("fullscreen before desktop 1 (after = 0)", "D D", "a b", 2, "a@0 b@0", "a b D D")
case("before desktop 1, already there", "a D D", "", 2, "a@0", "a D D")

-- Without dragging: all fullscreen apps after the last desktop, in order.
local off = { reorder = false }
case("off: already right", "D D D a b", "", 3, "a@1 b@2", "D D D a b", off)
case("off: the log's case", "D D D D D D D a", "b", 7, "a@3 b@5", "D D D D D D D a b", off)
case("off: wrong order at the end is fixed", "D D a c b", "", 2, "a@1 b@1 c@2", "D D a b c", off)
case("off: app between desktops goes to the end", "D a D D", "", 3, "a@1", "D D D a", off)
case("off: same space number keeps list order", "D D", "a b", 2, "b@1 a@1", "D D b a", off)
case("off: missing desktops are added before the apps", "D a", "", 3, "a@2", "D D D a", off)
case("off: unlisted fullscreen app is ignored", "D X D", "a", 2, "a@1", "D X D a", off)

-- macOS 27: a new desktop goes after the fullscreen apps.
newDesktopAtEnd = true
case("27: missing desktops are added, then the drag", "D a", "", 3, "a@2", "D D a D")
case("27 off: missing desktops are added before the apps", "D a", "", 3, "a@2", "D D D a", off)
newDesktopAtEnd = false

print(failures == 0 and "\nall structure cases pass" or ("\n" .. failures .. " case(s) failed"))
os.exit(failures == 0 and 0 or 1)
