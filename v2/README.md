# SpacePigeon V2 (God Mode Prototype)

This directory contains the clean-slate private-API-first prototype.

## Build
```bash
swift build --package-path v2
```

## Probe Capabilities
```bash
swift run --package-path v2 spacepigeon probe
```

## Run Reset Prototype
```bash
swift run --package-path v2 spacepigeon reset --main-spaces 4 --secondary-spaces 0 --close-all --dry-run
```

## Run Compatibility Harness
```bash
./v2/scripts/run-compat-harness.sh
```
