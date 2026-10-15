-- Tests lua/slots.lua (space numbers -> desktops and fullscreen positions).
-- Run from the project root: lua tests/slots_sim.lua
package.path = "./?.lua;" .. package.path
local slots = require("lua.slots")

local failures = 0
local function check(title, cond, detail)
  if not cond then failures = failures + 1 end
  print((cond and "PASS  " or "FAIL  ") .. title .. ((not cond and detail) and ("\n      " .. detail) or ""))
end

local function app(name, space, pos) return { name = name, space = space, pos = pos or "max" } end

-- 1. Basic: fullscreen first, normal app on position 3.
do
  local brave, cursor = app("Brave", 1, "fullscreen"), app("Cursor", 3)
  local r = slots.resolve({ brave, cursor }, 5, "position")
  check("fullscreen at 1 comes before desktop 1", r.afterOf[brave] == 0)
  check("Cursor at position 3 is desktop 2", r.desktopOf[cursor] == 2)
  check("4 desktops", r.desktops == 4)
  check("picture", r.picture == "1 Brave | 2 D | 3 D: Cursor | 4 D | 5 D", r.picture)
  check("no warnings", #r.warnings == 0)
end

-- 2. Many fullscreen apps next to each other, then two desktops.
do
  local list, names = {}, { "Brave", "Claude", "Cursor", "Obsidian", "Todoist", "Mail", "Mattermost" }
  for i, n in ipairs(names) do table.insert(list, app(n, i, "fullscreen")) end
  local zotero = app("Zotero", 8)
  table.insert(list, zotero)
  local r = slots.resolve(list, 9, "position")
  local allBefore = true
  for i = 1, 7 do if r.afterOf[list[i]] ~= 0 then allBefore = false end end
  check("seven fullscreen apps all before desktop 1", allBefore)
  check("Zotero at 8 is desktop 1", r.desktopOf[zotero] == 1)
  check("2 desktops", r.desktops == 2)
end

-- 3. Desktop, fullscreen, desktop, fullscreen.
do
  local a, b, c = app("A", 2, "fullscreen"), app("B", 4, "fullscreen"), app("C", 5)
  local r = slots.resolve({ a, b, c }, 5, "position")
  check("A after desktop 1", r.afterOf[a] == 1)
  check("B after desktop 2", r.afterOf[b] == 2)
  check("C on desktop 3", r.desktopOf[c] == 3)
  check("3 desktops", r.desktops == 3)
end

-- 4. Two fullscreen apps on the same number: list order, with a warning.
do
  local a, b, c = app("A", 2, "fullscreen"), app("B", 2, "fullscreen"), app("C", 3)
  local r = slots.resolve({ a, b, c }, 3, "position")
  check("both after desktop 1", r.afterOf[a] == 1 and r.afterOf[b] == 1)
  check("warning for the clash", #r.warnings == 1)
  check("picture keeps list order", r.picture == "1 D | 2 A | 2 B | 3 D: C", r.picture)
end

-- 5. Normal app on a fullscreen position goes on the next desktop.
do
  local a, b = app("A", 2, "fullscreen"), app("B", 2)
  local r = slots.resolve({ a, b }, 3, "position")
  check("B on the desktop after A", r.desktopOf[b] == 2)
  check("warning for B", #r.warnings == 1)
end

-- 6. Only fullscreen apps: a desktop is added at the end.
do
  local a, b = app("A", 1, "fullscreen"), app("B", 2, "fullscreen")
  local r = slots.resolve({ a, b }, 2, "position")
  check("one desktop added", r.desktops == 1)
  check("picture ends with the added desktop", r.picture == "1 A | 2 B | 3 D", r.picture)
end

-- 7. A number past the monitor's spaces adds desktops.
do
  local a = app("A", 4)
  local r = slots.resolve({ a }, 2, "position")
  check("A on desktop 4", r.desktopOf[a] == 4 and r.desktops == 4)
  check("warning for going past", #r.warnings == 1)
end

-- 8. Old configs keep their meaning.
do
  local a, b = app("A", 3, "fullscreen"), app("B", 2)
  local r = slots.resolve({ a, b }, 5, nil)
  check("old: 5 desktops", r.desktops == 5)
  check("old: fullscreen after desktop 3", r.afterOf[a] == 3)
  check("old: normal on desktop 2", r.desktopOf[b] == 2)
end

print(failures == 0 and "\nall slot cases pass" or ("\n" .. failures .. " check(s) failed"))
os.exit(failures == 0 and 0 or 1)
