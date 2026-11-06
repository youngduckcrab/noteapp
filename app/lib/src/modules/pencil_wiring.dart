/// Injection point over the static PencilBridge (docs/plans/m5-7/
/// 01-infra.md 4.6.5, 6.12.3). FeatureWiringModule reads the pencil through
/// this port; tests hand in a fake port (no channel fakes in app tests).
library;

import 'package:pencil_bridge/pencil_bridge.dart';

// src/modules/pencil_wiring.dart — injection point over the static PencilBridge (tests fake it)
class PencilPort {
  const PencilPort();
  bool get isSupported => PencilBridge.isSupported;
  Future<PencilCapabilities> capabilities() => PencilBridge.capabilities();
  Stream<PencilEvent> get events => PencilBridge.events;
}
