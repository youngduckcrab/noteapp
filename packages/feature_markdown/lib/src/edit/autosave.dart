// When the editor saves (08-markdown 8.7, B-9): 700 ms after the last keystroke, and at
// least every 5 s while typing goes on. While an IME composition is open (Korean keeps
// the last syllable composing for a long time) a due save waits — at most 1 s, then it
// saves anyway, composing text included. Flushes (switch to 보기, back, app hidden) do not
// go through here: they save at once whatever the composition.
import 'dart:async';

final class AutosaveScheduler {
  AutosaveScheduler({
    required this.onDue,
    required this.isComposing,
    this.debounce = const Duration(milliseconds: 700),
    this.maxWait = const Duration(seconds: 5),
    this.composeGrace = const Duration(seconds: 1),
  });

  /// Called when a save is due.
  final void Function() onDue;
  final bool Function() isComposing;
  final Duration debounce;
  final Duration maxWait;
  final Duration composeGrace;

  static const Duration _composeStep = Duration(milliseconds: 250);

  Timer? _debounce;
  Timer? _max;
  Duration _postponed = Duration.zero;

  /// A save is scheduled.
  bool get pending => _debounce != null || _max != null;

  /// The text changed.
  void changed() {
    _debounce?.cancel();
    _debounce = Timer(debounce, _fire);
    _max ??= Timer(maxWait, _fire);
  }

  void cancel() {
    _debounce?.cancel();
    _max?.cancel();
    _debounce = null;
    _max = null;
    _postponed = Duration.zero;
  }

  void _fire() {
    if (isComposing() && _postponed < composeGrace) {
      _postponed += _composeStep;
      _debounce?.cancel();
      _debounce = Timer(_composeStep, _fire);
      return;
    }
    cancel();
    onDue();
  }

  void dispose() => cancel();
}
