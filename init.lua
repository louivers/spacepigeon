-- === Workspace automation for PhD vs Chill ===

-- Bind reload config URL event.
-- Some URL dispatchers can lowercase the event name, so accept both.
local function reloadConfigEvent()
  hs.reload()
end

hs.urlevent.bind("reloadConfig", reloadConfigEvent)
hs.urlevent.bind("reloadconfig", reloadConfigEvent)

-- Load main workspace module after registering reload handlers so URL reload
-- keeps working even if workspace setup has an error.
local ok, workspacesOrErr = pcall(require, "workspaces")
if not ok then
  print("SpacePigeon init error (require workspaces): " .. tostring(workspacesOrErr))
  hs.alert.show("SpacePigeon init error - check Hammerspoon Console")
  return
end

local bindOk, bindErr = pcall(function()
  workspacesOrErr.bindWorkspaceHotkeys()
end)
if not bindOk then
  print("SpacePigeon init error (bind hotkeys): " .. tostring(bindErr))
  hs.alert.show("SpacePigeon hotkey error - check Console")
end
