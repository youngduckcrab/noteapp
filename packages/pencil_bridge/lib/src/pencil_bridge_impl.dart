// PencilBridge (contract 00-overview 7.2.13, docs/plans/m5-7/01-infra.md
// 4.4.2 and 6.12.1). Web-safe: no dart:io — the platform check is kIsWeb +
// defaultTargetPlatform.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pencil_events.dart';
import 'wire.dart';

abstract final class PencilBridge {
  /// !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS (tests: debugDefaultTargetPlatformOverride).
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Not supported → PencilCapabilities.unsupported, no channel call. On iOS: method 'capabilities'
  /// on 'dev.noteapp/pencil/methods'; PlatformException / MissingPluginException are rethrown
  /// (the app adapter logs them and keeps NoStylusExtras).
  ///
  /// A result that is not a map throws a [PlatformException] with code
  /// `invalid-result`.
  static Future<PencilCapabilities> capabilities() async {
    if (!isSupported) return PencilCapabilities.unsupported;
    final result = await const MethodChannel(PencilWire.methodChannel)
        .invokeMethod<Object?>(PencilWire.capabilitiesMethod);
    if (result is! Map) {
      throw PlatformException(
        code: 'invalid-result',
        message: 'pencil_bridge: capabilities returned ${result.runtimeType}',
      );
    }
    return PencilCapabilities.fromWire(result.cast<Object?, Object?>());
  }

  /// Broadcast. Attaches UIPencilInteraction + hover / roll recognizers on first listen
  /// (key window may not exist at plugin registration under UIScene), detaches on last cancel.
  ///
  /// Not supported → const Stream.empty(). Else one cached stream:
  /// EventChannel.receiveBroadcastStream().map(PencilWire.decode).where(non-null) — already a
  /// broadcast stream (map / where keep it), so NO asBroadcastStream(): that would keep the native
  /// subscription after the last cancel. The first listener triggers native attach (onListen), the
  /// last cancel detaches (onCancel); a later listener attaches again (contract 7.2.13).
  /// Undecodable maps are dropped (counted in debugDroppedEvents) — never an error event.
  ///
  /// Channel errors (PlatformException from the native side) are dropped too;
  /// the first one is printed once with [debugPrint] (6.12.1).
  static Stream<PencilEvent> get events {
    if (!isSupported) return const Stream<PencilEvent>.empty();
    return _events ??= const EventChannel(PencilWire.eventChannel)
        .receiveBroadcastStream()
        .handleError(_onChannelError)
        .map(_decodeCounting)
        .where((event) => event != null)
        .cast<PencilEvent>();
  }

  /// Undecodable events dropped since the last [debugReset]. Each listener
  /// decodes the native events on its own, so one bad event counts once per
  /// listener.
  @visibleForTesting
  static int get debugDroppedEvents => _dropped;

  /// Forget the cached stream and the counter.
  @visibleForTesting
  static void debugReset() {
    _events = null;
    _dropped = 0;
    _printedChannelError = false;
  }

  static Stream<PencilEvent>? _events;
  static int _dropped = 0;
  static bool _printedChannelError = false;

  static PencilEvent? _decodeCounting(Object? event) {
    final decoded = PencilWire.decode(event);
    if (decoded == null) _dropped++;
    return decoded;
  }

  static void _onChannelError(Object error) {
    if (_printedChannelError) return;
    _printedChannelError = true;
    debugPrint('pencil_bridge: event channel error dropped: $error');
  }
}
