-- Turns a preset's "space" numbers into desktops and fullscreen positions.
--
-- Space numbers are positions in Mission Control, counting desktops and
-- fullscreen apps together, left to right. With 5 spaces on a monitor,
-- Brave fullscreen at 1 and Cursor (normal) at 3:
--
--   1 Brave (fullscreen) | 2 desktop | 3 desktop with Cursor | 4 desktop | 5 desktop
--
-- Every position that has no fullscreen app is a desktop. Normal apps go on
-- the desktop at their position.
--
-- Old configs (written before config.numbering = "position") used the space
-- number as the desktop number, and for a fullscreen app as the desktop it
-- comes right after. Those still work the old way.

local M = {}

-- entries: the preset's layout entries for one monitor, in list order.
-- total: the number of spaces set for that monitor.
-- numbering: "position" (new) or anything else (old, by desktop).
-- Returns {
--   desktops = number of desktops,
--   desktopOf = { [entry] = desktop number } for normal apps,
--   afterOf = { [entry] = desktop number it follows (0 = before desktop 1) }
--             for fullscreen apps,
--   warnings = { "...", ... },
--   picture = "1 Brave | 2 D | 3 D: Cursor | ...",
-- }
function M.resolve(entries, total, numbering)
  total = tonumber(total) or 0
  local result = { desktops = 0, desktopOf = {}, afterOf = {}, warnings = {}, picture = "" }

  if numbering ~= "position" then
    result.desktops = total
    for _, e in ipairs(entries) do
      local n = tonumber(e.space) or 1
      if e.pos == "fullscreen" then
        result.afterOf[e] = math.max(1, math.min(n, math.max(total, 1)))
      else
        result.desktopOf[e] = n
      end
    end
    return result
  end

  local fsAt, normalAt = {}, {}
  local last = total
  for _, e in ipairs(entries) do
    local n = math.max(1, math.floor(tonumber(e.space) or 1))
    local bucket = (e.pos == "fullscreen") and fsAt or normalAt
    bucket[n] = bucket[n] or {}
    table.insert(bucket[n], e)
    if n > last then
      last = n
      table.insert(result.warnings, string.format(
        "%s is at space %d, but the monitor has %d space(s); adding more", e.name, n, total))
    end
  end

  local desktops, waiting, parts = 0, {}, {}
  local function addDesktop(position, apps)
    desktops = desktops + 1
    local names = {}
    for _, e in ipairs(apps) do
      result.desktopOf[e] = desktops
      table.insert(names, e.name)
    end
    table.insert(parts, tostring(position) .. " D" .. (#names > 0 and (": " .. table.concat(names, ", ")) or ""))
  end

  for p = 1, last do
    local fs = fsAt[p]
    if fs then
      if #fs > 1 then
        local names = {}
        for _, e in ipairs(fs) do table.insert(names, e.name) end
        table.insert(result.warnings, string.format(
          "Several fullscreen apps at space %d (%s); they follow each other in list order",
          p, table.concat(names, ", ")))
      end
      for _, e in ipairs(fs) do
        result.afterOf[e] = desktops
        table.insert(parts, tostring(p) .. " " .. e.name)
      end
      for _, e in ipairs(normalAt[p] or {}) do
        table.insert(result.warnings, string.format(
          "%s is at space %d, which is a fullscreen app; it goes on the next desktop", e.name, p))
        table.insert(waiting, e)
      end
    else
      local apps = waiting
      waiting = {}
      for _, e in ipairs(normalAt[p] or {}) do table.insert(apps, e) end
      addDesktop(p, apps)
    end
  end

  -- macOS needs at least one desktop, and apps that were pushed past the
  -- last space need one too.
  if desktops == 0 or #waiting > 0 then
    if desktops == 0 and last > 0 then
      table.insert(result.warnings, "Every space is a fullscreen app; adding a desktop at the end (macOS needs one)")
    end
    if last > 0 then addDesktop(last + 1, waiting) end
  end

  result.desktops = desktops
  result.picture = table.concat(parts, " | ")
  return result
end

return M
