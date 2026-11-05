# pencil_bridge — owned by INFRA: Apple Pencil double tap, squeeze, hover and barrel roll events. Plan: [docs/plans/m5-7/01-infra.md](../../docs/plans/m5-7/01-infra.md) 4.4 and 6.12

A Flutter plugin implemented on **iOS only** (contract [00-overview 7.2.13](../../docs/plans/m5-7/00-overview.md)). On the web, Android and desktop `PencilBridge.isSupported` is false, `capabilities()` returns the unsupported value and `events` is an empty stream — no channel is ever called. The entry point `package:pencil_bridge/pencil_bridge.dart` is web-safe (no `dart:io`; platform check = `kIsWeb` + `defaultTargetPlatform`).

State: the 2차 foundation step R2-B1 created the package with an empty entry point and an **empty** Swift registration (`PencilBridgePlugin.register(with:)` does nothing), so the app's `GeneratedPluginRegistrant` compiles on iOS. The Dart surface comes in R2-B8b, the Swift channels in J12.

## Layout

- `lib/pencil_bridge.dart` — the only entry point (contract names only).
- `ios/pencil_bridge.podspec` — CocoaPods (`s.platform = :ios, '15.0'`).
- `ios/pencil_bridge/Package.swift` — Swift Package Manager (`.iOS("15.0")`, `FlutterFramework`), Flutter 3.47.9 plugin template layout.
- `ios/pencil_bridge/Sources/pencil_bridge/PencilBridgePlugin.swift` — the plugin class (`pluginClass` in `pubspec.yaml`).

## Channels and event wire format (01-infra 4.4.3)

Channels: `dev.noteapp/pencil/events` (EventChannel) and `dev.noteapp/pencil/methods` (method `capabilities`). Each event is a `Map<String, Object?>`:

| `type` | required keys | optional keys | Dart |
|---|---|---|---|
| (all) | `type` (String), `t` (double, seconds — monotonic `ProcessInfo.systemUptime`) | | `timestamp = Duration(microseconds: (t * 1e6).round())` |
| `tap` | `action` (String) | `x`, `y` (double — a position only when both are present), `z` | `PencilTap` |
| `squeeze` | `phase`, `action` | `x`, `y`, `z`, `roll` | `PencilSqueeze` |
| `hover` | `x`, `y` | `z`, `altitude`, `azimuth`, `roll` | `PencilHover` |
| `roll` | `angle` | | `PencilRoll` |

Numbers arrive as `num` (`toDouble()`). An unknown `type` is dropped; unknown `action` / `phase` strings are kept as they are (the app adapter maps them). `capabilities` returns `{os, squeeze, hover, roll, prefersPencilOnlyDrawing, preferredTapAction, preferredSqueezeAction}`. Coordinates are Flutter global logical pixels.

## Tests

`ws test --package pencil_bridge` (VM). `test/pencil_wire_contract_test.dart` checks the Swift sources against the Dart side as text (the container has no Xcode): the class name equals `pluginClass`, it adopts `FlutterPlugin`, `register(with:)` exists, and `Package.swift` / the podspec point at the same sources.
