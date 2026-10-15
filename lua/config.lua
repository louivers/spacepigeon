local M = {}

local presets = {
  standard = {
    name   = "Standard",
    spaces = 3,
    layout = {
      -- pos: "max", "fullscreen", halves ("left", "right", "top", "bottom"),
      -- thirds ("left-third", "center-third", "right-third",
      -- "left-two-thirds", "right-two-thirds"), quarters ("top-left",
      -- "top-right", "bottom-left", "bottom-right") or "center".
      -- space = position in Mission Control, counting desktops and
      -- fullscreen apps together from the left (see M.numbering below).
      -- Every position without a fullscreen app is a desktop.
      { name = "Safari",   space = 1, pos = "max", url = "https://news.ycombinator.com" },
      { name = "Terminal", space = 2, pos = "left" },
      { name = "Notes",    space = 2, pos = "right" },
      { name = "Music",    space = 3, pos = "max" },
    },
    -- Optional: the app to focus when the setup is done. Without it, the
    -- first app on the main monitor's first space gets focus.
    -- focus = "Terminal",
    -- Optional: a different layout per number of connected monitors. The
    -- mode matching the current count is used; otherwise spaces/layout above.
    -- modes = {
    --   { monitors = 2, spaces = { main = 2, secondary = 1 }, layout = {
    --       { name = "Safari",   monitor = "main",      space = 1, pos = "max" },
    --       { name = "Terminal", monitor = "main",      space = 2, pos = "max" },
    --       { name = "Music",    monitor = "secondary", space = 1, pos = "max" },
    --   } },
    -- },
  },
}

M.keepAlive = {
  "Spotify",
}

-- Before quitting one of these apps, press Cmd+S in each of its windows.
-- Leave out browsers and apps where Cmd+S does something else.
M.saveBeforeQuit = {}

-- Quit apps that are not part of the preset (and not in keepAlive).
-- Apps that are in the preset are never quit; their windows are moved.
M.quitOthers = true

-- If a window refuses to move, quit that app normally and relaunch it on its
-- Space (the old SpacePigeon behaviour). Set to false to just report it.
M.killFallback = true

-- Put fullscreen apps right after their desktop by dragging them in Mission
-- Control (the mouse moves for a moment). Set to false to leave them after
-- the last desktop, in order.
M.reorderFullscreen = true

-- Show the presets in the menu bar.
M.menubar = true

-- When a monitor is plugged in or unplugged, set up the last preset again
-- for the new monitor count. No apps are quit; windows are only moved.
M.followMonitors = false

-- "position": space numbers are positions in Mission Control (desktops and
-- fullscreen apps together). Without this line, space numbers count desktops
-- only, as in older SpacePigeon configs.
M.numbering = "position"

M.presets = presets

M.bindings = {
  { mods = {"cmd", "alt", "ctrl"}, key = "S", preset = presets.standard },
}

return M
