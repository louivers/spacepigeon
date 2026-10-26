-- Builds a screen's Spaces from left to right:
--
--   Desktop 1, [fullscreen apps set to go after desktop 1], Desktop 2, [...], ...
--
-- macOS has no API to move Spaces. What it does on Tahoe 26 (seen in the
-- logs, "Automatically rearrange Spaces" off):
--   * a new desktop goes after the last desktop, so before any fullscreen
--     Spaces at the end
--   * a new fullscreen Space always goes at the very end
-- macOS 27 puts a new desktop at the very end too, after the fullscreen
-- Spaces; the drags below put it back in its place.
--
-- So: get the right number of desktops, make every fullscreen app
-- fullscreen (they land at the end), then drag the fullscreen Spaces to
-- their place in Mission Control (lua/mcdrag.lua).
--
-- With reordering turned off (config.reorderFullscreen = false) the
-- fullscreen apps stay after the last desktop, sorted by their "space"
-- number and then by their place in the preset list.
--
-- Fullscreen Spaces of apps that are not in the preset are left alone.

local spaces = require("hs.spaces")
local spaceUtils = require("lua.space_utils")
local fullscreen = require("lua.fullscreen")
local mcdrag = require("lua.mcdrag")
local log = require("lua.log")

local M = {}

local function names(list)
  local parts = {}
  for _, e in ipairs(list) do table.insert(parts, e.name or tostring(e.id)) end
  return table.concat(parts, " | ")
end

-- Describes the screen as "D | D | Claude | ...", configured apps only.
local function describeScreen(screen, wanted)
  local parts = {}
  for _, sid in ipairs(spaces.spacesForScreen(screen) or {}) do
    local kind = spaces.spaceType(sid)
    if kind == "user" then
      table.insert(parts, "D")
    elseif kind == "fullscreen" then
      for _, wid in ipairs(spaces.windowsForSpace(sid) or {}) do
        if wanted[wid] then table.insert(parts, wanted[wid].name or tostring(wid)) break end
      end
    end
  end
  return table.concat(parts, " | ")
end

-- Configured fullscreen windows, split into the ones after the last desktop
-- (in order) and the ones that have a desktop after them.
local function fullscreenState(screen, wanted)
  local tail, misplaced = {}, {}
  for _, sid in ipairs(spaces.spacesForScreen(screen) or {}) do
    local kind = spaces.spaceType(sid)
    if kind == "user" then
      -- Everything seen so far has a desktop after it.
      for _, e in ipairs(tail) do table.insert(misplaced, e) end
      tail = {}
    elseif kind == "fullscreen" then
      for _, wid in ipairs(spaces.windowsForSpace(sid) or {}) do
        if wanted[wid] then
          table.insert(tail, { id = wid, sid = sid, name = wanted[wid].name })
          break
        end
      end
    end
  end
  return tail, misplaced
end

-- The desktop to make a window fullscreen from: the one it is on (no move
-- needed) when that is a desktop on this screen, else the last desktop.
local function startDesktop(screen, winId)
  local desktops = spaceUtils.userSpacesForScreen(screen)
  local onScreen = {}
  for _, sid in ipairs(desktops) do onScreen[sid] = true end
  for _, sid in ipairs(spaces.windowSpaces(winId) or {}) do
    if onScreen[sid] then return sid end
  end
  return desktops[#desktops]
end

-- Fullscreen Space of a window when it is on this screen.
local function fullscreenSpaceOn(screen, winId)
  local sid = fullscreen.fullscreenSpaceOf(winId)
  if not sid then return nil end
  for _, s in ipairs(spaces.spacesForScreen(screen) or {}) do
    if s == sid then return sid end
  end
  return nil
end

-- Fullscreen apps at the end, sorted (used when reordering is off).
local function arrangeAtEnd(screen, order, wanted)
  local tail, misplaced = fullscreenState(screen, wanted)
  local keep = 0
  while keep < #tail and keep < #order and tail[keep + 1].id == order[keep + 1].id do
    keep = keep + 1
  end

  local toExit = {}
  for _, e in ipairs(misplaced) do table.insert(toExit, e) end
  for i = keep + 1, #tail do table.insert(toExit, tail[i]) end
  local toEnter = {}
  for i = keep + 1, #order do table.insert(toEnter, order[i]) end
  if #toExit == 0 and #toEnter == 0 then return end

  log.info(string.format("Fullscreen apps: keeping %d, taking out %d (%s), putting in %d (%s)",
    keep, #toExit, names(toExit), #toEnter, names(toEnter)))

  for _, e in ipairs(toExit) do
    fullscreen.exitFullscreen(wanted[e.id].app, e.id)
  end
  for _, item in ipairs(toEnter) do
    local from = startDesktop(screen, item.id)
    if from then
      fullscreen.enterFullscreen(item.app, item.id, from, screen)
    else
      log.error("No desktop to start " .. tostring(item.name) .. " from")
    end
  end
end

-- Every fullscreen app fullscreen, then dragged into place.
local function arrangeByDragging(screen, desktopCount, order)
  local missing = {}
  for _, item in ipairs(order) do
    if not fullscreenSpaceOn(screen, item.id) then table.insert(missing, item) end
  end
  if #missing > 0 then
    log.info(string.format("Making %d app(s) fullscreen: %s", #missing, names(missing)))
  end
  for _, item in ipairs(missing) do
    local from = startDesktop(screen, item.id)
    if from then
      fullscreen.enterFullscreen(item.app, item.id, from, screen)
    else
      log.error("No desktop to start " .. tostring(item.name) .. " from")
    end
  end

  -- Wanted order of space ids: desktop 1, its apps, desktop 2, ...
  local function wantedOrder()
    local desktops = spaceUtils.userSpacesForScreen(screen)
    local wantedIds, labels = {}, {}
    for _, item in ipairs(order) do
      local sid = item.after == 0 and fullscreenSpaceOn(screen, item.id)
      if sid then
        table.insert(wantedIds, sid)
        labels[sid] = item.name
      end
    end
    for k = 1, math.min(desktopCount, #desktops) do
      table.insert(wantedIds, desktops[k])
      labels[desktops[k]] = "Desktop " .. k
      for _, item in ipairs(order) do
        if item.after == k then
          local sid = fullscreenSpaceOn(screen, item.id)
          if sid then
            table.insert(wantedIds, sid)
            labels[sid] = item.name
          end
        end
      end
    end
    return wantedIds, labels
  end

  -- Two preset apps sharing one fullscreen Space are in Split View (from a
  -- drop that landed on a thumbnail instead of a gap). Take the second one
  -- out of fullscreen and make it fullscreen again on its own.
  local function splitMerged()
    local owner, found = {}, false
    for _, item in ipairs(order) do
      local sid = fullscreenSpaceOn(screen, item.id)
      if sid and owner[sid] then
        found = true
        log.warn(item.name .. " is in Split View with " .. owner[sid].name .. "; splitting them")
        fullscreen.exitFullscreen(item.app, item.id)
        local from = startDesktop(screen, item.id)
        if from then fullscreen.enterFullscreen(item.app, item.id, from, screen) end
      elseif sid then
        owner[sid] = item
      end
    end
    return found
  end

  splitMerged()
  local ok, info = mcdrag.reorder(screen, wantedOrder())
  if ok or not (info and info.merged) then return end

  -- A drop made a Split View: split it and drag once more, slowly.
  splitMerged()
  local wantedIds, labels = wantedOrder()
  mcdrag.reorder(screen, wantedIds, labels, { slow = true })
end

-- items: list of { app = hs.application, id = window id, after = desktop
-- number it comes after (0 = before desktop 1), name = app name }, in
-- preset order.
-- opts.reorder: drag fullscreen Spaces into place (default true).
-- Returns true when the screen ends up as wanted.
function M.build(screen, desktopCount, items, opts)
  local reorder = not (opts and opts.reorder == false)
  local done = log.step("Arrange Spaces on " .. (screen:name() or "screen"))

  -- Sorted by desktop, then preset order. With reordering this is also the
  -- order inside each desktop's group.
  local order = {}
  for i, item in ipairs(items) do
    -- 0 means before desktop 1.
    item.after = math.max(0, math.min(item.after or desktopCount, desktopCount))
    item.index = i
    table.insert(order, item)
  end
  table.sort(order, function(a, b)
    if a.after ~= b.after then return a.after < b.after end
    return a.index < b.index
  end)

  local wanted = {}
  for _, item in ipairs(order) do wanted[item.id] = item end

  local desired = {}
  if reorder then
    for _, item in ipairs(order) do
      if item.after == 0 then table.insert(desired, item.name or tostring(item.id)) end
    end
    for k = 1, desktopCount do
      table.insert(desired, "D")
      for _, item in ipairs(order) do
        if item.after == k then table.insert(desired, item.name or tostring(item.id)) end
      end
    end
  else
    for _ = 1, desktopCount do table.insert(desired, "D") end
    for _, item in ipairs(order) do table.insert(desired, item.name or tostring(item.id)) end
  end
  local desiredText = table.concat(desired, " | ")

  local now = describeScreen(screen, wanted)
  log.info("Spaces now: " .. now .. "; wanted: " .. desiredText)
  if now == desiredText then
    done("Spaces already in place")
    return true
  end

  -- 1. Number of desktops.
  local desktops = spaceUtils.userSpacesForScreen(screen)
  if #desktops < desktopCount then
    for _ = #desktops + 1, desktopCount do
      if not spaceUtils.addDesktop(screen) then break end
    end
  elseif #desktops > desktopCount then
    -- Mission Control cannot remove the desktop that is showing.
    spaceUtils.gotoSpaceAndWait(desktops[1])
    local extra = {}
    for i = desktopCount + 1, #desktops do table.insert(extra, desktops[i]) end
    spaceUtils.removeDesktops(extra)
  end

  -- 2. Fullscreen apps.
  if reorder then
    arrangeByDragging(screen, desktopCount, order)
  else
    arrangeAtEnd(screen, order, wanted)
  end

  -- 3. Verify.
  local got = describeScreen(screen, wanted)
  if got == desiredText then
    done("Spaces arranged: " .. got)
    return true
  end
  done("Spaces not fully arranged", { got = got, wanted = desiredText }, "warn")
  return false
end

return M
