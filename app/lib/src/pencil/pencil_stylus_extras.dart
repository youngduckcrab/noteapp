/// The app adapter from pencil_bridge to the editor's stylus extras slot
/// (X35 — docs/plans/m5-7/01-infra.md 4.6.5, 6.12.3; contract 00-overview
/// 7.2.10 v2.1 and 7.2.13): string → enum mapping, capabilities read once.
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:pencil_bridge/pencil_bridge.dart';

/// `stylusExtrasProvider` on iOS (contract 7.3.3 row, FeatureWiringModule).
final class PencilStylusExtrasSource implements StylusExtrasSource {
  /// [capabilities] is the value FeatureWiringModule read once at app start (계약 7.2.10 v2.1).
  PencilStylusExtrasSource({
    required PencilCapabilities capabilities,
    required Stream<PencilEvent> events,
  }) : capabilities = stylusCapabilitiesOf(capabilities),
       events = events
           .map(stylusEventOf)
           .where((e) => e != null)
           .cast<StylusExtraEvent>();

  @override
  bool get isSupported => true;

  /// stylusCapabilitiesOf(capabilities), fixed for the run.
  @override
  final StylusCapabilities capabilities;

  /// events.map(stylusEventOf).where(non-null) — broadcast (the source is), no asBroadcastStream;
  /// every event carries timestamp: PencilEvent.timestamp (CP-E6).
  @override
  final Stream<StylusExtraEvent> events;
}

/// 6.12.3 table: doubleTap is always true on iOS (UIKit does not say whether
/// the connected pencil can double tap); the other flags are copied as they
/// are — `squeeze` / `roll` are OS availability, not the pencil model
/// (CD2-24).
StylusCapabilities stylusCapabilitiesOf(PencilCapabilities c) =>
    StylusCapabilities(
      doubleTap: true,
      squeeze: c.squeeze,
      barrelRoll: c.roll,
      hoverPose: c.hover,
      prefersPencilOnlyDrawing: c.prefersPencilOnlyDrawing,
    );

/// Used when the capabilities call failed on iOS: os '?', everything false (→ only doubleTap true).
const PencilCapabilities kPencilFallbackCapabilities = PencilCapabilities(
  os: '?',
);

/// null = dropped (unknown phase). Every event keeps its timestamp (CP-E6);
/// tap / squeeze `z` has no place in the contract types and is dropped.
StylusExtraEvent? stylusEventOf(PencilEvent event) => switch (event) {
  PencilTap() => StylusDoubleTap(
    preferredAction: stylusPreferredActionOf(event.preferredAction),
    hoverPosition: event.position,
    timestamp: event.timestamp,
  ),
  PencilSqueeze() => switch (stylusSqueezePhaseOf(event.phase)) {
    null => null,
    final phase => StylusSqueeze(
      phase: phase,
      preferredAction: stylusPreferredActionOf(event.preferredAction),
      hoverPosition: event.position,
      timestamp: event.timestamp,
    ),
  },
  PencilHover() => StylusHoverPose(
    position: event.position,
    height: event.z,
    altitude: event.altitude,
    azimuth: event.azimuth,
    roll: event.roll,
    timestamp: event.timestamp,
  ),
  PencilRoll() => StylusBarrelRoll(event.angle, timestamp: event.timestamp),
};

/// unknown string → unknown
StylusPreferredAction stylusPreferredActionOf(String wire) {
  for (final action in StylusPreferredAction.values) {
    if (action.name == wire) return action;
  }
  return StylusPreferredAction.unknown;
}

/// unknown string → null
StylusSqueezePhase? stylusSqueezePhaseOf(String wire) {
  for (final phase in StylusSqueezePhase.values) {
    if (phase.name == wire) return phase;
  }
  return null;
}
