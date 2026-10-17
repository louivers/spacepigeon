-- The active profile, written by the SpacePigeon app when it saves.
--
-- Without one (what every user gets) the config is lua/config.lua and the
-- log is ~/.hammerspoon/spacepigeon.log. ~/.hammerspoon/spacepigeon_profile
-- can name a profile (e.g. "demo"); its config.lua and log then live in
-- ~/.hammerspoon/spacepigeon_profiles/<name>/, so a demo or test setup
-- never touches your own presets.

local M = { name = nil, dir = hs.configdir }

local f = io.open(hs.configdir .. "/spacepigeon_profile", "r")
if f then
  local name = (f:read("l") or ""):match("^%s*([%w_-]+)%s*$")
  f:close()
  if name and name ~= "default" then
    local dir = hs.configdir .. "/spacepigeon_profiles/" .. name
    if hs.fs.attributes(dir .. "/config.lua") then
      M.name = name
      M.dir = dir
    end
  end
end

return M
