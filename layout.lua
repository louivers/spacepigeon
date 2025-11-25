local spaces = require("hs.spaces")
local app    = require("hs.application")
local spaceUtils = require("space_utils")

local M = {}

-- Wait until an app has a main window, then call callback(win)
local function waitForMainWindow(appName, callback)
  local tries    = 0
  local maxTries = 40  -- 10 seconds
  local t

  t = hs.timer.doEvery(0.25, function()
    local a   = app.get(appName)
    local win = a and a:mainWindow()

    if win then
      t:stop()
      callback(win)
    else
      tries = tries + 1
      if tries >= maxTries then
        t:stop()
        hs.alert.show("No window for " .. appName)
        callback(nil)
      end
    end
  end)
end

local function applyWindowPosition(win, pos)
  local scr = win:screen()
  if not scr then return end
  
  local f = scr:frame()
  
  if not pos or pos == "max" then
    win:setFrame(f)
  elseif pos == "left" then
    f.w = f.w / 2
    win:setFrame(f)
  elseif pos == "right" then
    f.x = f.x + (f.w / 2)
    f.w = f.w / 2
    win:setFrame(f)
  end
end

-- Layout application (single-phase with verification + retries)
function M.applyLayoutWithChecks(layout, done)
  local index = 1

  local function nextApp()
    if index > #layout then
      if done then done() end
      return
    end

    local entry = layout[index]
    index = index + 1

    -- Determine Target Space ID
    local spaceId = nil
    
    if entry.monitor and entry.space then
      -- New format: { monitor="main", space=1 }
      local monitorSpaces = spaceUtils.getSpacesForMonitor(entry.monitor)
      spaceId = monitorSpaces[entry.space]
    elseif entry.space then
       -- Legacy format: absolute index
       local all = spaceUtils.getSpaces()
       spaceId = all[entry.space]
    end

    if not spaceId then
      hs.alert.show("Missing space for " .. entry.name)
      nextApp()
      return
    end

    local maxAttempts = 3

    local function placeApp(attempt)
      attempt = attempt or 1
      if attempt > maxAttempts then
        hs.alert.show("Failed to place " .. entry.name)
        nextApp()
        return
      end

      -- 1. Go to target space and wait
      spaceUtils.gotoSpaceAndWait(spaceId)

      -- 2. Launch/focus the app
      hs.application.launchOrFocus(entry.name)

      -- 3. Wait for main window
      waitForMainWindow(entry.name, function(win)
        if not win then
          -- retry from scratch
          placeApp(attempt + 1)
          return
        end

        -- small extra wait so macOS finishes assigning space
        hs.timer.doAfter(0.5, function()
          local ws = spaces.windowSpaces(win) or {}
          local inTarget = false
          for _, sid in ipairs(ws) do
            if sid == spaceId then
              inTarget = true
              break
            end
          end

          if inTarget then
            -- Apply positioning and focus
            applyWindowPosition(win, entry.pos)
            win:focus()
            nextApp()
          else
            -- Check if on the wrong screen (common issue with multi-monitor)
            local winScreen = win:screen()
            local targetScreen = spaceUtils.getScreenForSpace(spaceId)
            
            if winScreen and targetScreen and winScreen:id() ~= targetScreen:id() then
              -- Attempt to move it to the correct screen
              win:moveToScreen(targetScreen)
              
              hs.timer.doAfter(0.8, function()
                -- Re-check space
                local ws2 = spaces.windowSpaces(win) or {}
                local nowInTarget = false
                for _, sid in ipairs(ws2) do
                  if sid == spaceId then nowInTarget = true; break end
                end
                
                if nowInTarget then
                  applyWindowPosition(win, entry.pos)
                  win:focus()
                  nextApp()
                else
                  -- Still failed? Kill app and try again in this space
                  local a = win:application()
                  if a then
                    a:kill9()
                    hs.timer.doAfter(1.0, function()
                      placeApp(attempt + 1)
                    end)
                  else
                    placeApp(attempt + 1)
                  end
                end
              end)
              return
            end

            -- Kill app and try again in this space
            local a = win:application()
            if a then
              a:kill9()
              hs.timer.doAfter(1.0, function()
                placeApp(attempt + 1)
              end)
            else
              placeApp(attempt + 1)
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
