# Echoform

Near-ultrasonic echolocation for Mac, iPhone and AirPods. Chirps, multi-mic time-of-flight, occupancy, tracks. GPS unused.

**Download the disk image from [Releases](https://github.com/bpms9cmnxc-debug/Echoform/releases/latest)** — `Echoform-0.3.0.dmg`.

Do not use the repository URL as a website. Source lives here; the installer is the release asset.

## What you get

- SwiftUI + SceneKit macOS app (Apple silicon, macOS 26/27)
- Multi-band chirps, matched-filter ToF, occupancy grid
- AirPods as **speaker only** (no ear-mic)
- tA clock-sync for I/O bias (one-way range)
- `Scripts/make_dmg.sh` for a signed UDIF on a Mac with Xcode

## Install from the DMG

1. Open `Echoform-0.3.0.dmg`
2. Drag `Echoform.app` to Applications if the Mac build is present
3. Otherwise open `Echoform.xcodeproj` and Product → Archive, or run `Scripts/make_dmg.sh`

A GitHub Action on `macos-15` rebuilds a native UDIF whenever a `v*` tag is pushed.

## Build on your Mac

```bash
chmod +x Scripts/make_dmg.sh
./Scripts/make_dmg.sh
```

Needs Xcode with the macOS 26/27 SDK. Ad-hoc sign is the default; Developer ID + `notarytool` are commented in the script.

## Layout

```
Echoform/          Swift sources
Echoform.xcodeproj
Scripts/make_dmg.sh
Docs/              physics + hardware limits
dist/              disk images
```

MIT. See `LICENSE`.
