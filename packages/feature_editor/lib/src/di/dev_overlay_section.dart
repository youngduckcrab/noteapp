// lib/src/di/dev_overlay_section.dart — contract 00-overview 7.2.17,
// 04-editor 4.5.
//
// The developer overlay (04-editor 6.12) subscribes to each section's lines
// only while it is visible; sections are drawn in list order after the
// EDITOR / INK / CORE blocks.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class DevOverlaySection {
  const DevOverlaySection({
    required this.id,
    required this.title,
    required this.lines,
  });
  final String id;
  final String title;
  final ValueListenable<List<String>> lines; // short text lines, updated ≤ 4 Hz

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevOverlaySection &&
          other.id == id &&
          other.title == title &&
          other.lines == lines;

  @override
  int get hashCode => Object.hash(id, title, lines);

  @override
  String toString() => 'DevOverlaySection($id, "$title")';
}

/// Extra developer-overlay blocks from other areas (INFRA wires PDF render stats).
final devOverlaySectionsProvider = Provider<List<DevOverlaySection>>(
  (ref) => const [],
  name: 'devOverlaySectionsProvider',
);
