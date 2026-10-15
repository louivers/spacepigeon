# V2 Compatibility Matrix

## Status Legend
- `green`: expected stable for prototype workflows
- `yellow`: usable with caveats
- `red`: unsupported

## Matrix
| macOS | PrivateFrameworkLoad | SymbolSet | ResetPipeline |
|---|---|---|---|
| 14.x | yellow | yellow | yellow |
| 15.x | green | yellow | yellow |
| 16.x+ | yellow | red | red |

## Notes
- Symbol compatibility must be validated per point release.
- A missing symbol should fail fast with `symbolMissing`.
- Any Dock instability should trigger `dock_restart_and_reconcile` flow.
