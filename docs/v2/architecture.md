# SpacePigeon V2 Architecture

## Objective
V2 is designed for maximum control over Spaces/window placement under a power-user security model (including SIP-reduced setups).

## Components
- `spacepigeon` CLI: operator entrypoint for `probe` and `reset`.
- `spacepigeond`: daemon transport prototype (stdin/stdout now, XPC later).
- `SpacePigeonCore`: shared execution engine.

## Engine Hierarchy
1. `EnginePrivateCGS`: private framework symbol loading and managed-space operations.
2. `EngineAX`: accessibility fallback for app/window state validation.
3. `EngineRobot`: Mission Control simulation fallback for recovery.

## Reset Pipeline
1. Capability probe and macOS version gate.
2. App lifecycle reconciliation (`--close-all` + keep-alive allowlist).
3. Space reconciliation to target graph.
4. Verification and structured JSON result output.
5. Optional Dock restart recovery and re-verify.

## Failure Taxonomy
- `permission`
- `symbolMissing`
- `dockDesync`
- `timeout`
- `verificationFailed`
- `unsupportedMacOS`
- `shellError`
