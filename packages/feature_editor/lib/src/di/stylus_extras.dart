// lib/src/di/stylus_extras.dart — contract 00-overview 7.2.17 (v1.4) and
// 2nd-round contract m5-7/00-overview 7.2.10 ('stylus extras: 깨짐(구독자
// 없음) / 추가'), m5-7/04-editor 4.2, 4.3.4.
//
// Native-only pencil events enter the editor through this interface only.
// INFRA's PencilStylusExtrasSource (pencil_bridge) overrides
// stylusExtrasProvider on iPad (contract 7.3.3). R2-B5 (foundation): the v2
// types. E2-18: StylusExtrasListener (stylus/stylus_extras_listener.dart)
// subscribes while the note's page viewport is on screen (6.5).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// (v2.1, CP-E6) base class gains an optional event time; subclasses pass
/// super.timestamp. iOS: same base as PencilEvent.timestamp (systemUptime);
/// null when the source has none.
///
/// Every subtype compares all its fields, [timestamp] included
/// (04-editor 4.3.4).
@immutable
sealed class StylusExtraEvent {
  const StylusExtraEvent({this.timestamp});
  final Duration? timestamp;
}

enum StylusPreferredAction {
  ignore,
  switchEraser,
  switchPrevious,
  showColorPalette,
  showInkAttributes,
  showContextualPalette,
  runSystemShortcut,
  unknown,
}

enum StylusSqueezePhase { began, changed, ended, cancelled }

/// Apple Pencil (2nd gen / Pro) double tap.
final class StylusDoubleTap extends StylusExtraEvent {
  const StylusDoubleTap({
    this.preferredAction = StylusPreferredAction.unknown,
    this.hoverPosition,
    super.timestamp,
  });
  final StylusPreferredAction preferredAction;
  final Offset? hoverPosition; // global logical px

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StylusDoubleTap &&
          other.preferredAction == preferredAction &&
          other.hoverPosition == hoverPosition &&
          other.timestamp == timestamp;

  @override
  int get hashCode =>
      Object.hash(StylusDoubleTap, preferredAction, hoverPosition, timestamp);

  @override
  String toString() =>
      'StylusDoubleTap(${preferredAction.name}, hover: $hoverPosition, '
      'at: $timestamp)';
}

/// Apple Pencil Pro squeeze; [hoverPosition] in global logical px if hovering.
final class StylusSqueeze extends StylusExtraEvent {
  const StylusSqueeze({
    this.phase = StylusSqueezePhase.ended,
    this.preferredAction = StylusPreferredAction.unknown,
    this.hoverPosition,
    super.timestamp,
  });
  final StylusSqueezePhase phase;
  final StylusPreferredAction preferredAction;
  final Offset? hoverPosition;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StylusSqueeze &&
          other.phase == phase &&
          other.preferredAction == preferredAction &&
          other.hoverPosition == hoverPosition &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    StylusSqueeze,
    phase,
    preferredAction,
    hoverPosition,
    timestamp,
  );

  @override
  String toString() =>
      'StylusSqueeze(${phase.name}, ${preferredAction.name}, '
      'hover: $hoverPosition, at: $timestamp)';
}

/// Apple Pencil Pro barrel roll angle (radians). v1.4.
final class StylusBarrelRoll extends StylusExtraEvent {
  const StylusBarrelRoll(this.angle, {super.timestamp});
  final double angle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StylusBarrelRoll &&
          other.angle == angle &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(StylusBarrelRoll, angle, timestamp);

  @override
  String toString() => 'StylusBarrelRoll($angle, at: $timestamp)';
}

/// The pencil's pose while it hovers (iPad, v2.0).
final class StylusHoverPose extends StylusExtraEvent {
  const StylusHoverPose({
    required this.position,
    this.height,
    this.altitude,
    this.azimuth,
    this.roll,
    super.timestamp,
  });
  final Offset position; // global logical px
  final double? height; // 0..1 (UIKit zOffset)
  final double? altitude, azimuth, roll; // rad

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StylusHoverPose &&
          other.position == position &&
          other.height == height &&
          other.altitude == altitude &&
          other.azimuth == azimuth &&
          other.roll == roll &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    StylusHoverPose,
    position,
    height,
    altitude,
    azimuth,
    roll,
    timestamp,
  );

  @override
  String toString() =>
      'StylusHoverPose($position, height: $height, altitude: $altitude, '
      'azimuth: $azimuth, roll: $roll, at: $timestamp)';
}

/// (v2.1) `squeeze` and `barrelRoll` are OS availability (iPadOS 17.5+), not
/// the kind of pencil: the editor shows those settings only after the first
/// squeeze / roll event on the device (contract 7.2.10).
@immutable
class StylusCapabilities {
  const StylusCapabilities({
    this.doubleTap = false,
    this.squeeze = false,
    this.barrelRoll = false,
    this.hoverPose = false,
    this.prefersPencilOnlyDrawing = false,
  });
  final bool doubleTap,
      squeeze,
      barrelRoll,
      hoverPose,
      prefersPencilOnlyDrawing;
  static const StylusCapabilities none = StylusCapabilities();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StylusCapabilities &&
          other.doubleTap == doubleTap &&
          other.squeeze == squeeze &&
          other.barrelRoll == barrelRoll &&
          other.hoverPose == hoverPose &&
          other.prefersPencilOnlyDrawing == prefersPencilOnlyDrawing;

  @override
  int get hashCode => Object.hash(
    doubleTap,
    squeeze,
    barrelRoll,
    hoverPose,
    prefersPencilOnlyDrawing,
  );

  @override
  String toString() =>
      'StylusCapabilities(doubleTap: $doubleTap, squeeze: $squeeze, '
      'barrelRoll: $barrelRoll, hoverPose: $hoverPose, '
      'pencilOnly: $prefersPencilOnlyDrawing)';
}

abstract interface class StylusExtrasSource {
  bool get isSupported; // v1.4
  /// (v2.0) read once at app start — (v2.1) a change in iPadOS settings
  /// applies on the next app start.
  StylusCapabilities get capabilities;
  Stream<StylusExtraEvent> get events; // v1.4
}

/// Web / unsupported platforms.
class NoStylusExtras implements StylusExtrasSource {
  const NoStylusExtras();
  @override
  bool get isSupported => false; // v1.4
  @override
  StylusCapabilities get capabilities => StylusCapabilities.none; // (v2.0)
  @override
  Stream<StylusExtraEvent> get events => const Stream<StylusExtraEvent>.empty();
}

/// Native-only pencil events (squeeze, double tap, barrel roll, hover pose).
/// Default: unsupported (web). INFRA overrides it on iPad (contract 7.3.3);
/// consumed by StylusExtrasListener (E2-18).
final stylusExtrasProvider = Provider<StylusExtrasSource>(
  (ref) => const NoStylusExtras(),
  name: 'stylusExtrasProvider',
);
