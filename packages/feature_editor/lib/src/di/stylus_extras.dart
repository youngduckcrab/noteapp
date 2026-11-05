// lib/src/di/stylus_extras.dart — contract 00-overview 7.2.17 ('StylusExtrasSource
// / stylusExtrasProvider — EDITOR 4.7 (unchanged, default NoStylusExtras)'),
// 04-editor 4.7.
//
// Native-only pencil events enter the editor through this interface only
// (04-editor 6.16). Nothing subscribes to it in this scope.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

sealed class StylusExtraEvent {
  const StylusExtraEvent();
}

/// Apple Pencil (2nd gen / Pro) double tap.
final class StylusDoubleTap extends StylusExtraEvent {
  const StylusDoubleTap();
}

/// Apple Pencil Pro squeeze; [hoverPosition] in global logical px if hovering.
final class StylusSqueeze extends StylusExtraEvent {
  const StylusSqueeze({this.hoverPosition});
  final Offset? hoverPosition;
}

/// Apple Pencil Pro barrel roll angle (radians).
final class StylusBarrelRoll extends StylusExtraEvent {
  const StylusBarrelRoll(this.angle);
  final double angle;
}

abstract interface class StylusExtrasSource {
  bool get isSupported;
  Stream<StylusExtraEvent> get events;
}

/// Web / unsupported platforms.
class NoStylusExtras implements StylusExtrasSource {
  const NoStylusExtras();
  @override
  bool get isSupported => false;
  @override
  Stream<StylusExtraEvent> get events => const Stream<StylusExtraEvent>.empty();
}

/// Native-only pencil events (squeeze, double tap, barrel roll).
/// Default: unsupported (web). Consumed from M5; not overridden in this scope.
final stylusExtrasProvider = Provider<StylusExtrasSource>(
  (ref) => const NoStylusExtras(),
  name: 'stylusExtrasProvider',
);
