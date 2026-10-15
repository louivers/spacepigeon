-- Drag test: tries many ways of dragging a fullscreen Space in Mission
-- Control and finds the fastest one that never makes a Split View.
--
-- Uses the fullscreen apps that are already open (run a workspace first).
-- Each approach is a mix of: the wait after the previous drop, how long the
-- mouse is held before moving, a small pickup nudge or not, how fast the
-- pointer moves, and when it lets go.
-- Each one is tried on a few moves (between two fullscreen apps going left
-- or right, all the way left, all the way right). An approach is out at its
-- first Split View (which the test then repairs); the others get more rounds.
--
-- Start:  open "hammerspoon://dragbench"   (scripts/drag_bench.sh)
-- Stop:   cmd+alt+ctrl+X (results so far are still written)
-- Output: ~/.hammerspoon/dragbench/<time>.csv (every drag) and .md (ranking)

local spaces = require("hs.spaces")
local spaceUtils = require("lua.space_utils")
local mcdrag = require("lua.mcdrag")
local log = require("lua.log")

local M = {}

local LAND_TIMEOUT = 1.2  -- wait for a drop to show up in the bar
local GAP_TIMEOUT = 0.6   -- "drop once the gap is open": give up waiting after this

local SETTLES = { 0, 0.15, 0.3 }
local HOLDS = { 0, 0.05, 0.1, 0.15 }
-- Pickup: "nudge" first moves the pointer 3 x 3 pt (10 ms apart) before
-- the real move, so the drag starts while still over the thumbnail.
local PICKUPS = { { name = "", nudge = false }, { name = "nudge", nudge = true } }
-- Move: how far the pointer goes per mouse event (8 ms apart). A long drag
-- in big jumps (200+ pt per event) never opened the gap.
local STEP_WAIT = 0.008
local MOVES = {
  { name = "jump", step = math.huge },
  { name = "150pt", step = 150 },
  { name = "80pt", step = 80 },
  { name = "40pt", step = 40 },
}
-- hover: wait, then move to the middle of the gap as it is now and let go.
-- whenOpen: let go as soon as the gap has opened, following it. (Aiming
-- at the gap measured before the drag is off: the bar moves ~22 pt while
-- a thumbnail is held.)
local DROPS = {
  { name = "hover0+live", hover = 0, live = true },
  { name = "hover100+live", hover = 0.1, live = true },
  { name = "hover200+live", hover = 0.2, live = true },
  { name = "whenOpen", open = true },
}
local KINDS = { "between-left", "between-right", "far-left", "far-right" }

local function variant(settle, hold, pickup, move, drop)
  return {
    id = string.format("settle%.0f hold%.0f %s%s %s", settle * 1000, hold * 1000,
      pickup.nudge and "nudge+" or "", move.name, drop.name),
    settle = settle, hold = hold, pickup = pickup, move = move, drop = drop,
    trials = 0, ok = 0, off = 0, ignored = 0, split = 0, ms = 0, worst = 0,
  }
end

local function variants(smoke)
  if smoke then
    return {
      variant(0.15, 0.15, PICKUPS[2], MOVES[4], DROPS[4]),
      variant(0.15, 0.05, PICKUPS[1], MOVES[3], DROPS[4]),
      variant(0.15, 0.15, PICKUPS[1], MOVES[2], DROPS[2]),
      variant(0.15, 0.05, PICKUPS[2], MOVES[2], DROPS[4]),
    }
  end
  local out = {}
  for _, settle in ipairs(SETTLES) do
    for _, hold in ipairs(HOLDS) do
      for _, pickup in ipairs(PICKUPS) do
        for _, move in ipairs(MOVES) do
          for _, drop in ipairs(DROPS) do
            table.insert(out, variant(settle, hold, pickup, move, drop))
          end
        end
      end
    end
  end
  return out
end

local function shuffle(list)
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
end

local function isFullscreen(sid)
  return spaces.spaceType(sid) == "fullscreen"
end

-- Picks a drag for one kind of move, at random among the possible ones.
-- Returns { src, target, final } (target as in mcdrag: insert before it),
-- or nil when the screen has no such move.
local function pick(kind, order)
  local n, options = #order, {}
  local function fs(i) return order[i] and isFullscreen(order[i]) end
  for src = 1, n do
    if fs(src) then
      if kind == "far-left" and src >= 3 and fs(1) then
        table.insert(options, { src = src, target = 1, final = 1 })
      elseif kind == "far-right" and src <= n - 2 and fs(n) then
        table.insert(options, { src = src, target = n + 1, final = n })
      elseif kind == "between-left" or kind == "between-right" then
        for target = 2, n do
          local ok = fs(target - 1) and fs(target)
          if kind == "between-left" then ok = ok and target <= src - 2 else ok = ok and target >= src + 3 end
          if ok then
            table.insert(options, { src = src, target = target, final = (src < target) and target - 1 or target })
          end
        end
      end
    end
  end
  if #options == 0 then return nil end
  return options[math.random(#options)]
end

-- The gap the drag aims for, from frames: left and right edge. At an end
-- of the bar the outer edge is half a normal gap past the end thumbnail.
local function gapOf(kind, plan, frames, leftName, rightName, gapW)
  local a, b
  for _, th in ipairs(frames) do
    if th.name == leftName then a = th.frame elseif th.name == rightName then b = th.frame end
  end
  if plan.target == 1 then
    if not b then return nil end
    return b.x - gapW, b.x
  elseif not rightName then
    if not a then return nil end
    return a.x + a.w, a.x + a.w + gapW
  end
  if not (a and b) then return nil end
  return a.x + a.w, b.x
end

-- One drag with one approach. Returns a result table.
local function trial(screen, v, kind, plan, order)
  spaceUtils.sleep(v.settle)
  local thumbs = mcdrag.thumbnails(screen)
  if not thumbs or #thumbs ~= #order then return { outcome = "bar changed" } end

  local count = #thumbs
  local name = thumbs[plan.src].name
  local gapW = thumbs[2].frame.x - (thumbs[1].frame.x + thumbs[1].frame.w)
  local thumbW = thumbs[1].frame.w
  local leftName = plan.target > 1 and thumbs[plan.target - 1].name or nil
  local rightName = plan.target <= count and thumbs[plan.target].name or nil
  local gl, gr = gapOf(kind, plan, thumbs, leftName, rightName, gapW)
  local from = mcdrag.center(thumbs[plan.src].frame)
  local at = { x = (gl + gr) / 2, y = from.y }

  local post = mcdrag.post
  local function glide(to, steps, wait)
    for i = 1, steps do
      post("leftMouseDragged", { x = at.x + (to.x - at.x) * i / steps, y = at.y + (to.y - at.y) * i / steps })
      if wait > 0 then hs.timer.usleep(math.floor(wait * 1e6)) end
    end
    at = to
  end

  -- What happened during the drag, for the CSV: "ms:left-right@pointer"
  -- samples of the live gap, and the bar when the mouse was let go.
  local trace = {}
  local started = hs.timer.secondsSinceEpoch()
  local function sample(tag, lg, rg)
    table.insert(trace, string.format("%s%.0f:%s@%.0f", tag or "",
      math.floor((hs.timer.secondsSinceEpoch() - started) * 1000),
      lg and string.format("%.0f-%.0f", lg, rg) or "?", at.x))
  end
  local function liveGap()
    local lg, rg = gapOf(kind, plan, mcdrag.thumbnails(screen) or {}, leftName, rightName, gapW)
    return lg, rg
  end
  hs.mouse.absolutePosition(from)
  hs.timer.usleep(10000)
  post("leftMouseDown", from)
  if v.hold > 0 then hs.timer.usleep(math.floor(v.hold * 1e6)) end
  local target = at
  at = from
  if v.pickup.nudge then
    local dir = (target.x < from.x) and -1 or 1
    glide({ x = from.x + dir * 9, y = from.y }, 3, 0.01)
  end
  glide(target, math.max(1, math.ceil(math.abs(target.x - at.x) / v.move.step)), STEP_WAIT)

  local opened = nil
  if v.drop.open then
    opened = false
    local deadline = hs.timer.secondsSinceEpoch() + GAP_TIMEOUT
    repeat
      local lg, rg = liveGap()
      sample(nil, lg, rg)
      if lg then
        local width = rg - lg
        local mid = (lg + rg) / 2
        local slack = math.max(2, width / 4)
        -- At an end of the bar the gap only has one real edge: open means
        -- that thumbnail moved away from the pointer.
        if plan.target == 1 then width, mid, slack = rg - at.x, rg - gapW / 2, 2
          if width >= thumbW / 2 then slack = math.huge end
        elseif not rightName then width, mid, slack = at.x - lg, lg + gapW / 2, 2
          if width >= thumbW / 2 then slack = math.huge end
        end
        -- First get the pointer well inside the gap, then wait for it to open.
        if math.abs(at.x - mid) > slack then
          glide({ x = mid, y = at.y }, 4, 0.008)
        elseif width >= thumbW / 2 then
          opened = true
        end
      end
      if not opened then hs.timer.usleep(20000) end
    until opened or hs.timer.secondsSinceEpoch() > deadline
    if opened then hs.timer.usleep(30000) end
  else
    if v.drop.hover > 0 then hs.timer.usleep(math.floor(v.drop.hover * 1e6)) end
    if v.drop.live then
      local lg, rg = liveGap()
      sample(nil, lg, rg)
      if lg then glide({ x = (lg + rg) / 2, y = at.y }, 3, 0.008) end
    end
  end
  local barAtDrop = {}
  for _, th in ipairs(mcdrag.thumbnails(screen) or {}) do
    table.insert(barAtDrop, string.format("%.0f-%.0f", th.frame.x, th.frame.x + th.frame.w))
  end
  sample("drop", liveGap())
  post("leftMouseUp", at)
  local dropped = hs.timer.secondsSinceEpoch()

  -- Wait for the result: the thumbnail where it should be, or one fewer
  -- thumbnail (two Spaces merged into a Split View).
  local outcome, landedAt = nil, nil
  local deadline = dropped + LAND_TIMEOUT
  repeat
    local now = mcdrag.thumbnails(screen)
    if now and #now < count then outcome = "split" break end
    for i, th in ipairs(now or {}) do
      if th.name == name then landedAt = i end
    end
    if landedAt == plan.final then outcome = "ok" break end
    hs.timer.usleep(20000)
  until hs.timer.secondsSinceEpoch() > deadline
  if not outcome then
    outcome = (landedAt == plan.src) and "ignored" or "off"
  end
  local finished = hs.timer.secondsSinceEpoch()
  return {
    outcome = outcome,
    landedAt = landedAt,
    dragMs = math.floor((dropped - started) * 1000),
    landMs = math.floor((finished - dropped) * 1000),
    totalMs = math.floor((v.settle + finished - started) * 1000),
    gapOpened = opened,
    planGap = string.format("%.0f-%.0f", gl, gr),
    trace = table.concat(trace, " "),
    barAtDrop = table.concat(barAtDrop, " "),
    name = name,
    splitSid = order[plan.src],
  }
end

-- Fullscreen Spaces on the screen: space id -> list of the apps in it,
-- each { app, pid, id = its biggest fullscreen window }. Apps can have
-- small extra windows in the same Space (Brave has a 151 pt tall one),
-- which cannot be taken out of fullscreen. Two apps in one Space is a
-- Split View.
local function fullscreenApps(screen)
  local helper = require("lua.helper")
  local onScreen = {}
  for _, sid in ipairs(spaces.spacesForScreen(screen) or {}) do onScreen[sid] = true end
  local out = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 then
      local best = {}
      for _, w in ipairs(helper.windowsForApp(app) or {}) do
        if w.fullscreen then
          local area = (w.w or 0) * (w.h or 0)
          for _, sid in ipairs(w.spaces or {}) do
            if onScreen[sid] and (not best[sid] or area > best[sid].area) then
              best[sid] = { app = app, pid = app:pid(), id = w.id, area = area }
            end
          end
        end
      end
      for sid, entry in pairs(best) do
        out[sid] = out[sid] or {}
        table.insert(out[sid], entry)
      end
    end
  end
  return out
end

-- Space id -> the app in it (the first one, for a Split View).
local function fullscreenWindows(screen)
  local out = {}
  for sid, apps in pairs(fullscreenApps(screen)) do out[sid] = apps[1] end
  return out
end

-- Splits every Split View on the screen: one of the two apps (the dragged
-- one when known) leaves fullscreen and goes fullscreen again on its own
-- (its Space lands at the end). Returns true when no Split View is left.
local function repairSplit(screen, dragged)
  local fullscreen = require("lua.fullscreen")
  if mcdrag.thumbnails(screen) then mcdrag.closeBar(screen) end
  for _, apps in pairs(fullscreenApps(screen)) do
    if #apps > 1 then
      local out = apps[2]
      for _, a in ipairs(apps) do
        if dragged and a.pid == dragged.pid then out = a end
      end
      log.info("Splitting " .. out.app:name() .. " out of a Split View")
      fullscreen.exitFullscreen(out.app, out.id)
      local desktops = spaceUtils.userSpacesForScreen(screen)
      fullscreen.enterFullscreen(out.app, out.id, desktops[1], screen)
    end
  end
  for _, apps in pairs(fullscreenApps(screen)) do
    if #apps > 1 then return false end
  end
  return true
end

local function csvRow(fields, n)
  local out = {}
  for i = 1, n or #fields do
    local f = fields[i]
    f = tostring(f == nil and "" or f)
    if f:find("[,\"]") then f = "\"" .. f:gsub("\"", "\"\"") .. "\"" end
    table.insert(out, f)
  end
  return table.concat(out, ",") .. "\n"
end

local function summary(list, info)
  local done = {}
  for _, v in ipairs(list) do
    if v.trials > 0 then table.insert(done, v) end
  end
  local function clean(v) return v.split == 0 and v.off == 0 and v.ignored == 0 end
  local function avg(v) return v.ok > 0 and v.ms / v.ok or math.huge end
  table.sort(done, function(a, b)
    if clean(a) ~= clean(b) then return clean(a) end
    if a.split ~= b.split then return a.split < b.split end
    if a.trials ~= b.trials then return a.trials > b.trials end
    return avg(a) < avg(b)
  end)
  local lines = {
    "# Drag test " .. info.started,
    "",
    string.format("%d approaches, %d drags, %d Split Views, %.0f s. Moves tried: %s.%s",
      info.variants, info.drags, info.splits, info.seconds, table.concat(info.kinds, ", "),
      info.stopped and " Stopped early." or ""),
    "",
    "Ranked: approaches with no Split View, no off or ignored drop first, then by average time per drag",
    "(wait after the previous drop + drag + until the drop shows in the bar).",
    "",
    "| # | approach | drags | ok | off | ignored | split | avg ms | worst ms |",
    "|---|---|---|---|---|---|---|---|---|",
  }
  for i, v in ipairs(done) do
    table.insert(lines, string.format("| %d | %s | %d | %d | %d | %d | %d | %s | %d |",
      i, v.id, v.trials, v.ok, v.off, v.ignored, v.split,
      v.ok > 0 and string.format("%.0f", avg(v)) or "-", v.worst))
  end
  return table.concat(lines, "\n") .. "\n"
end

local running, stopRequested = false, false

local function bench(params)
  local screen = hs.screen.primaryScreen()
  local smoke = params.smoke == "1"
  local kinds = KINDS
  if params.kinds and params.kinds ~= "" then
    kinds = {}
    for k in params.kinds:gmatch("[^,]+") do table.insert(kinds, k) end
  end
  local rounds = tonumber(params.rounds) or (smoke and 1 or 3)
  local list = variants(smoke)
  local started = os.date("%Y-%m-%d %H:%M:%S")
  local dir = hs.configdir .. "/dragbench"
  hs.fs.mkdir(dir)
  local base = dir .. "/" .. os.date("%Y%m%d-%H%M%S")
  local csv = io.open(base .. ".csv", "w")
  csv:write(csvRow({ "round", "approach", "settle_ms", "hold_ms", "pickup", "move", "drop", "kind", "from", "to",
    "outcome", "landed_at", "drag_ms", "land_ms", "total_ms", "gap_opened", "thumbnails",
    "planned_gap", "trace", "bar_at_drop" }))
  csv:flush()

  -- Split any Split View left over from before (a stopped test).
  M.hooks.repairSplit(screen, nil)
  local order = spaces.spacesForScreen(screen) or {}
  local fsCount = 0
  for _, sid in ipairs(order) do if isFullscreen(sid) then fsCount = fsCount + 1 end end
  if fsCount < 4 then
    local why = "Drag test needs at least 4 fullscreen apps on the main screen, found " .. fsCount ..
      " (run a workspace first)"
    log.warn(why)
    local md = io.open(base .. ".md", "w")
    md:write("# Drag test " .. started .. "\n\nNot run: " .. why .. ".\n")
    md:close()
    hs.alert.show(why, 5)
    csv:close()
    return
  end

  log.startRun("Drag test", { approaches = #list, rounds = rounds, fullscreen = fsCount })
  hs.alert.show("Drag test: " .. #list .. " approaches. Don't touch the mouse. Stop: cmd+alt+ctrl+X", 4)
  spaceUtils.sleep(2)

  local mouseBefore = hs.mouse.absolutePosition()
  local windows = M.hooks.fullscreenWindows(screen)
  local info = { started = started, variants = #list, drags = 0, splits = 0, kinds = {} }
  local possible = {}
  local t0 = hs.timer.secondsSinceEpoch()
  local barOpen = false

  local function openBar()
    order = spaces.spacesForScreen(screen) or {}
    local thumbs, err = mcdrag.openBar(screen, #order)
    if not thumbs then
      log.warn("Drag test: " .. tostring(err))
      mcdrag.closeBar(screen)
      return false
    end
    barOpen = true
    return true
  end

  local alive = {}
  for _, v in ipairs(list) do table.insert(alive, v) end
  for round = 1, rounds do
    shuffle(alive)
    log.info("Drag test round " .. round, { approaches = #alive })
    for _, v in ipairs(alive) do
      for _, kind in ipairs(kinds) do
        if stopRequested or v.split > 0 then break end
        if not barOpen and not openBar() then stopRequested = true break end
        order = spaces.spacesForScreen(screen) or {}
        local plan = pick(kind, order)
        if plan then
          possible[kind] = true
          local r = trial(screen, v, kind, plan, order)
          if r.outcome == "bar changed" then
            -- Mission Control closed or the bar changed under us: start over.
            mcdrag.closeBar(screen)
            barOpen = false
          else
            info.drags = info.drags + 1
            v.trials = v.trials + 1
            v[r.outcome] = v[r.outcome] + 1
            if r.outcome == "ok" then v.ms = v.ms + r.totalMs end
            v.worst = math.max(v.worst, r.totalMs)
            csv:write(csvRow({ round, v.id, v.settle * 1000, v.hold * 1000, v.pickup.nudge and "nudge" or "",
              v.move.name, v.drop.name, kind,
              plan.src, plan.final, r.outcome, r.landedAt, r.dragMs, r.landMs, r.totalMs,
              r.gapOpened, #order, r.planGap, r.trace, r.barAtDrop }, 20))
            csv:flush()
            log.debug("Drag test: " .. v.id .. ", " .. kind .. ": " .. r.outcome, {
              ms = r.totalMs, from = plan.src, to = plan.final, landedAt = r.landedAt })
            if r.outcome == "split" then
              info.splits = info.splits + 1
              log.info("Drag test: " .. v.id .. " made a Split View; repairing")
              barOpen = false
              if not M.hooks.repairSplit(screen, windows[r.splitSid]) then
                log.error("Drag test: could not repair the Split View; stopping")
                stopRequested = true
              end
              windows = M.hooks.fullscreenWindows(screen)
            end
          end
        end
      end
      if stopRequested then break end
    end
    if stopRequested then break end
    -- Next round: only approaches without a Split View.
    local keep = {}
    for _, v in ipairs(alive) do if v.split == 0 then table.insert(keep, v) end end
    alive = keep
  end

  if barOpen then mcdrag.closeBar(screen) end
  if mouseBefore then hs.mouse.absolutePosition(mouseBefore) end
  csv:close()

  for _, kind in ipairs(kinds) do
    table.insert(info.kinds, kind .. (possible[kind] and "" or " (not possible here)"))
  end
  info.seconds = hs.timer.secondsSinceEpoch() - t0
  info.stopped = stopRequested
  local md = io.open(base .. ".md", "w")
  md:write(summary(list, info))
  md:close()
  log.endRun("Drag test finished: " .. info.drags .. " drags, " .. info.splits .. " Split Views", { results = base .. ".md" })
  hs.alert.show("Drag test done: results in " .. base .. ".md", 5)
end

-- params: smoke=1 (4 approaches, 1 round), rounds=N (default 3),
-- kinds=between-right,far-left (only these moves).
function M.run(params)
  if running then
    hs.alert.show("Drag test is already running")
    return
  end
  running, stopRequested = true, false
  local stopKey = hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "x", function()
    stopRequested = true
    hs.alert.show("Stopping the drag test after this drag...")
  end)
  coroutine.wrap(function()
    local ok, err = xpcall(bench, debug.traceback, params or {})
    running = false
    stopKey:delete()
    if not ok then
      log.error("Drag test crashed", { error = tostring(err) })
      log.endRun("Drag test crashed")
      -- Close Mission Control before letting go of the mouse: a release
      -- in the bar could still drop the thumbnail onto another app.
      pcall(spaces.closeMissionControl)
      hs.timer.usleep(300000)
      pcall(mcdrag.post, "leftMouseUp", hs.mouse.absolutePosition())
      hs.alert.show("Drag test crashed - check the log window")
    end
  end)()
end

-- Replaced by tests/dragbench_sim.lua.
M.hooks = { fullscreenWindows = fullscreenWindows, repairSplit = repairSplit }

return M
