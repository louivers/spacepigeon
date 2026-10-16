-- Runs lua/dragbench.lua against the fake Mission Control of
-- tests/mcdrag_sim.lua. The fake only picks a thumbnail up when the first
-- move is small (a nudge), opens a gap after hovering it 0.15 s, and merges
-- a drop next to a fullscreen app made before that. So the winner must
-- nudge and drop when the gap is open (or after hovering long enough).
-- Run from the project root: lua tests/dragbench_sim.lua [smoke]
package.path = "./?.lua;" .. package.path
MCSIM_LIBRARY = true
local sim = dofile("tests/mcdrag_sim.lua")
local mcdrag = require("lua.mcdrag")
local bench = require("lua.dragbench")

local nextSid = 1000
local repairs = 0
bench.hooks.fullscreenWindows = function() return {} end
bench.hooks.repairSplit = function(screen, dragged)
  if dragged == nil and not sim.show():find("&") then return true end -- nothing to split at the start
  mcdrag.closeBar(screen)
  repairs = repairs + 1
  local order, names = sim.state()
  for _, sid in ipairs(order) do
    local a, b = names[sid]:match("^(.-) & (.+)$")
    if a then
      -- Like leaving and entering fullscreen: the app gets its own Space at the end.
      names[sid] = a
      nextSid = nextSid + 1
      names[nextSid] = "exit to full screen " .. b
      table.insert(order, nextSid)
      return true
    end
  end
  return false
end

sim.setup("b c u o t m e D D z D D")
local smoke = arg[1] == "smoke"
bench.run(smoke and { smoke = "1" } or {})

local failures = 0
local function check(title, ok)
  print((ok and "PASS  " or "FAIL  ") .. title)
  if not ok then failures = failures + 1 end
end

local function newest(ext)
  local p = io.popen("ls -t /tmp/spacepigeon-mcsim/dragbench/*." .. ext .. " 2>/dev/null | head -1")
  local path = p:read("*l")
  p:close()
  return path
end
local mdPath = newest("md")
local md = mdPath and io.open(mdPath):read("*a") or ""
local csvPath = newest("csv")
local rows = 0
for _ in io.lines(csvPath) do rows = rows + 1 end

local first = md:match("\n| 1 | ([^|]+) |")
print(md:match("^(.-)\n| 2 |") or md)
check("results written", mdPath ~= nil and rows > 1)
check("every Split View was repaired: " .. sim.show(), not sim.show():find("&") and #sim.state() == 12)
check("winner nudges and drops when the gap is open or after >= 0.2 s: " .. tostring(first),
  first ~= nil and first:find("nudge") ~= nil
  and (first:find("whenOpen") or first:find("hover200")) ~= nil)
check("winner never split", md:match("\n| 1 | [^|]+ | %d+ | %d+ | 0 | 0 | 0 |") ~= nil)
if not smoke then check("all moves were tried", md:find("not possible here") == nil) end
print(string.format("%d drags, %d repairs", rows - 1, repairs))
print(failures == 0 and "\ndrag test sim passes" or ("\n" .. failures .. " check(s) failed"))
os.exit(failures == 0 and 0 or 1)
