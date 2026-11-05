// pencil_bridge (INFRA, docs/plans/m5-7/01-infra.md 3.3 and 6.12).
// R2-B1: an empty registration only — no channels yet. It exists so that the
// app's GeneratedPluginRegistrant, which references this class, keeps
// compiling on iOS between R2-B1 and J12 (review S-6). J12 adds the channels
// 'dev.noteapp/pencil/events' / 'dev.noteapp/pencil/methods', attach / detach
// and UIPencilInteractionDelegate.
import Flutter
import UIKit

public final class PencilBridgePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {}
}
