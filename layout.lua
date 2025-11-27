local spaces = require("hs.spaces")
local app    = require("hs.application")
local spaceUtils = require("space_utils")

local M = {}

-- Helper: Wait for main window
local function waitForMainWindow(appName, callback)
  local tries, maxTries = 0, 40
  local t
  t = hs.timer.doEvery(0.25, function()
    local a = app.get(appName)
    local win = a and a:mainWindow()
    if win then
      t:stop()
      callback(win)
    elseif tries >= maxTries then
      t:stop()
      hs.alert.show("No window for " .. appName)
      callback(nil)
    else
      tries = tries + 1
    end
  end)
end

-- Helper: Position window
local function applyWindowPosition(win, pos)
  local scr = win:screen()
  if not scr then return end
  local f = scr:frame()
  
  if pos == "left" then
    f.w = f.w / 2
  elseif pos == "right" then
    f.x = f.x + (f.w / 2)
    f.w = f.w / 2
  end
  -- "max" or nil uses full frame
  win:setFrame(f)
end

-- Helper: Open URL in a "Fresh" Single Window (The "Pivot" Strategy)
local function openUrlCleanly(appName, url)
  appName = appName:match("^%s*(.-)%s*$") -- trim
  local script = nil

  if appName == "Safari" then
     -- Safari Strategy: Create new doc, close all others.
     script = string.format([[
        tell application "Safari"
            activate
            set newDoc to make new document with properties {URL:"%s"}
            set newWin to window 1
            
            -- Close all other windows
            set allWins to every window
            repeat with w in allWins
                if (id of w) is not (id of newWin) then
                    close w
                end if
            end repeat
        end tell
     ]], url)
  elseif appName == "Google Chrome" or appName == "Arc" or appName == "Brave Browser" or appName == "Microsoft Edge" then
     -- Chromium Strategy: Create new window, close all others.
     script = string.format([[
        tell application "%s"
            activate
            set newWin to make new window
            set URL of active tab of newWin to "%s"
            
            -- Close all other windows
            set allWins to every window
            repeat with w in allWins
                if (id of w) is not (id of newWin) then
                    close w
                end if
            end repeat
        end tell
     ]], appName, url)
  end

  if script then
    local ok, _, err = hs.osascript.applescript(script)
    if not ok then
      print("SpacePigeon Error: " .. tostring(err))
      hs.execute(string.format("open -a %q %q", appName, url))
    end
  else
    hs.execute(string.format("open -a %q %q", appName, url))
  end
end

function M.applyLayoutWithChecks(layout, done)
  local index = 1

  local function nextApp()
    if index > #layout then
      if done then done() end
      return
    end

    local entry = layout[index]
    index = index + 1

    -- Resolve Space
    local spaceId = nil
    if entry.monitor and entry.space then
      local monitorSpaces = spaceUtils.getSpacesForMonitor(entry.monitor)
      spaceId = monitorSpaces[entry.space]
    elseif entry.space then
       local all = spaceUtils.getSpaces()
       spaceId = all[entry.space]
    end

    if not spaceId then
      hs.alert.show("Missing space for " .. entry.name)
      nextApp()
      return
    end

    local function placeApp(attempt)
      if attempt > 3 then
        hs.alert.show("Failed to place " .. entry.name)
        nextApp()
        return
      end

      spaceUtils.gotoSpaceAndWait(spaceId)
      hs.application.launchOrFocus(entry.name)

      waitForMainWindow(entry.name, function(win)
        if not win then
          placeApp(attempt + 1)
          return
        end

        -- Wait for space assignment
        hs.timer.doAfter(0.5, function()
          local ws = spaces.windowSpaces(win) or {}
          local inTarget = false
          for _, sid in ipairs(ws) do
            if sid == spaceId then inTarget = true; break end
          end

          if inTarget then
            applyWindowPosition(win, entry.pos)
            win:focus()
            
            if entry.url then
              hs.timer.usleep(500000) -- 0.5s wait for browser readiness
              openUrlCleanly(entry.name, entry.url)
            end

            nextApp()
          else
            -- Wrong screen logic: move or kill retry
            local winScreen = win:screen()
            local targetScreen = spaceUtils.getScreenForSpace(spaceId)
            
            if winScreen and targetScreen and winScreen:id() ~= targetScreen:id() then
              win:moveToScreen(targetScreen)
              hs.timer.doAfter(0.8, function()
                 -- Simple re-check
                 local ws2 = spaces.windowSpaces(win) or {}
                 for _, sid in ipairs(ws2) do
                   if sid == spaceId then
                     applyWindowPosition(win, entry.pos)
                     win:focus()
                     if entry.url then openUrlCleanly(entry.name, entry.url) end
                     nextApp()
                     return
                   end
                 end
                 -- Failed move, retry from scratch
                 if win:application() then win:application():kill9() end
                 hs.timer.doAfter(1.0, function() placeApp(attempt + 1) end)
              end)
            else
               -- Same screen but wrong space? Move it!
               spaces.moveWindowToSpace(win:id(), spaceId)
               hs.timer.doAfter(0.8, function()
                  -- Re-check
                  local ws3 = spaces.windowSpaces(win) or {}
                  for _, sid in ipairs(ws3) do
                    if sid == spaceId then
                      applyWindowPosition(win, entry.pos)
                      win:focus()
                      if entry.url then openUrlCleanly(entry.name, entry.url) end
                      nextApp()
                      return
                    end
                  end
                  
                  -- If still failed, THEN kill
                  if win:application() then win:application():kill9() end
                  hs.timer.doAfter(1.0, function() placeApp(attempt + 1) end)
               end)
            end
          end
        end)
      end)
    end

    placeApp(1)
  end

  nextApp()
end

return M
