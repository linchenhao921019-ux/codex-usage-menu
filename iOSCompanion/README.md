# iOS Companion Prototype

This folder contains the iOS app and WidgetKit companion for the low-power sync design:

1. The Mac menu-bar app serves a small JSON snapshot on the local network.
2. The iOS app and Widget read the snapshot from the Mac while both devices are on the same Wi-Fi.
3. The Widget renders the latest snapshot without polling Codex directly.

## Xcode Setup

Open `CodexUsageCompanion.xcodeproj`, select your Apple development team, then build the `CodexUsageCompanion` scheme to a connected iPhone.

The project includes:

- `Shared/CodexUsageSnapshot.swift` to both targets
- `App/CodexUsageCompanionApp.swift` to the iOS app target
- `Widget/CodexUsageWidget.swift` and `Widget/CodexUsageWidgetBundle.swift` to the Widget Extension target
- `App/Assets.xcassets` with the app icon

The current prototype reads these Mac endpoints in order:

```text
http://Mac-mini.local:8765/snapshot
http://MacBook-Air.local:8765/snapshot
http://MacBookAir.local:8765/snapshot
```

When the iPhone is on the same Wi-Fi as Mac mini, it uses Mac mini first. When Mac mini is unreachable but the iPhone is on the same network as MacBook Air, it falls back to the MacBook Air snapshot. If the MacBook Air hostname is different, update `snapshotURLs` in `Shared/CodexUsageSnapshot.swift`.

## Battery Behavior

The Widget uses a 30-minute timeline request. iOS may refresh less often depending on system policy. If the Mac is off or unreachable, the Widget keeps showing the last successful snapshot and marks data as stale after one hour.
