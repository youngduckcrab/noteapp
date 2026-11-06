// pencil_bridge (INFRA, docs/plans/m5-7/01-infra.md 4.4.3 and 6.12.2): the
// channel names, wire strings and event maps. lib/src/wire.dart holds the
// same constants and decodes these maps — test/pencil_wire_contract_test.dart
// compares the two files as text (no Swift compiler in the container).
//
// One builder per event `type`. Its dictionary literal holds `type`, `t` and
// the required keys; an optional key is set (event["k"] = ...) only when
// there is a value. Numbers go out as Double (the standard message codec
// sends them as float64; Dart reads `num`).
import UIKit

enum PencilWire {
  static let eventChannel = "dev.noteapp/pencil/events"
  static let methodChannel = "dev.noteapp/pencil/methods"
  static let capabilitiesMethod = "capabilities"

  /// Hover and roll events closer together than this are dropped (≤ 60 Hz).
  static let minInterval: TimeInterval = 0.016

  // MARK: - Events (4.4.3)

  static func tapEvent(
    t: TimeInterval, action: String, position: CGPoint?, z: CGFloat?
  ) -> [String: Any] {
    var event: [String: Any] = ["type": "tap", "t": t, "action": action]
    if let position = position {
      event["x"] = Double(position.x)
      event["y"] = Double(position.y)
    }
    if let z = z {
      event["z"] = Double(z)
    }
    return event
  }

  static func squeezeEvent(
    t: TimeInterval, phase: String, action: String, position: CGPoint?, z: CGFloat?,
    roll: CGFloat?
  ) -> [String: Any] {
    var event: [String: Any] = [
      "type": "squeeze", "t": t, "phase": phase, "action": action,
    ]
    if let position = position {
      event["x"] = Double(position.x)
      event["y"] = Double(position.y)
    }
    if let z = z {
      event["z"] = Double(z)
    }
    if let roll = roll {
      event["roll"] = Double(roll)
    }
    return event
  }

  static func hoverEvent(
    t: TimeInterval, position: CGPoint, z: CGFloat?, altitude: CGFloat?, azimuth: CGFloat?,
    roll: CGFloat?
  ) -> [String: Any] {
    var event: [String: Any] = [
      "type": "hover", "t": t, "x": Double(position.x), "y": Double(position.y),
    ]
    if let z = z {
      event["z"] = Double(z)
    }
    if let altitude = altitude {
      event["altitude"] = Double(altitude)
    }
    if let azimuth = azimuth {
      event["azimuth"] = Double(azimuth)
    }
    if let roll = roll {
      event["roll"] = Double(roll)
    }
    return event
  }

  static func rollEvent(t: TimeInterval, angle: CGFloat) -> [String: Any] {
    let event: [String: Any] = ["type": "roll", "t": t, "angle": Double(angle)]
    return event
  }

  // MARK: - Names

  /// Wire name of a UIPencilPreferredAction (PencilWire.actions in Dart). A
  /// value iPadOS adds later is "unknown" — the app adapter maps the string.
  static func actionName(_ action: UIPencilPreferredAction) -> String {
    if #available(iOS 17.5, *) {
      switch action {
      case .ignore: return "ignore"
      case .switchEraser: return "switchEraser"
      case .switchPrevious: return "switchPrevious"
      case .showColorPalette: return "showColorPalette"
      case .showInkAttributes: return "showInkAttributes"
      case .showContextualPalette: return "showContextualPalette"
      case .runSystemShortcut: return "runSystemShortcut"
      @unknown default: return "unknown"
      }
    }
    if #available(iOS 16.0, *), action == .showInkAttributes {
      return "showInkAttributes"
    }
    switch action {
    case .ignore: return "ignore"
    case .switchEraser: return "switchEraser"
    case .switchPrevious: return "switchPrevious"
    case .showColorPalette: return "showColorPalette"
    default: return "unknown"
    }
  }
}
