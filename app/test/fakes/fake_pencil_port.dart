// A PencilPort without channels (docs/plans/m5-7/01-infra.md 4.6.5 and
// 6.12.4): FeatureWiringModule tests hand it in through the module's
// constructor (S2-2 — no provider override fakes).
import 'dart:async';

import 'package:noteapp/src/modules/pencil_wiring.dart';
import 'package:pencil_bridge/pencil_bridge.dart';

final class FakePencilPort implements PencilPort {
  FakePencilPort({
    this.isSupported = true,
    Future<PencilCapabilities> Function()? capabilities,
  }) : _capabilities =
           capabilities ??
           (() async => const PencilCapabilities(os: '17.5', hover: true));

  @override
  final bool isSupported;

  final Future<PencilCapabilities> Function() _capabilities;

  /// The fake native events; broadcast like PencilBridge.events. Tests
  /// that add events close it with [close].
  final StreamController<PencilEvent> controller =
      StreamController<PencilEvent>.broadcast();

  Future<void> close() => controller.close();

  int capabilityCalls = 0;
  int eventReads = 0;

  @override
  Future<PencilCapabilities> capabilities() {
    capabilityCalls++;
    return _capabilities();
  }

  @override
  Stream<PencilEvent> get events {
    eventReads++;
    return controller.stream;
  }
}
