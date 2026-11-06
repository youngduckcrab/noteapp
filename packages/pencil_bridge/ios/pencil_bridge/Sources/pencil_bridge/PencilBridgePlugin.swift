// pencil_bridge (INFRA, docs/plans/m5-7/01-infra.md 4.4.4 and 6.12.2,
// contract 00-overview 7.2.13). The plugin class: registers the two channels
// and answers 'capabilities'. Events (attach / detach, UIPencilInteraction,
// hover and roll) are PencilEventStream's — the FlutterStreamHandler of
// 'dev.noteapp/pencil/events'.
//
// Registration does no UI work: under UIScene there may be no window yet
// (research 02 9.2). The first Dart listener attaches (onListen).
import Flutter
import UIKit

public final class PencilBridgePlugin: NSObject, FlutterPlugin {
  private let events: PencilEventStream

  init(events: PencilEventStream) {
    self.events = events
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let events = PencilEventStream(registrar: registrar)
    let instance = PencilBridgePlugin(events: events)
    let methods = FlutterMethodChannel(
      name: PencilWire.methodChannel, binaryMessenger: messenger)
    registrar.addMethodCallDelegate(instance, channel: methods)
    let eventChannel = FlutterEventChannel(
      name: PencilWire.eventChannel, binaryMessenger: messenger)
    eventChannel.setStreamHandler(events)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case PencilWire.capabilitiesMethod:
      result(PencilBridgePlugin.capabilities())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    events.detach()
  }

  /// The 'capabilities' result (4.4.3). squeeze / roll are the OS availability
  /// (iPadOS 17.5+) only, not the pencil model (contract 7.2.10 v2.1, CD2-24);
  /// hover is 16.1+.
  static func capabilities() -> [String: Any] {
    var squeeze = false
    var hover = false
    var roll = false
    var squeezeAction = "unknown"
    if #available(iOS 16.1, *) {
      hover = true
    }
    if #available(iOS 17.5, *) {
      squeeze = true
      roll = true
      squeezeAction = PencilWire.actionName(UIPencilInteraction.preferredSqueezeAction)
    }
    return [
      "os": UIDevice.current.systemVersion,
      "squeeze": squeeze,
      "hover": hover,
      "roll": roll,
      "prefersPencilOnlyDrawing": UIPencilInteraction.prefersPencilOnlyDrawing,
      "preferredTapAction": PencilWire.actionName(UIPencilInteraction.preferredTapAction),
      "preferredSqueezeAction": squeezeAction,
    ]
  }
}
