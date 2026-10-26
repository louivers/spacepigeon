-- Tests lua/mcdrag.lua against a fake Mission Control.
-- The fake shows one thumbnail per Space in a row and handles a mouse drag
-- the way the real one did in testing: on release, the dragged Space is put
-- in front of the first thumbnail whose middle is right of the mouse.
-- Run from the project root: lua tests/mcdrag_sim.lua
package.path = "./?.lua;" .. package.path

local clock = 0
local order = {}      -- space ids, left to right
local names = {}      -- space id -> thumbnail name
local mcOpen = false
local mouse = { x = 5, y = 500 }
local pressedIndex = nil
local dragCount, rightDrags = 0, 0
local ignoreDrops = 0  -- how many drops to ignore (a slow Mission Control)
local mergeNext = false -- next drop lands on the left neighbour (Split View)
local offNext = 0       -- how many drops land one place too far right

local shiftAfterDrop = false -- after the next drop the bar sits 22 pt to the left for 1.5 s
local shiftUntil = -1

-- While a drag hovers over a gap for OPEN_DELAY, Mission Control opens it:
-- the thumbnails right of it move right.
local OPEN_DELAY = 0.15
local gapRight, gapSince = nil, 0 -- right neighbour of the hovered gap, and since when

-- The bar can open small (names only, a strip at the top of the screen).
-- Like the real one, it grows only when a mouse move enters it from
-- outside; putting the pointer on it directly does not count.
-- barMode: "big" (opens grown), "small" (opens small), "stuck" (never grows).
local barMode = "big"
local grown = true

local function smallFrame(i)
  return { x = 110.5 + (i - 1) * 90, y = 0.5, w = 80, h = 24 }
end

local function baseFrame(i)
  if not grown then return smallFrame(i) end
  local shift = clock < shiftUntil and -22 or 0
  -- Fractional like on a Retina screen (positions such as 177.5).
  return { x = 100.5 + shift + (i - 1) * 120, y = 20.5, w = 100, h = 60 }
end

-- Like the real one (lua/dragbench.lua results): a thumbnail is only
-- picked up when the first move after pressing is small (the nudge);
-- otherwise no gap ever opens.
local PICKUP = 20
local downPos, pickedUp = nil, nil
local noPickup = 0 -- how many drags Mission Control does not pick up, nudge or not
-- macOS 27: the first press on a Space's thumbnail picks nothing up, and
-- letting go over a thumbnail that was not picked up is a click, which
-- opens that Space and closes Mission Control.
local firstPressIgnored = false
local pressedBefore, pressIgnored = {}, false
local clickCloses, clicks = false, 0

local function gapOpen()
  return pickedUp and gapRight ~= nil and clock - gapSince >= OPEN_DELAY
end

local function frameOf(i)
  local f = baseFrame(i)
  if pressedIndex and gapOpen() and i >= gapRight and i ~= pressedIndex then f.x = f.x + 80 end
  return f
end

local function hoverGap(p)
  local right = #order + 1
  for j = 1, #order do
    local f = baseFrame(j)
    if j ~= pressedIndex and f.x + f.w / 2 > p.x then right = j break end
  end
  if right ~= gapRight then gapRight, gapSince = right, clock end
end

local function thumbAt(p)
  for i = 1, #order do
    local f = frameOf(i)
    if p.x >= f.x and p.x <= f.x + f.w and p.y >= f.y and p.y <= f.y + f.h then return i end
  end
  return nil
end

local function element(fields, childrenFn)
  return setmetatable(fields, {
    __index = function(_, key)
      if key == "AXChildren" then return childrenFn and childrenFn() or {} end
      return nil
    end,
  })
end

-- macOS 27.0 reports a thumbnail's centre as its position.
local centeredFrames = false
local list = element({ AXIdentifier = "mc.spaces.list", AXFrame = { x = 0, y = 0, w = 1600, h = 100 } }, function()
  local out = {}
  for i, sid in ipairs(order) do
    local f = frameOf(i)
    if centeredFrames then f = { x = f.x + f.w / 2, y = f.y + f.h / 2, w = f.w, h = f.h } end
    table.insert(out, { AXDescription = names[sid], AXFrame = f })
  end
  return out
end)
local display = element({ AXIdentifier = "mc.display", AXDisplayID = 1 }, function()
  return {
    element({ AXIdentifier = "com.apple.mail.space.1" }), -- a window thumbnail
    element({ AXIdentifier = "mc.spaces" }, function() return { list } end),
  }
end)
-- Up to macOS 26 Mission Control's elements are in the Dock. From macOS 27
-- they are in WindowManager, and the Dock only has an empty "mc" group.
local layout = "dock"
local mc = element({ AXIdentifier = "mc" }, function() return layout == "dock" and { display } or {} end)
local dock = element({}, function() return mcOpen and { mc } or {} end)
local windowManager = element({}, function()
  return (mcOpen and layout == "windowmanager") and { display } or {}
end)

local screen = {
  id = function() return 1 end,
  name = function() return "Sim Display" end,
  frame = function() return { x = 0, y = 0, w = 1600, h = 900 } end,
}

os.execute("mkdir -p /tmp/spacepigeon-mcsim")
hs = {
  configdir = "/tmp/spacepigeon-mcsim",
  fs = { attributes = function() return nil end, mkdir = function(p) os.execute("mkdir -p '" .. p .. "'") end },
  hotkey = { bind = function() return { delete = function() end } end },
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
  mouse = {
    absolutePosition = function(p)
      if p then mouse = { x = p.x, y = p.y } end
      return { x = mouse.x, y = mouse.y }
    end,
  },
  eventtap = {
    event = {
      types = { leftMouseDown = "down", leftMouseDragged = "drag", leftMouseUp = "up", mouseMoved = "move" },
      newMouseEvent = function(kind, p)
        return {
          post = function()
            if kind == "move" and mcOpen and not grown and barMode ~= "stuck" then
              local f = smallFrame(1)
              local function inBar(q) return q.y >= f.y and q.y <= f.y + f.h end
              if not inBar(mouse) and inBar(p) then grown = true end
            end
            mouse = { x = p.x, y = p.y }
            -- A small bar picks nothing up: down and up on a name is a
            -- click, which switches Space and closes Mission Control.
            if not grown and kind == "down" then pressedIndex = nil end
            if not grown and kind == "up" then
              local f = smallFrame(1)
              if p.y >= f.y and p.y <= f.y + f.h then mcOpen = false end
              return
            end
            if not grown then return end
            if kind == "up" and pressedIndex and pickedUp == false then
              -- Nothing was picked up, so nothing moves.
              if clickCloses and thumbAt(p) == pressedIndex then
                clicks = clicks + 1
                mcOpen = false
              end
              pressedIndex, gapRight = nil, nil
              return
            end
            if kind == "drag" and pressedIndex then
              if pickedUp == nil then
                pickedUp = math.abs(p.x - downPos.x) <= PICKUP and noPickup == 0 and not pressIgnored
                if noPickup > 0 then noPickup = noPickup - 1 end
              end
              hoverGap(p)
            end
            local outside = kind == "up" and pressedIndex and p.y > 100
            -- The thumbnail under the drop, while the gap is still open.
            local hit = kind == "up" and pressedIndex and thumbAt(p) or nil
            if kind == "up" and pressedIndex and not outside and not mergeNext and not gapOpen()
              and hit ~= pressedIndex then
              -- Dropped before the gap opened, next to a fullscreen app: it
              -- merges with it, even in the middle of the gap.
              local left, right = nil, nil
              for j = 1, #order do
                local f = baseFrame(j)
                if j ~= pressedIndex then
                  if f.x + f.w / 2 < p.x then left = j elseif not right then right = j end
                end
              end
              local function fs(j) return j and names[order[j]]:match("^exit to full screen") end
              if fs(right) or fs(left) then mergeNext = true end
            end
            if kind == "down" then
              gapRight, downPos, pickedUp = nil, { x = p.x, y = p.y }, nil
              pressedIndex = thumbAt(p)
              local sid = pressedIndex and order[pressedIndex]
              pressIgnored = firstPressIgnored and sid ~= nil and not pressedBefore[sid]
              if sid then pressedBefore[sid] = true end
            elseif outside then
              -- Let go below the bar: the thumbnail goes back, nothing moves.
              pressedIndex = nil
            elseif kind == "up" and pressedIndex and ignoreDrops > 0 then
              pressedIndex = nil
              ignoreDrops = ignoreDrops - 1
            elseif kind == "up" and pressedIndex and (mergeNext or (hit and hit ~= pressedIndex
                and names[order[hit]]:match("^exit to full screen"))) then
              -- Dropped on a fullscreen thumbnail instead of a gap: the two
              -- merge (Split View).
              mergeNext = false
              local src = pressedIndex
              pressedIndex = nil
              local onto = hit
              if onto == src then onto = nil end
              if not onto then
                for j = 1, #order do
                  local f = frameOf(j)
                  if j ~= src and f.x + f.w / 2 > p.x then onto = j - 1 break end
                end
              end
              if onto and onto >= 1 then
                local into = order[onto]
                local sid = table.remove(order, src)
                names[into] = names[into] .. " & " .. names[sid]:gsub("^exit to full screen ", "")
              end
              dragCount = dragCount + 1
            elseif kind == "up" and pressedIndex then
              local src = pressedIndex
              pressedIndex = nil
              local before = nil
              for j = 1, #order do
                local f = frameOf(j)
                if j ~= src and f.x + f.w / 2 > p.x then before = order[j] break end
              end
              local sid = table.remove(order, src)
              local at = #order + 1
              for j, s in ipairs(order) do if s == before then at = j break end end
              if offNext > 0 then
                offNext = offNext - 1
                at = math.min(at + 1, #order + 1)
              end
              table.insert(order, at, sid)
              dragCount = dragCount + 1
              if shiftAfterDrop then shiftAfterDrop, shiftUntil = false, clock + 1.5 end
              if at > src then rightDrags = rightDrags + 1 end
            end
            if kind == "up" then gapRight = nil end
          end,
        }
      end,
    },
  },
  spaces = {
    spacesForScreen = function() local out = {} for i, s in ipairs(order) do out[i] = s end return out end,
    openMissionControl = function() mcOpen = true; grown = barMode == "big" end,
    closeMissionControl = function() mcOpen = false end,
    spaceType = function(sid) return names[sid]:match("^exit to full screen") and "fullscreen" or "user" end,
    activeSpaceOnScreen = function() return order[1] end,
  },
}
package.preload["hs.spaces"] = function() return hs.spaces end
package.preload["hs.axuielement"] = function()
  return {
    applicationElement = function(app) return app.bundleID == "com.apple.dock" and dock or windowManager end,
  }
end

local mcdrag = require("lua.mcdrag")

-- "D1 D2 a b" style: D = desktop, letters = fullscreen apps.
local function setup(pattern)
  order, names = {}, {}
  local id, d = 0, 0
  local byToken = {}
  for token in pattern:gmatch("%S+") do
    id = id + 1
    table.insert(order, id)
    if token == "D" then
      d = d + 1
      names[id] = "exit to Desktop " .. d
      byToken["D" .. d] = id
    else
      names[id] = "exit to full screen " .. token
      byToken[token] = id
    end
  end
  return byToken
end

local function show()
  local out = {}
  for _, sid in ipairs(order) do
    local n = names[sid]:gsub("^exit to full screen ", ""):gsub("^exit to Desktop %d+", "D")
    table.insert(out, n)
  end
  return table.concat(out, " ")
end

-- tests/dragbench_sim.lua loads this file for its fake Mission Control.
if MCSIM_LIBRARY then
  return {
    setup = setup,
    show = show,
    state = function() return order, names end,
    clock = function() return clock end,
  }
end

local failures = 0
local lastInfo = nil
local function case(title, start, wantedTokens, expect, ignore, shouldFail, merge, off, rights, shift, nopick)
  ignoreDrops = ignore or 0
  noPickup = nopick or 0
  pressedBefore, clicks = {}, 0
  shiftAfterDrop, shiftUntil = shift or false, -1
  offNext = off or 0
  mergeNext = merge or false
  local ids = setup(start)
  local wanted = {}
  for token in wantedTokens:gmatch("%S+") do table.insert(wanted, ids[token]) end
  dragCount, rightDrags, mouse = 0, 0, { x = 5, y = 500 }
  local t0 = clock
  local ok, info = mcdrag.reorder(screen, wanted)
  local took = clock - t0
  lastInfo = info
  local got = show()
  local pass = (ok == not shouldFail) and got == expect and rightDrags == (rights or 0) and mouse.x == 5 and mouse.y == 500 and not mcOpen
  if not pass then failures = failures + 1 end
  print(string.format("%s  %-42s %-20s -> %-20s drags=%d %.1fs", pass and "PASS" or "FAIL", title, start, got, dragCount, took))
  if not pass then
    print(string.format("      expected %s (right drags %d, mouse %d,%d, open %s)", expect, rightDrags, mouse.x, mouse.y, tostring(mcOpen)))
  end
end

case("the real test: Claude after desktop 3", "D D D D D D D a b", "D1 D2 D3 a D4 D5 b D6 D7", "D D D a D D b D D")
case("already in order: Mission Control not opened", "D a D", "D1 a D2", "D a D")
case("two apps after one desktop, wrong order", "D D a b", "D1 b a D2", "D b a D")
case("app left of desktop 1", "a D D", "D1 a D2", "D a D", 0, false, false, 0, 1)
case("unlisted app in between stays", "D X D a", "D1 a D2", "D a X D")
case("three apps spread out", "D D D a b c", "D1 a D2 b D3 c", "D a D b D c")
case("fast drop ignored: slow retry works", "D D a", "D1 a D2", "D a D", 1)
case("all three drops ignored: gives up cleanly", "D D a", "D1 a D2", "D D a", 3, true)
case("drop lands one place off: tried again", "D D D D D a", "D1 a D2 D3 D4 D5", "D a D D D D", 0, false, false, 1)
case("to the front, past a fullscreen app", "a D b c", "c a D1 b", "c a D b", 0, false, false, 0, 1)
case("to the front, next to a fullscreen app", "a c D", "c a D1", "c a D", 0, false, false, 0, 1)
case("to the front, past a desktop", "D a c", "c D1 a", "c D a", 0, false, false, 0, 1)
case("drop one off, then the bar sits shifted", "a D D D b", "b a D1 D2 D3", "b a D D D", 0, false, false, 1, 1, true)
case("not picked up: let go over itself, retry", "D a b c", "D1 c a b", "D c a b", 0, false, false, 0, 0, false, 1)
case("PhD - Reading, 12 Spaces", "b m D D D D e c u o t z", "b c u o t m e D1 D2 z D3 D4", "b c u o t m e D D z D D")
case("PhD - Reading, run of 16:16", "b D D D D m e c u o t z", "b c u o t m e D1 D2 z D3 D4", "b c u o t m e D D z D D")
case("drop made a Split View: reported", "D a c b", "D1 a b c", "D a & b c", 0, true, true)
if not (lastInfo and lastInfo.merged) then
  failures = failures + 1
  print("FAIL  the Split View was not reported as merged")
end

-- Run of 16:41: the bar opened small after desktops were removed.
barMode = "small"
case("bar opens small: grown by entering it", "b c u o t m e D z", "b c u o z t m e D1", "b c u o z t m e D")
barMode = "stuck"
case("bar stays small: gives up without a click", "b c u o t m e D z", "b c u o z t m e D1", "b c u o t m e D z", 0, true)
barMode = "big"

-- macOS 27: Mission Control in WindowManager. A new desktop goes at the
-- very end there, after the fullscreen apps.
layout = "windowmanager"
centeredFrames = true
require("lua.mission_control").inWindowManager = true
case("macOS 27: PhD - Coding of 13:32", "e D c b t u o m k", "b c u o m k e t D1", "b c u o m k e t D", 0, false, false, 0, 1)
case("macOS 27: new desktop landed at the end", "D a b D", "D1 a D2 b", "D a D b")
-- The first drag of a new Space is not picked up there, and letting go over
-- its thumbnail would be a click: it lets go on the empty bar instead and
-- tries again, without a click.
firstPressIgnored, clickCloses = true, true
for _, c in ipairs({
  { "macOS 27: first drag not picked up: no click", "D D a", "D1 a D2", "D a D" },
  { "macOS 27: first drags not picked up, two apps", "D D a b", "D1 b D2 a", "D b D a" },
}) do
  case(c[1], c[2], c[3], c[4])
  if clicks > 0 then
    failures = failures + 1
    print("FAIL  let go over a thumbnail that was not picked up (a click)")
  end
end
firstPressIgnored, clickCloses = false, false
require("lua.mission_control").inWindowManager = false
centeredFrames = false
case("macOS 27 layout, found from the Dock side too", "D D a", "D1 a D2", "D a D")
layout = "dock"

print(failures == 0 and "\nall drag cases pass" or ("\n" .. failures .. " case(s) failed"))
os.exit(failures == 0 and 0 or 1)
