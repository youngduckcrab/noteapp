// lib/src/ui/overlays/focus_flash.dart — m5-7/04-editor 6.16 (E2-19): the
// position flash after EditorScreen.initialFocusRectPt (search hits) and
// after EditorMenuContext.navigateToPage(pageId, focusRectPt).
//
// The rect (displayed page pt) is drawn in screen coordinates every frame
// from the camera, so it follows a pan or zoom. Timing (1.6 s in all):
// 0.4 s on → 0.3 s off → 0.4 s on → 0.5 s fade out. Any input meanwhile
// (a pointer down, a wheel / trackpad scroll or zoom, a key down — anywhere
// in the app) ends it at once.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';

/// Where the flash of [FocusFlashController] is in its 1.6 s.
enum FocusFlashPhase {
  /// Shown (first and second blink).
  on,

  /// Hidden between the blinks (the widget stays, at opacity 0).
  off,

  /// Fading out over [FocusFlashController.fadeDuration].
  fading,
}

/// One flash: a rect in displayed page pt of page [pageId].
@immutable
final class FocusFlashTarget {
  const FocusFlashTarget({required this.pageId, required this.rectPt});

  final String pageId;
  final Rect rectPt;

  @override
  bool operator ==(Object other) =>
      other is FocusFlashTarget &&
      other.pageId == pageId &&
      other.rectPt == rectPt;

  @override
  int get hashCode => Object.hash(pageId, rectPt);

  @override
  String toString() => 'FocusFlashTarget($pageId, $rectPt)';
}

/// The flash state of one note (editorFocusFlashProvider). [show] starts the
/// 1.6 s sequence (a running one starts over); [dismiss] ends it at once.
/// While a flash is shown, any pointer down / pointer signal / pan-zoom
/// start (a global pointer route) or key down ends it.
final class FocusFlashController extends ChangeNotifier {
  FocusFlashController();

  static const onDuration = Duration(milliseconds: 400);
  static const offDuration = Duration(milliseconds: 300);
  static const fadeDuration = Duration(milliseconds: 500);

  /// on + off + on + fade = 1.6 s.
  static const totalDuration = Duration(milliseconds: 1600);

  FocusFlashTarget? _target;
  FocusFlashPhase _phase = FocusFlashPhase.on;
  Timer? _timer;
  bool _listening = false;
  bool _disposed = false;

  /// The rect being flashed, null when none.
  FocusFlashTarget? get target => _target;

  /// Meaningful while [target] is not null.
  FocusFlashPhase get phase => _phase;

  /// Flashes [rectPt] of page [pageId] (displayed page pt).
  void show({required String pageId, required Rect rectPt}) {
    if (_disposed) return;
    _timer?.cancel();
    _target = FocusFlashTarget(pageId: pageId, rectPt: rectPt);
    _listen(true);
    _step(FocusFlashPhase.on, onDuration, () {
      _step(FocusFlashPhase.off, offDuration, () {
        _step(FocusFlashPhase.on, onDuration, () {
          _step(FocusFlashPhase.fading, fadeDuration, dismiss);
        });
      });
    });
  }

  /// Ends the flash at once (no-op without one).
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _listen(false);
    if (_target == null) return;
    _target = null;
    _phase = FocusFlashPhase.on;
    if (!_disposed) notifyListeners();
  }

  void _step(FocusFlashPhase phase, Duration duration, void Function() next) {
    _phase = phase;
    notifyListeners();
    _timer = Timer(duration, next);
  }

  void _listen(bool on) {
    if (on == _listening) return;
    _listening = on;
    if (on) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
      HardwareKeyboard.instance.addHandler(_onKey);
    } else {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerSignalEvent ||
        event is PointerPanZoomStartEvent) {
      dismiss();
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) dismiss();
    return false; // never consumes the key
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _listen(false);
    _target = null;
    _disposed = true;
    super.dispose();
  }
}

/// The flash over the page area (inside its clip, above the pages): the
/// screen rect of [FocusFlashController.target] inflated by [inflatePx],
/// rounded, tertiary 2 px border + tertiary at 20 %. Display only.
class FocusFlash extends ConsumerWidget {
  const FocusFlash({super.key});

  /// Appendix C.
  static const flashKey = ValueKey('editor.focusFlash');

  static const double inflatePx = 6;
  static const double radiusPx = 6;
  static const double borderPx = 2;
  static const double fillAlpha = 0.2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flash = ref.watch(editorFocusFlashProvider);
    final viewport = ref.watch(editorViewportProvider);
    final color = Theme.of(context).colorScheme.tertiary;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([flash, viewport]),
        builder: (context, _) {
          final target = flash.target;
          final index = target == null
              ? -1
              : viewport.pages.indexWhere((p) => p.id == target.pageId);
          if (target == null || index < 0 || !viewport.isPlaced) {
            return const SizedBox.shrink();
          }
          final r = target.rectPt;
          final rect = Rect.fromPoints(
            viewport.pageToScreen(index, r.topLeft),
            viewport.pageToScreen(index, r.bottomRight),
          ).inflate(inflatePx);
          final phase = flash.phase;
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: AnimatedOpacity(
                  opacity: phase == FocusFlashPhase.on ? 1 : 0,
                  duration: phase == FocusFlashPhase.fading
                      ? FocusFlashController.fadeDuration
                      : Duration.zero,
                  child: DecoratedBox(
                    key: flashKey,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: fillAlpha),
                      border: Border.all(color: color, width: borderPx),
                      borderRadius: BorderRadius.circular(radiusPx),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
