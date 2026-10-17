-- lua/profile.lua: which profile Hammerspoon loads.
-- Run from the project root: lua tests/profile_sim.lua
package.path = "./?.lua;" .. package.path

local dir = "/tmp/spacepigeon-psim"
os.execute("rm -rf " .. dir .. " && mkdir -p " .. dir .. "/spacepigeon_profiles/demo")

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return {} end
  return nil
end
hs = { configdir = dir, fs = { attributes = exists } }

local function write(path, text)
  local f = assert(io.open(path, "w")); f:write(text); f:close()
end

local function load()
  package.loaded["lua.profile"] = nil
  return require("lua.profile")
end

local checks = {}
local p = load()
table.insert(checks, { "no marker: own setup", p.name == nil and p.dir == dir })

write(dir .. "/spacepigeon_profile", "demo\n")
p = load()
table.insert(checks, { "marker without the profile's config.lua: own setup", p.name == nil })

write(dir .. "/spacepigeon_profiles/demo/config.lua", "return { presets = {} }")
p = load()
table.insert(checks, { "marker and config.lua: demo profile", p.name == "demo" and p.dir == dir .. "/spacepigeon_profiles/demo" })

write(dir .. "/spacepigeon_profile", "default\n")
table.insert(checks, { "\"default\" means own setup", load().name == nil })

write(dir .. "/spacepigeon_profile", "../etc\n")
table.insert(checks, { "a name with a path in it is ignored", load().name == nil })

local failed = 0
for _, c in ipairs(checks) do
  print((c[2] and "PASS  " or "FAIL  ") .. c[1])
  if not c[2] then failed = failed + 1 end
end
print(failed == 0 and "\nprofile checks pass" or ("\n" .. failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
