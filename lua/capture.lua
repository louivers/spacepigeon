-- Saves the current layout as a preset: reads the windows that are open
-- right now and writes them to ~/.hammerspoon/spacepigeon_capture.json,
-- which the SpacePigeon app turns into a new preset.
--
-- Per window: its app (by file name, like the app picker), its monitor, its
-- place in Mission Control (desktops and fullscreen apps counted together,
-- like `space` in a preset) and its position: the named part of the screen
-- it is close to, else "custom" with its frame.

local spaceUtils = require("lua.space_utils")
local layout = require("lua.layout")
local helper = require("lua.helper")
local log = require("lua.log")

local M = {}

M.path = hs.configdir .. "/spacepigeon_capture.json"

-- Never part of a layout. The config editor is open while you capture from it.
local skipNames = { Hammerspoon = true, SpacePigeon = true }
local skipBundles = { ["org.hammerspoon.Hammerspoon"] = true, ["com.louivers.spacepigeon"] = true }

local function appName(a)
  local file = a:path() and a:path():match("([^/]+)%.app/?$")
  return file or a:name()
end

-- Every normal window: { id, pid, spaces, frame }. The helper sees windows
-- on every Space; without it only the ones Accessibility sees, on the
-- Spaces that are showing.
local function windows()
  local list = {}
  local fromHelper = helper.allWindows()
  if fromHelper then
    for _, w in ipairs(fromHelper) do
      local frame
      if w.x and w.y and w.w and w.h then
        frame = { x = w.x, y = w.y, w = w.w, h = w.h }
      else
        -- A helper older than 1.2 gives no position.
        local win = hs.window.get(w.id)
        frame = win and win:frame()
      end
      table.insert(list, { id = w.id, pid = w.pid, spaces = w.spaces or {}, frame = frame })
    end
    return list, "helper"
  end

  for _, w in ipairs(hs.window.allWindows()) do
    local a = w:application()
    if a and w:isStandard() and not w:isMinimized() then
      table.insert(list, { id = w:id(), pid = a:pid(), spaces = hs.spaces.windowSpaces(w:id()) or {}, frame = w:frame() })
    end
  end
  return list, "accessibility"
end

-- The current layout as { monitors = { { spaces = n }, ... }, apps = { ... },
-- warnings = { ... } }. Apps are sorted by monitor, space, then left to
-- right; each has name, monitor, space, pos, frame (custom only) and id
-- (the window).
function M.read()
  local screens = spaceUtils.getOrderedScreens()
  local monitors, place = {}, {}
  for i, screen in ipairs(screens) do
    local all = hs.spaces.spacesForScreen(screen) or {}
    monitors[i] = { spaces = #all }
    for p, sid in ipairs(all) do
      place[sid] = { monitor = i, space = p, screen = screen, fullscreen = hs.spaces.spaceType(sid) == "fullscreen" }
    end
  end

  local list, via = windows()
  local apps, warnings, byPid, order = {}, {}, {}, {}
  for _, w in ipairs(list) do
    if byPid[w.pid] == nil then
      byPid[w.pid] = hs.application.applicationForPID(w.pid) or false
    end
    local a = byPid[w.pid]
    local at = place[w.spaces[1]]
    if a and at and a:kind() == 1 and not skipNames[a:name() or ""] and not skipBundles[a:bundleID() or ""] then
      local entry = { name = appName(a), monitor = at.monitor, space = at.space, id = w.id }
      if at.fullscreen then
        entry.pos = "fullscreen"
      elseif w.frame then
        entry.pos, entry.frame = layout.snap(w.frame, at.screen:frame())
        if entry.pos ~= "custom" then entry.frame = nil end
      else
        entry.pos = "max"
        table.insert(warnings, "Could not read where " .. entry.name .. " is; it is set to Max")
      end
      order[entry] = { x = w.frame and w.frame.x or 0, y = w.frame and w.frame.y or 0 }
      table.insert(apps, entry)
    end
  end

  table.sort(apps, function(p, q)
    if p.monitor ~= q.monitor then return p.monitor < q.monitor end
    if p.space ~= q.space then return p.space < q.space end
    if order[p].x ~= order[q].x then return order[p].x < order[q].x end
    if order[p].y ~= order[q].y then return order[p].y < order[q].y end
    return p.id < q.id
  end)

  if via ~= "helper" then
    table.insert(warnings, "Without the spacectl helper only the windows on the desktops that are showing can be read")
  end
  return { monitors = monitors, apps = apps, warnings = warnings, via = via }
end

-- Reads the layout and writes it for the app. Returns true when written.
function M.toFile()
  local done = log.step("Save current layout")
  local ok, result = pcall(M.read)
  if not ok then
    done("Could not read the windows", { error = tostring(result) }, "error")
    return false
  end

  -- An app with several windows: each entry keeps the window it was read
  -- from, so setting the preset up does not swap them around.
  local ids, names = {}, {}
  for _, e in ipairs(result.apps) do
    local key = e.name:lower()
    if not ids[key] then
      ids[key] = {}
      table.insert(names, e.name)
    end
    table.insert(ids[key], e.id)
    e.id = nil
  end
  for _, name in ipairs(names) do
    if #ids[name:lower()] > 1 then layout.rememberWindows(name, ids[name:lower()]) end
  end

  local data = { monitors = result.monitors, apps = result.apps }
  if #result.warnings > 0 then data.warnings = result.warnings end
  local json = hs.json.encode(data)
  local tmp = M.path .. ".tmp"
  local f = json and io.open(tmp, "w")
  if not f then
    done("Could not write " .. M.path, nil, "error")
    return false
  end
  f:write(json)
  f:close()
  os.rename(tmp, M.path)

  for _, w in ipairs(result.warnings) do log.warn(w) end
  done(string.format("Read %d window(s) on %d monitor(s)", #result.apps, #result.monitors), { via = result.via })
  return true
end

-- From the menu bar: writes the layout and opens the app on it.
function M.toApp()
  if not M.toFile() then
    hs.alert.show("Could not read your windows - check the log")
    return
  end
  local args = { "-a", "SpacePigeon", "--args", "--capture" }
  local profileOk, profile = pcall(require, "lua.profile")
  if profileOk and profile.name then
    table.insert(args, "--profile")
    table.insert(args, profile.name)
  end
  hs.task.new("/usr/bin/open", nil, args):start()
end

return M
