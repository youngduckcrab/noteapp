// lib/src/tools/eyedropper_interaction.dart — 04-editor 6.6.8 (stroke
// eyedropper), 6.6.2 ①.
import 'dart:ui' show Offset;

import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../input/input_sample.dart';
import '../input/input_targets.dart';
import '../viewport/viewport_controller.dart';
import 'tool_interaction.dart';

/// The eyedropper's gesture: the pick happens at the down (pen, finger or
/// mouse — 6.6.8) and the rest of the gesture is consumed. No INK session
/// and no CORE command, so it never settles the viewport and works on a
/// read-only note (6.6.2 ①).
final class EyedropperInteraction extends ToolInteraction {
  EyedropperInteraction._({
    required super.source,
    required super.startedAt,
    required Offset start,
  }) : _last = start;

  /// Picks at [down] at once and hands the CORE colour of the stroke there
  /// (or null) to [onPicked].
  factory EyedropperInteraction.start({
    required InputSample down,
    required InteractionSource source,
    required ViewportController viewport,
    required MountedPages pages,
    required core.NoteSession session,
    required void Function(int? argb) onPicked,
  }) {
    onPicked(
      colorAt(
        down.position,
        viewport: viewport,
        pages: pages,
        session: session,
      ),
    );
    return EyedropperInteraction._(
      source: source,
      startedAt: down.timeStamp,
      start: down.position,
    );
  }

  /// Hit tolerance in screen px (6.5.8: tolerance = 6 / scale pt).
  static const double tolerancePx = 6;

  /// The colour of the topmost stroke within [tolerancePx] of [screen]:
  /// INK's hitTest finds it on the mounted, loaded page under the point, its
  /// colour is read from CORE (session.pageIfLoaded — 6.7). Null on a gap, a
  /// page that is not loaded, or when no stroke is there.
  static int? colorAt(
    Offset screen, {
    required ViewportController viewport,
    required MountedPages pages,
    required core.NoteSession session,
  }) {
    final hit = viewport.hitPage(screen);
    if (hit == null) return null;
    final mount = pages[hit.pageId];
    if (mount == null || !mount.isLoaded.value) return null;
    final scale = viewport.camera.scale;
    final found = mount.controller.hitTest(
      hit.pagePoint,
      tolerance: tolerancePx / scale,
    );
    if (found == null) return null;
    return session
        .pageIfLoaded(hit.pageId)
        ?.strokeById(found.id)
        ?.style
        .colorArgb;
  }

  Offset _last;
  double _travelled = 0;

  @override
  double get travelled => _travelled;

  @override
  void move(InputSample sample) {
    _travelled += (sample.position - _last).distance;
    _last = sample.position;
  }

  @override
  void end(InputSample sample) {}

  /// The colour was already taken at the down; nothing else to undo.
  @override
  void cancel() {}
}
