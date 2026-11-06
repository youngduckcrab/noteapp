// lib/src/render/page_host.dart — INTERNAL. What gesture sessions and selections need
// from their InkPageController (implemented privately by the controller).
import 'dart:ui' show Rect;

import 'package:note_core/note_core.dart' as core;

import '../diagnostics/diagnostics.dart';
import '../diagnostics/ink_clock.dart';
import '../edit/ink_edit.dart';
import '../input/pressure_capability.dart';
import '../model/ink_stroke.dart';
import 'ink_page_content.dart';
import 'ink_page_controller.dart';
import 'laser_trail.dart';
import 'selection.dart';
import 'sessions.dart';

abstract interface class InkPageHost {
  String get pageId;
  InkCoreServices get services;
  InkClock get clock;
  InkDiagnostics get diagnostics;

  /// The stylus pressure capability now (developer display).
  PressureCapability get stylusCapability;

  /// The committed content (null before the first updateContent).
  InkPageContent? get content;

  /// True while a pending edit hides [id] (erased / deleted / split original):
  /// such strokes cannot be erased, lassoed or hit again.
  bool isPendingRemoved(String id);

  /// 6.18 spatial index: the committed strokes whose CORE bounds meet
  /// [pageRect] (closed), without the pending-removed ones; no particular order.
  List<InkStroke> strokesNear(Rect pageRect);

  /// (v2.0) The committed page objects whose CORE bounds meet [pageRect] (closed), without
  /// the pending-removed ones; z order (m5-7 T37a: candidates from the object spatial
  /// index, sorted by compareOrder).
  List<core.PageObject> objectsNear(Rect pageRect);

  /// Registers the pending display of [edit] (6.12 R6).
  void addPending(InkEdit edit);

  /// Repaints [layer] (live geometry changed; no display-state change).
  void repaint(InkRenderLayer layer);

  /// The display state changed (eraser touches, selection preview).
  void displayChanged();

  /// [session] stopped (end or cancel).
  void sessionEnded(InkGestureSession session);

  /// A lasso produced [selection]; it becomes controller.selection.
  void lassoSelected(InkSelection selection);

  /// (m5-7 T30) The page's laser trails (drawn by the overlay layer, 6.6).
  LaserTrails get laserTrails;
}
