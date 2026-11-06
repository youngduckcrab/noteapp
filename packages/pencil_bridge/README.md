# pencil_bridge — owned by INFRA: Apple Pencil double tap, squeeze, hover and barrel roll events. Plan: [docs/plans/m5-7/01-infra.md](../../docs/plans/m5-7/01-infra.md) 4.4 and 6.12

A Flutter plugin implemented on **iOS only** (contract [00-overview 7.2.13](../../docs/plans/m5-7/00-overview.md)). On the web, Android and desktop `PencilBridge.isSupported` is false, `capabilities()` returns the unsupported value and `events` is an empty stream — no channel is ever called. The entry point `package:pencil_bridge/pencil_bridge.dart` is web-safe (no `dart:io`; platform check = `kIsWeb` + `defaultTargetPlatform`).

State: the Dart surface is complete (R2-B8b) and the Swift side is written (J12): the two channels, attach on the first listener / detach on the last cancel, `UIPencilInteraction` (double tap; squeeze on iPadOS 17.5+), a pencil hover recognizer and a passive barrel-roll recognizer (17.5+). The container has no Xcode, so the Swift sources are only checked as text against the Dart constants (`pencil_wire_contract_test`); the first real compile is `ios-compile.yml` (U19) and the behaviour on a device is checked after TestFlight (real device check C-1).

## Layout

- `lib/pencil_bridge.dart` — the only entry point (contract names only: `PencilBridge`, `PencilEvent`, `PencilTap`, `PencilSqueeze`, `PencilHover`, `PencilRoll`, `PencilCapabilities`).
- `lib/src/pencil_bridge_impl.dart` — `PencilBridge`: `isSupported` (`!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS`), `capabilities()`, the cached `events` stream (`receiveBroadcastStream().handleError(…).map(decode).where(non-null)` — no `asBroadcastStream()`, so the last cancel reaches the native side), `debugDroppedEvents` / `debugReset()` for tests.
- `lib/src/pencil_events.dart` — the value types (`==`, `hashCode`, `toString`).
- `lib/src/wire.dart` — `PencilWire`: channel names, wire strings, the key table and `decode` (the Swift side repeats these constants).
- `ios/pencil_bridge.podspec` — CocoaPods (`s.platform = :ios, '15.0'`).
- `ios/pencil_bridge/Package.swift` — Swift Package Manager (`.iOS("15.0")`, `FlutterFramework`), Flutter 3.47.9 plugin template layout.
- `ios/pencil_bridge/Sources/pencil_bridge/PencilBridgePlugin.swift` — the plugin class (`pluginClass` in `pubspec.yaml`): registers the channels (no UI work at registration — under UIScene there may be no window yet) and answers `capabilities` (`squeeze` / `roll` = iPadOS 17.5+, `hover` = 16.1+ — OS availability, not the pencil model).
- `ios/pencil_bridge/Sources/pencil_bridge/PencilEventStream.swift` — the `FlutterStreamHandler`: on listen it attaches to `registrar.viewController.view` (the Flutter view of this engine), else the key window's root view, else waits for `UIWindow.didBecomeKeyNotification`; on cancel it removes everything. Hover and roll are sent at most 60 times a second; both recognizers recognize simultaneously with the engine's own.
- `ios/pencil_bridge/Sources/pencil_bridge/PencilRollRecognizer.swift` — passive `UIGestureRecognizer` (17.5+): reads `UITouch.rollAngle` of the pencil, never recognizes, never cancels or delays Flutter's touches.
- `ios/pencil_bridge/Sources/pencil_bridge/PencilWire.swift` — the Swift copy of `PencilWire`: channel names, one map builder per event type, the action names.

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

`ws test --package pencil_bridge` (VM).

- `test/pencil_bridge_test.dart` — decoding of the four event types, dropped events, the listen / cancel counts of the native side over a mock stream handler (two listeners → last cancel detaches once → a later listener attaches again), the cached stream, `capabilities()` decoding and errors, and no channel call on other platforms.
- `test/api_surface_test.dart` — the entry point shows exactly the contract names; typed references to every member.
- `test/pencil_wire_contract_test.dart` — checks the Swift sources against the Dart side as text (the container has no Xcode): the class name equals `pluginClass` and adopts `FlutterPlugin`; channel names; `type` values and the keys of each event builder against the 4.4.3 table (and the built maps decode in Dart); capabilities keys; action and phase names; every iPadOS 16 / 17.5 API inside `@available` / `#available`; `Package.swift` / the podspec build every Swift file for iOS 15.0 ≤ the app's deployment target; `registrar.viewController` first, simultaneous recognition, a passive roll recognizer and the 60 Hz limit.
