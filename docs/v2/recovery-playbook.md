# Recovery Playbook

## Trigger Conditions
- `dockDesync`
- repeated `verificationFailed` after reconciliation
- private symbol path changed after macOS update

## Recovery Procedure
1. Capture telemetry and result payload from last command run.
2. Execute Dock restart.
3. Re-run reconciliation with same target request.
4. Verify observed state against target.
5. If failure persists, downgrade operation to dry-run and emit compatibility warning.

## Operational Commands
- Probe capabilities:
  - `swift run --package-path v2 spacepigeon probe`
- Dry-run reset:
  - `swift run --package-path v2 spacepigeon reset --main-spaces 4 --secondary-spaces 0 --close-all --dry-run`

## Manual Exit Hatch
When desktop state is unstable, user can:
1. Log out/in.
2. Kill Dock manually: `killall Dock`.
3. Re-run probe before next reset attempt.
