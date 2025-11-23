local M = {}

local presets = {
  phd = {
    name   = "PhD",
    spaces = 9,
    layout = {
      { name = "Brave Browser", space = 1, pos = "max" },
      { name = "Zotero",        space = 2, pos = "max" },
      { name = "Obsidian",      space = 3, pos = "max" },
      { name = "Mattermost",    space = 4, pos = "max" },
      { name = "Mail",          space = 5, pos = "max" },
      { name = "Calendar",      space = 6, pos = "max" },
      -- 7 intentionally left empty
      { name = "Marta",         space = 8, pos = "max" },
      { name = "Spotify",       space = 9, pos = "max" },
    },
  },
  chill = {
    name   = "Chill",
    spaces = 4,
    layout = {
      { name = "Brave Browser", space = 1, pos = "max" },
      -- 2 and 3 empty
      { name = "Marta",         space = 4, pos = "max" },
    },
  },
  casualCoding = {
    name   = "Casual Coding",
    spaces = 5,
    layout = {
      { name = "Brave Browser", space = 1, pos = "max" },
      { name = "Cursor",        space = 2, pos = "max" },
      -- 3 empty on purpose
      { name = "Marta",         space = 4, pos = "max" },
      { name = "Spotify",       space = 5, pos = "max" },
    },
  },
  split = {
    name   = "Split Coding",
    spaces = 4,
    layout = {
      { name = "Cursor",        space = 1, pos = "left" },
      { name = "Brave Browser", space = 1, pos = "right" },
      { name = "Marta",         space = 2, pos = "max" },
      { name = "Spotify",       space = 3, pos = "max" },
    },
  },
}

M.presets = presets

M.bindings = {
  { mods = {"cmd", "alt", "ctrl"}, key = "P", preset = presets.phd },
  { mods = {"cmd", "alt", "ctrl"}, key = "C", preset = presets.chill },
  { mods = {"cmd", "alt", "ctrl"}, key = "D", preset = presets.casualCoding },
  { mods = {"cmd", "alt", "ctrl"}, key = "S", preset = presets.split },
}

return M
