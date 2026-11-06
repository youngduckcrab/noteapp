import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// Route paths of the app shell (docs/plans/01-infra.md 4.5.5, 6.6; 2차
/// docs/plans/m5-7/01-infra.md 4.6.6, 6.8).
///
/// Feature screens never see these paths: the shell turns their callbacks
/// into navigation (D5).
abstract final class AppRoutes {
  static const String library = '/';
  static const String folderPattern = '/folders/:folderId';
  static const String notePattern = '/notes/:noteId';
  static const String settings = '/settings';
  static const String pageQueryKey = 'page';
  static const String focusQueryKey = 'focus';

  /// Shared page key of `/` and `/folders/:folderId`: the Navigator keeps ONE
  /// library route, so folder changes update LibraryScreen instead of
  /// recreating it (6.6).
  static const ValueKey<String> libraryPageKey = ValueKey<String>('library');

  /// `/folders/<encoded id>`
  static String folder(String folderId) =>
      '/folders/${Uri.encodeComponent(folderId)}';

  /// `'/notes/<id>' [+ '?page=<pageId>' [+ '&focus=' + FocusRectCodec.encode(focus)]]`.
  /// focus without pageId is ignored (asserted in debug).
  ///
  /// A [focus] that [FocusRectCodec.decode] would not read back (not finite,
  /// `left > right`, `top > bottom`, a value beyond ±100000 pt) is left out
  /// too, so every address this returns opens (6.8).
  static String note(String noteId, {String? pageId, Rect? focus}) {
    assert(
      focus == null || pageId != null,
      'AppRoutes.note: focus needs a pageId (S2-6)',
    );
    final path = '/notes/${Uri.encodeComponent(noteId)}';
    if (pageId == null) return path;
    final page = '$path?$pageQueryKey=${Uri.encodeQueryComponent(pageId)}';
    if (focus == null || !FocusRectCodec.canEncode(focus)) return page;
    return '$page&$focusQueryKey=${FocusRectCodec.encode(focus)}';
  }
}

/// The `focus` query value `l,t,r,b` in page pt (6.8, S2-6).
abstract final class FocusRectCodec {
  /// The largest absolute coordinate [decode] accepts (pt).
  static const double maxAbs = 100000;

  /// 'l,t,r,b' — each value rounded to 0.1 pt, no trailing '.0', commas NOT percent-encoded.
  ///
  /// Throws [ArgumentError] for a rect that is not finite; use [canEncode]
  /// first when the rect comes from outside.
  static String encode(Rect rect) {
    if (!rect.isFinite) {
      throw ArgumentError.value(rect, 'rect', 'must be finite');
    }
    return [
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
    ].map(_formatTenths).join(',');
  }

  /// null unless exactly 4 comma-separated finite numbers with l ≤ r, t ≤ b, |v| ≤ 100000.
  /// Accepts '%2C' too (go_router already decodes query values).
  ///
  /// A number is an optional '-', digits and an optional '.digits' (what
  /// [encode] writes; no exponent, sign '+' or spaces).
  static Rect? decode(String? value) {
    if (value == null) return null;
    final parts = value.replaceAll(_encodedComma, ',').split(',');
    if (parts.length != 4) return null;
    final numbers = <double>[];
    for (final part in parts) {
      if (!_number.hasMatch(part)) return null;
      final n = double.tryParse(part);
      if (n == null || !n.isFinite || n.abs() > maxAbs) return null;
      numbers.add(n);
    }
    final [l, t, r, b] = numbers;
    if (l > r || t > b) return null;
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Whether `decode(encode(rect))` gives a rect (after rounding to 0.1 pt).
  static bool canEncode(Rect rect) =>
      rect.isFinite && decode(encode(rect)) != null;

  static final RegExp _encodedComma = RegExp('%2C', caseSensitive: false);
  static final RegExp _number = RegExp(r'^-?\d+(\.\d+)?$');

  static String _formatTenths(double value) {
    final tenths = (value * 10).round();
    if (tenths % 10 == 0) return '${tenths ~/ 10}';
    final sign = tenths < 0 ? '-' : '';
    final abs = tenths.abs();
    return '$sign${abs ~/ 10}.${abs % 10}';
  }
}

/// Arguments of the library routes `/` and `/folders/:folderId`.
@immutable
final class LibraryRouteArgs {
  const LibraryRouteArgs({this.folderId});
  final String? folderId; // null = root

  @override
  bool operator ==(Object other) =>
      other is LibraryRouteArgs && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;

  @override
  String toString() => 'LibraryRouteArgs(folderId: $folderId)';
}

/// Arguments of the editor route
/// `/notes/:noteId?page=<pageId>&focus=<l>,<t>,<r>,<b>` (S2-6).
@immutable
final class EditorRouteArgs {
  const EditorRouteArgs({
    required this.noteId,
    this.initialPageId,
    this.initialFocusRectPt,
  }) : assert(
         initialPageId != null || initialFocusRectPt == null,
         'initialFocusRectPt needs initialPageId',
       );
  final String noteId;
  final String? initialPageId;

  /// Page pt; null when [initialPageId] is null.
  final Rect? initialFocusRectPt;

  @override
  bool operator ==(Object other) =>
      other is EditorRouteArgs &&
      other.noteId == noteId &&
      other.initialPageId == initialPageId &&
      other.initialFocusRectPt == initialFocusRectPt;

  @override
  int get hashCode => Object.hash(noteId, initialPageId, initialFocusRectPt);

  @override
  String toString() =>
      'EditorRouteArgs(noteId: $noteId, initialPageId: $initialPageId, '
      'initialFocusRectPt: $initialFocusRectPt)';
}
