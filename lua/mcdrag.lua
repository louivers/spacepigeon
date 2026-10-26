-- Reorders Spaces by dragging their thumbnails in Mission Control.
--
-- macOS has no API to move a Space, but Mission Control lets you drag one in
-- its Spaces bar. This does that drag with synthetic mouse events, using the
-- exact thumbnail positions that Mission Control reports via Accessibility.
-- All drags for one screen happen in one Mission Control session. The mouse
-- is put back where it was afterwards.

local spaces = require("hs.spaces")
local spaceUtils = require("lua.space_utils")
local missionControl = require("lua.mission_control")
local log = require("lua.log")

local M = {}

local OPEN_TIMEOUT = 2.0   -- wait for Mission Control's Accessibility tree
local GROW_TIMEOUT = 0.4   -- the Spaces bar grows when the mouse is over it
local LAND_TIMEOUT = 0.8   -- wait for a drop to show up in the bar
local CLOSE_TIMEOUT = 0.6  -- wait for Mission Control to close
local GAP_TIMEOUT = 0.6    -- wait for Mission Control to open the gap during a drag
-- The Spaces bar is either small (only names, ~24 pt high, a strip at the
-- top of the screen) or grown (thumbnails, ~76-90 pt). Only grown
-- thumbnails can be dragged.
local GROWN_HEIGHT = 40

-- Each drag is tried quick first. If Mission Control ignores it, it is done
-- again carefully. Both were picked by the drag test (lua/dragbench.lua,
-- 384 ways, 1272 drags on macOS 26.7):
--
-- - Nudge: after pressing, move the pointer 3 x 3 pt before the real move.
--   Without it Mission Control often did not pick the thumbnail up when the
--   first move was long (47% of drags made a Split View; with it 17%, all
--   of those at the far left end, see below).
-- - Let go only once Mission Control has opened the gap: while a drag
--   hovers over a gap, the two neighbours move apart (from ~27 pt to
--   ~180 pt), and the Accessibility frames show that live. Dropping after a
--   fixed wait instead made a Split View in 36-42% of drags. The bar also
--   moves ~22 pt while a thumbnail is held, so the pointer follows the
--   live gap. (Do not overshoot the gap either: 40 pt landed on the
--   neighbour.)
-- - With both, all 276 drags into a gap between two fullscreen apps
--   worked, whatever the hold, the speed, or the wait after the previous
--   drop. Quick (hold 0.05 s, jump): ~270 ms per drag.
-- - Dropping at an end of the bar (before the first or after the last
--   thumbnail) went wrong in 20% of drags even like this, so ends are
--   reached with two gap drops (see the loop below).
local QUICK = { name = "quick", hold = 0.05, step = math.huge }
local SLOW = { name = "careful", hold = 0.15, step = 40 }
local STEP_WAIT = 0.008

-- The Spaces bar (an AX element) for one screen, or nil and a reason. In
-- the Dock up to macOS 26, in WindowManager from macOS 27.
local spacesBar = missionControl.spacesList

-- Thumbnails left to right: { name = ..., frame = { x, y, w, h } }.
local function thumbnails(screen)
  local bar, err = spacesBar(screen)
  if not bar then return nil, err end
  return missionControl.thumbnails(bar)
end

local function center(f)
  return { x = f.x + f.w / 2, y = f.y + f.h / 2 }
end

local function post(kind, point)
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types[kind], point):post()
end

-- One drag. Uses blocking sleeps on purpose: the steps must be evenly timed.
local function drag(from, to, timing, beforeDrop)
  hs.mouse.absolutePosition(from)
  hs.timer.usleep(20000)
  post("leftMouseDown", from)
  hs.timer.usleep(math.floor(timing.hold * 1e6))
  -- The nudge (see QUICK and SLOW).
  local dir = (to.x < from.x) and -1 or 1
  for i = 1, 3 do
    post("leftMouseDragged", { x = from.x + dir * 3 * i, y = from.y })
    hs.timer.usleep(10000)
  end
  local start = { x = from.x + dir * 9, y = from.y }
  local steps = math.max(1, math.ceil(math.abs(to.x - start.x) / timing.step))
  for i = 1, steps do
    local f = i / steps
    post("leftMouseDragged", {
      x = start.x + (to.x - start.x) * f,
      y = start.y + (to.y - start.y) * f,
    })
    hs.timer.usleep(math.floor(STEP_WAIT * 1e6))
  end
  -- beforeDrop may move the pointer and return where to drop instead.
  local at = beforeDrop and beforeDrop() or to
  post("leftMouseUp", at)
end

-- Waits until the thumbnails stop moving (the drop animation is over), so
-- the next drag starts from the right place.
local function waitUntilStill(screen, timeout)
  local last = nil
  spaceUtils.waitFor(function()
    local t = thumbnails(screen)
    if not t then return true end
    local key = {}
    for _, b in ipairs(t) do
      table.insert(key, string.format("%s@%.0f/%.0f", b.name, b.frame.x, b.frame.w))
    end
    key = table.concat(key, ",")
    local still = key == last
    last = key
    return still
  end, timeout, 0.04)
end

local function indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return nil
end

-- True when the Spaces in `wanted` appear in that order with nothing of
-- `wanted` out of place (other Spaces may sit in between).
local function inOrder(order, wanted)
  local set = {}
  for _, sid in ipairs(wanted) do set[sid] = true end
  local filtered = {}
  for _, sid in ipairs(order) do
    if set[sid] then table.insert(filtered, sid) end
  end
  if #filtered ~= #wanted then return false end
  for i = 1, #wanted do
    if filtered[i] ~= wanted[i] then return false end
  end
  return true
end
M.inOrder = inOrder

-- Opens Mission Control and gets the Spaces bar of `screen` ready to drag
-- in: `count` thumbnails, grown to full size and no longer moving.
-- Returns the thumbnails, or nil and a reason.
function M.openBar(screen, count)
  local opened = log.clock()
  spaces.openMissionControl()
  local thumbs = spaceUtils.waitFor(function()
    local t = thumbnails(screen)
    return t and #t == count and t
  end, OPEN_TIMEOUT, 0.03)
  if not thumbs then
    local _, err = thumbnails(screen)
    return nil, "Could not read the Spaces bar: " .. tostring(err or "wrong number of thumbnails")
  end
  -- Hover the bar so the thumbnails grow to full size. Mission Control
  -- grows it when the pointer enters it. Putting the pointer on it directly
  -- does not count (no mouse event crosses the edge of the bar), and when
  -- the bar is small it never grew, so there was nothing to drag. So start
  -- below the bar and move up into it with real mouse events.
  local function height()
    local t = thumbnails(screen)
    return t and t[1] and t[1].frame.h or 0
  end
  local function grown() return height() >= GROWN_HEIGHT end
  local function enterFromBelow(f, below)
    local x = f.x + f.w / 2
    local inside, outside = f.y + f.h / 2, f.y + f.h + below
    hs.mouse.absolutePosition({ x = x, y = outside })
    hs.timer.usleep(16000)
    for i = 1, 8 do
      post("mouseMoved", { x = x, y = outside + (inside - outside) * i / 8 })
      hs.timer.usleep(16000)
    end
  end
  local startHeight = thumbs[1].frame.h
  enterFromBelow(thumbs[1].frame, 60)
  local didGrow = spaceUtils.waitFor(grown, GROW_TIMEOUT, 0.03)
  if not didGrow then
    local t = thumbnails(screen)
    if t and t[1] then enterFromBelow(t[1].frame, 150) end
    didGrow = spaceUtils.waitFor(grown, GROW_TIMEOUT, 0.03)
  end
  -- The growing is animated: positions read halfway through are off by a
  -- bit, enough to drop onto a thumbnail instead of a gap (Split View).
  -- So wait until the thumbnails stop moving.
  waitUntilStill(screen, 1.0)
  local after = thumbnails(screen)
  local info = {
    ms = math.floor(log.since(opened)),
    startHeight = math.floor(startHeight),
    height = after and after[1] and math.floor(after[1].frame.h) or nil,
  }
  if not didGrow then
    -- Dragging a small bar does not pick anything up: letting go then is
    -- a click, which switches Space and closes Mission Control.
    log.debug("Spaces bar stayed small", info)
    return nil, "The Spaces bar stayed small, so its Spaces cannot be dragged"
  end
  log.debug("Mission Control ready", info)
  return after
end

function M.closeBar(screen)
  spaces.closeMissionControl()
  spaceUtils.waitFor(function() return spacesBar(screen) == nil end, CLOSE_TIMEOUT, 0.03)
end

-- For the drag test (lua/dragbench.lua).
M.thumbnails = thumbnails
M.post = post
M.center = center
M.waitUntilStill = waitUntilStill

-- Puts the Spaces of a screen in the order of `wanted` (a list of space ids,
-- desktops and fullscreen Spaces). Spaces that are not in the list are left
-- where they are as much as possible.
-- Returns true when the order is right afterwards.
-- opts.slow: skip the quick attempt (used for a second try).
-- Returns ok, info; info.merged is true when a drop made a Split View.
function M.reorder(screen, wanted, names, opts)
  names = names or {}
  opts = opts or {}
  local merged = false
  local function nameOf(sid) return names[sid] or tostring(sid) end

  local order = spaces.spacesForScreen(screen) or {}
  if inOrder(order, wanted) then return true, {} end

  local done = log.step("Reorder Spaces in Mission Control")
  local mouseBefore = hs.mouse.absolutePosition()
  local moved, failure = 0, nil

  local thumbs, err = M.openBar(screen, #order)
  if not thumbs then failure = err end
  local reopened = false

  local listed = {}
  for _, sid in ipairs(wanted) do listed[sid] = true end

  -- Left to right: wanted[t] must come after wanted[t - 1] with only
  -- unlisted Spaces in between. If not, drag it right after wanted[t - 1].
  -- Everything listed left of that point is already final, so drags go to
  -- the left (unless a drop overshot, then a correcting drag may go right,
  -- or an end of the bar is reached in two drops, see below).
  local function targetFor(t)
    if t == 1 then return 1 end
    local prev = indexOf(order, wanted[t - 1])
    return prev and (prev + 1) or nil
  end
  local function isPlaced(t)
    local src = indexOf(order, wanted[t])
    if not src then return false end
    local first = 1
    if t > 1 then
      local prev = indexOf(order, wanted[t - 1])
      if not prev or src < prev then return false end
      first = prev + 1
    end
    for i = first, src - 1 do
      if listed[order[i]] then return false end
    end
    return true
  end

  for t = 1, #wanted do
    if failure then break end
    local sid = wanted[t]
    if not indexOf(order, sid) or (t > 1 and not indexOf(order, wanted[t - 1])) then
      failure = "Space " .. nameOf(sid) .. " is not on this screen"
      break
    end

    local how, tries = nil, 0
    local timings = opts.slow and { SLOW, SLOW } or { QUICK, SLOW, SLOW }
    -- macOS 27 picked a quick drag up but never opened the gap (Split
    -- View); careful drags worked there.
    if missionControl.inWindowManager and not opts.slow then timings = { SLOW, SLOW, SLOW } end
    local aimInfo = {}
    local started = log.clock()

    while not isPlaced(t) and tries < #timings and not failure do
      tries = tries + 1
      local timing = timings[tries]

      waitUntilStill(screen, 0.5)
      thumbs = thumbnails(screen)
      if not thumbs and not reopened then
        -- A drag that was not picked up ends as a click on the thumbnail,
        -- which closes Mission Control. Open it again, once.
        reopened = true
        log.debug("Mission Control closed during a drag; opening it again")
        thumbs, err = M.openBar(screen, #order)
        if not thumbs then failure = err break end
      end
      if not thumbs or #thumbs ~= #order then
        failure = "The Spaces bar does not match the Spaces list"
        break
      end

      local src = indexOf(order, sid)
      local target = targetFor(t)
      -- Going to either end of the bar means dropping onto or next to the
      -- end thumbnail, which went wrong too often (see QUICK and SLOW). So
      -- go there with two gap drops: first next to the end Space, then
      -- drag that Space past it.
      local dragSid, dragSrc = sid, src
      local n = #order
      if n > 2 and target == 1 then
        if src == 2 then dragSid, dragSrc, target = order[1], 1, 3 else target = 2 end
      elseif n > 2 and target > n then
        if src == n - 1 then dragSid, dragSrc, target = order[n], n, n - 1 else target = n end
      end
      -- Where it ends up: dragging right, everything it passes moves left.
      local final = (dragSrc < target) and (target - 1) or target
      local name = thumbs[dragSrc].name
      local from = center(thumbs[dragSrc].frame)
      local to
      if target == 1 then
        local f = thumbs[1].frame
        to = { x = f.x + f.w * 0.15, y = from.y }
      elseif target > #thumbs then
        local f = thumbs[#thumbs].frame
        to = { x = f.x + f.w * 0.85, y = from.y }
      else
        -- The middle of the gap between the two thumbnails it goes between.
        local a, b = thumbs[target - 1].frame, thumbs[target].frame
        to = { x = (a.x + a.w + b.x) / 2, y = from.y }
      end

      local dropAt = to
      local count = #thumbs
      aimInfo = { dropX = math.floor(dropAt.x), from = dragSrc, to = final, speed = timing.name }
      if dragSid ~= sid then aimInfo.moving = nameOf(dragSid) end
      local leftName, rightName = nil, nil
      if target > 1 and target <= #thumbs then
        aimInfo.gapLeft = math.floor(thumbs[target - 1].frame.x + thumbs[target - 1].frame.w)
        aimInfo.gapRight = math.floor(thumbs[target].frame.x)
        leftName, rightName = thumbs[target - 1].name, thumbs[target].name
      end

      -- Before letting go, wait until Mission Control has opened the gap
      -- (see QUICK and SLOW). The bar can also have moved since it was
      -- measured (seen: 22 pt), so the pointer follows the live gap.
      local function dropWhenOpen()
        if not leftName then
          -- An end of the bar (only with two Spaces): no gap to watch.
          hs.timer.usleep(300000)
          return nil
        end
        local at, minOpen = dropAt, thumbs[1].frame.w / 2
        local waited = log.clock()
        local deadline = hs.timer.secondsSinceEpoch() + GAP_TIMEOUT
        local open = false
        repeat
          local a, b
          for _, th in ipairs(thumbnails(screen) or {}) do
            if th.name == leftName then a = th.frame elseif th.name == rightName then b = th.frame end
          end
          if a and b and b.x - (a.x + a.w) > 0 then
            local gl, gr = a.x + a.w, b.x
            local mid = (gl + gr) / 2
            if math.abs(at.x - mid) > math.max(2, (gr - gl) / 4) then
              local next = { x = mid, y = at.y }
              for i = 1, 4 do
                post("leftMouseDragged", { x = at.x + (next.x - at.x) * i / 4, y = at.y })
                hs.timer.usleep(10000)
              end
              at = next
              aimInfo.liveGap = string.format("%.0f-%.0f", gl, gr)
            elseif gr - gl >= minOpen then
              open = true
            end
          end
          if not open then hs.timer.usleep(20000) end
        until open or hs.timer.secondsSinceEpoch() > deadline
        aimInfo.gapMs = math.floor(log.since(waited))
        if open then
          hs.timer.usleep(30000)
          aimInfo.dropX = math.floor(at.x)
          return at
        end
        aimInfo.gapOpened = false
        -- The gap never opened. When nothing in the bar moved, Mission
        -- Control did not pick the thumbnail up: let go over the thumbnail
        -- itself, where a drop cannot merge it with another app, and try
        -- again. (Not outside the bar: that drops it onto the current
        -- Space, which made a Split View.)
        local still = true
        for i, th in ipairs(thumbnails(screen) or {}) do
          local was = thumbs[i] and thumbs[i].frame
          if not was or th.name ~= thumbs[i].name or math.abs(th.frame.x - was.x) > 2 then still = false end
        end
        -- On macOS 27 also when something moved: there a thumbnail that was
        -- picked up and let go at an unopened gap made a Split View.
        if still or missionControl.inWindowManager then
          if still then aimInfo.pickedUp = false end
          for i = 1, 4 do
            post("leftMouseDragged", { x = at.x + (from.x - at.x) * i / 4, y = from.y })
            hs.timer.usleep(10000)
          end
          aimInfo.dropX = math.floor(from.x)
          return from
        end
        aimInfo.dropX = math.floor(at.x)
        return at
      end

      local function indexOfName()
        for i, th in ipairs(thumbnails(screen) or {}) do
          if th.name == name then return i end
        end
        return nil
      end
      local function mergedNow()
        local now = thumbnails(screen)
        return now and #now < count
      end

      drag(from, dropAt, timing, dropWhenOpen)
      spaceUtils.waitFor(function()
        return indexOfName() == final or mergedNow()
      end, LAND_TIMEOUT, 0.03)
      -- Let the drop animation finish: a drag started during it was not
      -- picked up (the gap never opened) and made a Split View.
      waitUntilStill(screen, 0.5)

      if mergedNow() then
        merged = true
        failure = nameOf(dragSid) .. " was dropped onto another fullscreen app (Split View)"
        local frames = {}
        for _, th in ipairs(thumbnails(screen) or {}) do
          table.insert(frames, string.format("%.0f-%.0f", th.frame.x, th.frame.x + th.frame.w))
        end
        aimInfo.barNow = table.concat(frames, " ")
        log.debug("Split View drop details", aimInfo)
        break
      end

      -- Wherever it went, follow it, so the next try starts from the truth.
      local now = indexOfName()
      if now and now ~= dragSrc then
        table.remove(order, dragSrc)
        table.insert(order, now, dragSid)
        moved = moved + 1
      end
      if now == final then
        how = timing.name
        -- First of two drops done: the second one gets all tries again.
        if not isPlaced(t) then tries = 0 end
      elseif now == dragSrc then
        log.debug("Drag of " .. nameOf(dragSid) .. " was ignored at " .. timing.name .. " speed", aimInfo)
      else
        aimInfo.landedAt = now
        log.debug("Drag of " .. nameOf(dragSid) .. " landed at position " .. tostring(now) ..
          " instead of " .. final .. "; trying again", aimInfo)
      end
    end

    if not failure and not isPlaced(t) then
      failure = "Drag of " .. nameOf(sid) .. " did not land where expected"
    elseif how then
      aimInfo.ms = math.floor(log.since(started))
      aimInfo.tries = tries
      log.debug("Dragged " .. nameOf(sid) .. " to position " .. indexOf(order, sid), aimInfo)
    end
  end

  M.closeBar(screen)
  spaceUtils.sleep(0.1)
  if mouseBefore then hs.mouse.absolutePosition(mouseBefore) end

  local ok = inOrder(spaces.spacesForScreen(screen) or {}, wanted)
  if ok then
    done("Reordered with " .. moved .. " drag(s)")
  elseif failure then
    done(failure, { drags = moved }, "warn")
  else
    done("Order still not right after " .. moved .. " drag(s)", nil, "warn")
  end
  return ok, { merged = merged }
end

return M
