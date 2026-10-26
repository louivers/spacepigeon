-- Enter and leave native fullscreen for one window, with logging.
-- structure.lua decides which windows go fullscreen and in which order.

local spaces = require("hs.spaces")
local helper = require("lua.helper")
local spaceUtils = require("lua.space_utils")
local log = require("lua.log")

local M = {}

local SETTLE = 0.35   -- pause after each transition so the next one is clean

local function fullscreenSpaceOf(winId)
  for _, sid in ipairs(spaces.windowSpaces(winId) or {}) do
    if spaces.spaceType(sid) == "fullscreen" then
      return sid
    end
  end
  return nil
end
M.fullscreenSpaceOf = fullscreenSpaceOf

-- hs.window for a window id. Accessibility only sees windows on Spaces it can
-- reach, so this may need the window's Space to be active first.
function M.findWindow(application, winId)
  if application then
    for _, w in ipairs(application:allWindows()) do
      if w:id() == winId then return w end
    end
  end
  return hs.window.get(winId)
end

local function waitForWindow(application, winId, timeout)
  return spaceUtils.waitFor(function()
    return M.findWindow(application, winId)
  end, timeout or 2, 0.1)
end

local function label(application, winId)
  local name = application and application:name() or "window"
  return name .. " (" .. tostring(winId) .. ")"
end

local function activate(application, win)
  if application and application.activate then application:activate(true) end
  spaceUtils.sleep(0.25)
  win:focus()
  if win.raise then win:raise() end
  spaceUtils.sleep(0.1)
end

-- Path to an app's "Enter Full Screen" / "Toggle Full Screen" menu item.
local MENU_TITLES = {
  ["Enter Full Screen"] = true,
  ["Toggle Full Screen"] = true,
  ["Full Screen"] = true,
}

local function fullscreenMenuPath(application)
  if not application or not application.getMenuItems then return nil end
  local ok, tree = pcall(function() return application:getMenuItems() end)
  if not ok or type(tree) ~= "table" then return nil end

  local found
  local function walk(items, path)
    for _, item in ipairs(items or {}) do
      if found then return end
      local title = item.AXTitle or ""
      local here = { table.unpack(path) }
      table.insert(here, title)
      if MENU_TITLES[title] and item.AXEnabled ~= false then
        found = here
        return
      end
      local children = item.AXChildren
      if type(children) == "table" then
        -- Menus come wrapped once: AXChildren = { { item, item, ... } }.
        if children[1] and children[1].AXTitle == nil and type(children[1][1]) == "table" then
          children = children[1]
        end
        walk(children, here)
      end
    end
  end
  walk(tree, {})
  return found
end

-- Ways to make a window fullscreen, tried in order until one works.
-- The first one is the normal one; the rest are for apps that ignore it
-- (seen right after a window was moved to another Space).
local ATTEMPTS = {
  {
    how = "accessibility", wait = 2.0, toggles = false,
    run = function(_, win)
      win:focus()
      win:setFullScreen(true)
      return true
    end,
  },
  {
    how = "activate app, then accessibility", wait = 2.5, toggles = false,
    run = function(application, win)
      activate(application, win)
      win:setFullScreen(true)
      return true
    end,
  },
  {
    how = "menu item", wait = 3.0, toggles = true,
    run = function(application, win)
      local path = fullscreenMenuPath(application)
      if not path then return false, "no Full Screen menu item" end
      activate(application, win)
      local ok = application:selectMenuItem(path)
      return ok and true or false, table.concat(path, " > ")
    end,
  },
  {
    how = "keys ctrl+cmd+F", wait = 3.0, toggles = true,
    run = function(application, win)
      activate(application, win)
      hs.eventtap.keyStroke({ "ctrl", "cmd" }, "f", 0)
      return true
    end,
  },
}

-- Tries the attempts above. Returns the fullscreen Space id and how it got
-- there, or nil.
local function goFullscreen(application, winId, win)
  for i, attempt in ipairs(ATTEMPTS) do
    local sid = fullscreenSpaceOf(winId)
    if sid then return sid, ATTEMPTS[math.max(1, i - 1)].how end

    -- A window that says it is fullscreen but has no Space yet is still
    -- animating. Toggling it now would undo it, so just wait longer.
    if attempt.toggles and win.isFullScreen and win:isFullScreen() then
      sid = spaceUtils.waitFor(function() return fullscreenSpaceOf(winId) end, 3, 0.1)
      if sid then return sid, "late" end
    end

    local started = log.clock()
    local ran, detail = attempt.run(application, win)
    if ran then
      sid = spaceUtils.waitFor(function() return fullscreenSpaceOf(winId) end, attempt.wait, 0.1)
      if sid then return sid, attempt.how end
      log.warn("Fullscreen via " .. attempt.how .. " did not work for " .. label(application, winId), {
        ms = math.floor(log.since(started)), detail = detail,
      })
    else
      log.debug("Skipped fullscreen via " .. attempt.how, { detail = detail })
    end
  end
  local late = fullscreenSpaceOf(winId)
  if late then return late, "late" end
  return nil
end

-- Takes a window out of native fullscreen. Returns true when it left.
function M.exitFullscreen(application, winId)
  local sid = fullscreenSpaceOf(winId)
  if not sid then return true end

  local done = log.step("Exit fullscreen")
  spaceUtils.gotoSpaceAndWait(sid)
  local win = waitForWindow(application, winId)
  if not win then
    done("Cannot reach " .. label(application, winId) .. " to leave fullscreen", nil, "error")
    return false
  end

  local function left()
    return fullscreenSpaceOf(winId) == nil
  end

  -- macOS 27: a window in Split View says it is not fullscreen, so
  -- setFullScreen(false) does nothing (seen with Mail next to Brave). Its
  -- fullscreen button does work: the window gets a fullscreen Space of its
  -- own (the new Space becomes active), which it then leaves as usual.
  if not win:isFullScreen() then
    local ok, button = pcall(function()
      return hs.axuielement.windowElement(win):attributeValue("AXFullScreenButton")
    end)
    if ok and button and button:performAction("AXPress") then
      log.info(label(application, winId) .. " is in Split View; pressed its fullscreen button")
      spaceUtils.waitFor(function() return fullscreenSpaceOf(winId) ~= sid end, 3, 0.1)
      spaceUtils.sleep(SETTLE)
      local own = fullscreenSpaceOf(winId)
      if own then spaceUtils.gotoSpaceAndWait(own) end
      win = waitForWindow(application, winId) or win
    end
  end

  win:setFullScreen(false)
  local ok = spaceUtils.waitFor(left, 2.5, 0.1)
  if not ok then
    log.warn("Leaving fullscreen via accessibility did not work for " .. label(application, winId) .. "; trying again")
    activate(application, win)
    win:setFullScreen(false)
    ok = spaceUtils.waitFor(left, 3, 0.1)
  end
  spaceUtils.sleep(SETTLE)

  if ok then
    done(label(application, winId) .. " left fullscreen")
  else
    done(label(application, winId) .. " did not leave fullscreen", nil, "error")
  end
  return ok and true or false
end

-- Where a fullscreen Space sits compared to the desktop it was made from.
local function placement(screen, sid, fromDesktop)
  local all = screen and spaces.spacesForScreen(screen) or {}
  local pos, fromPos
  for i, s in ipairs(all) do
    if s == sid then pos = i end
    if s == fromDesktop then fromPos = i end
  end
  -- "After its desktop" means in the group of fullscreen Spaces that follows
  -- that desktop, with no other desktop in between.
  local inGroup = pos and fromPos and pos > fromPos
  if inGroup then
    for i = fromPos + 1, pos - 1 do
      if spaces.spaceType(all[i]) == "user" then inGroup = false break end
    end
  end
  local where
  if pos and pos == #all then
    where = "at the end"
  elseif inGroup then
    where = "after its desktop"
  else
    where = "somewhere else"
  end
  return where, pos, #all
end

-- Puts a window into native fullscreen, starting from desktop `fromDesktop`.
-- Returns the new fullscreen Space id and where it landed ("at the end",
-- "after its desktop", "somewhere else"), or nil.
function M.enterFullscreen(application, winId, fromDesktop, screen)
  if fullscreenSpaceOf(winId) and not M.exitFullscreen(application, winId) then
    return nil
  end

  local done = log.step("Enter fullscreen")
  local moved = not helper.windowIsOnSpace(winId, fromDesktop)

  -- spacectl cannot move a window to a Space on another screen (seen in
  -- the logs), so such a window is first put on the right screen. Right
  -- after leaving fullscreen macOS may not report the window's Space yet,
  -- so Accessibility's idea of its screen is used as well.
  local function onOtherScreen()
    if not screen then return false end
    local known = false
    for _, sid in ipairs(spaces.windowSpaces(winId) or {}) do
      local s = spaceUtils.getScreenForSpace(sid)
      if s then
        known = true
        if s:id() ~= screen:id() then return true end
      end
    end
    if not known then
      local w = M.findWindow(application, winId)
      local ws = w and w:screen()
      return ws ~= nil and ws:id() ~= screen:id()
    end
    return false
  end

  local function toRightScreen()
    local win = waitForWindow(application, winId, 1)
    if not win then return end
    log.info("Moving " .. label(application, winId) .. " to " .. (screen:name() or "the right screen") .. " first")
    win:moveToScreen(screen, false, true)
    spaceUtils.waitFor(function() return not onOtherScreen() end, 1.0, 0.05)
  end

  if moved then
    if onOtherScreen() then toRightScreen() end
    if not helper.moveWindowToSpace(winId, fromDesktop, { quiet = true, timeoutMs = 800 }) then
      if onOtherScreen() then toRightScreen() else spaceUtils.sleep(0.2) end
      helper.moveWindowToSpace(winId, fromDesktop)
    end
  end

  local switched = spaces.activeSpaceOnScreen(screen) ~= fromDesktop
  spaceUtils.gotoSpaceAndWait(fromDesktop)
  local win = waitForWindow(application, winId)
  if not win then
    done("Cannot reach " .. label(application, winId) .. " to make it fullscreen", nil, "error")
    return nil
  end

  -- Let the move or the Space switch finish before asking for fullscreen.
  if moved or switched then spaceUtils.sleep(0.3) end

  local sid, how = goFullscreen(application, winId, win)
  spaceUtils.sleep(SETTLE)

  if not sid then
    done(label(application, winId) .. " did not go fullscreen", { moved = moved }, "error")
    return nil
  end

  local where, pos, total = placement(screen, sid, fromDesktop)
  local data = { space = sid, via = how, moved = moved, landed = where, position = pos, of = total }
  -- structure.lua expects every new fullscreen Space at the end.
  if where == "at the end" then
    done(label(application, winId) .. " is fullscreen", data)
  else
    done(label(application, winId) .. " is fullscreen but landed " .. where .. ", not at the end", data, "warn")
  end
  return sid, where
end

return M
