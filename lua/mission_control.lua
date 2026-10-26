-- Finds Mission Control's Accessibility elements: the Spaces bar of a
-- screen and its "add desktop" button. They only exist while Mission
-- Control is open.
--
-- Up to macOS 26 they belong to the Dock:
--   Dock > "mc" > "mc.display" > "mc.spaces" > "mc.spaces.list" / "mc.spaces.add"
-- hs.spaces relies on that. macOS 27 draws Mission Control in WindowManager
-- (the process behind Stage Manager) instead, with the same identifiers but
-- "mc.display" right under the application, while the Dock's "mc" group is
-- empty. hs.spaces.gotoSpace, removeSpace and addSpaceToScreen then fail
-- with "no display with specified id found", so on macOS 27 SpacePigeon
-- presses these buttons itself (lua/space_utils.lua). The Dock still adds
-- its empty "mc" group while Mission Control is open, so
-- hs.spaces.openMissionControl and closeMissionControl keep working.

local M = {}

local version = hs.host and hs.host.operatingSystemVersion and hs.host.operatingSystemVersion()
M.inWindowManager = (version and version.major or 0) >= 27

local function children(e)
  if not e then return {} end
  local ok, list = pcall(function() return e.AXChildren end)
  return ok and list or {}
end

local function child(e, identifier)
  for _, c in ipairs(children(e)) do
    if c.AXIdentifier == identifier then return c end
  end
  return nil
end

local function find(el, identifier, depth)
  if not el or depth < 0 then return nil end
  local ok, id = pcall(function() return el.AXIdentifier end)
  if ok and id == identifier then return el end
  for _, c in ipairs(children(el)) do
    local found = find(c, identifier, depth - 1)
    if found then return found end
  end
  return nil
end

local function appElement(bundleID)
  local a = hs.application.get(bundleID)
  return a and require("hs.axuielement").applicationElement(a) or nil
end

-- The elements the "mc.display" groups hang under, the likely one first.
local function roots()
  local wm = appElement("com.apple.WindowManager")
  local mc = child(appElement("com.apple.dock"), "mc")
  local first, second = mc, wm
  if M.inWindowManager then first, second = wm, mc end
  local list = {}
  if first then table.insert(list, first) end
  if second then table.insert(list, second) end
  return list
end

-- The "mc.display" group of a screen, or nil and a reason.
function M.displayGroup(screen)
  local single = #hs.screen.allScreens() == 1
  local sawDisplay = false
  for _, root in ipairs(roots()) do
    local other = nil
    for _, c in ipairs(children(root)) do
      if c.AXIdentifier == "mc.display" then
        if tonumber(c.AXDisplayID) == screen:id() then return c end
        sawDisplay, other = true, other or c
      end
    end
    -- With one screen any group will do, or the root itself when the bar
    -- hangs right under it.
    local fallback = other or root
    if single and find(fallback, "mc.spaces.list", 4) then return fallback end
  end
  if sawDisplay then return nil, "no Mission Control group for this screen" end
  return nil, "Mission Control is not open"
end

local function spacesGroupItem(screen, identifier, missing)
  local display, err = M.displayGroup(screen)
  if not display then return nil, err end
  local item = child(child(display, "mc.spaces"), identifier) or find(display, identifier, 4)
  if not item then return nil, missing end
  return item
end

-- The Spaces bar of a screen: a list with one button per Space, left to
-- right. Or nil and a reason.
function M.spacesList(screen)
  return spacesGroupItem(screen, "mc.spaces.list", "no Spaces bar")
end

-- The "add desktop" button of a screen, or nil and a reason.
function M.addButton(screen)
  return spacesGroupItem(screen, "mc.spaces.add", "no add desktop button")
end

-- macOS 27.0 reports a Spaces bar thumbnail's centre as its position (in
-- AXFrame and AXPosition alike), so the frame is half a thumbnail right of
-- and below where the thumbnail is drawn (seen: frame 178,120 for a
-- thumbnail window at 93,55, both 169x129). Drags aimed at those frames
-- missed. Accessibility hit-testing goes by the same frames, but the bar's
-- own frame is right (0,0 1728x188 there): full-size thumbnails fill most
-- of its height, so a centred frame sticks out below it. Checked until it
-- is clear.
local centered = nil

local function thumbnailsCentered(list, frame)
  local bar = list.AXFrame
  if not bar or frame.h < 40 then return nil end -- the small bar does not tell
  return frame.y + frame.h > bar.y + bar.h + 2
end

-- The thumbnails of a Spaces bar (from spacesList), left to right:
-- { name = ..., frame = { x, y, w, h } }, framed where they are drawn.
function M.thumbnails(list)
  local out = {}
  for _, b in ipairs(list.AXChildren or {}) do
    local f = b.AXFrame
    table.insert(out, {
      name = b.AXDescription or b.AXTitle or "?",
      frame = f and { x = f.x, y = f.y, w = f.w, h = f.h },
    })
  end
  local first = out[1] and out[1].frame
  if not (M.inWindowManager and first) then return out end
  if centered == nil then centered = thumbnailsCentered(list, first) end
  -- Not known yet: what macOS 27.0 does.
  if centered ~= false then
    for _, t in ipairs(out) do
      if t.frame then t.frame.x, t.frame.y = t.frame.x - t.frame.w / 2, t.frame.y - t.frame.h / 2 end
    end
  end
  return out
end

return M
