local M = {}

local presets = {
  standard = {
    name   = "Standard",
    spaces = 3,
    layout = {
      -- Optional: add url="https://..." to open a specific webpage/deep link
      { name = "Safari",   space = 1, pos = "max", url = "https://news.ycombinator.com" },
      { name = "Terminal", space = 2, pos = "left" },
      { name = "Notes",    space = 2, pos = "right" },
      { name = "Music",    space = 3, pos = "max" },
    },
  },
}

-- Apps to keep alive when switching modes (e.g. Spotify)
M.keepAlive = {
  "Spotify",
}

M.presets = presets

M.bindings = {
  { mods = {"cmd", "alt", "ctrl"}, key = "S", preset = presets.standard },
}

return M
