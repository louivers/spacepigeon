-- === Workspace automation for PhD vs Chill ===

local workspaces = require("workspaces")

-- Bind workspace hotkeys
workspaces.bindWorkspaceHotkeys()

-- Bind reload config URL event
hs.urlevent.bind("reloadConfig", function(eventName, params)
  hs.reload()
end)
