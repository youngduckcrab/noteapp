// Undo / redo of the source editor with a cap (08-markdown 8.7 U4, MD-T19). Flutter's own
// UndoHistory keeps every 500 ms state of the field for the whole session, and each state
// is a full copy of the text: on a 150,000-character document an hour of typing would hold
// gigabytes. This history keeps at most [maxEntries] states and [maxUnits] UTF-16 units in
// all (the oldest go first), groups typing within [groupFor] into one step, and treats
// programmatic changes (task toggles, restores) as one step each.
//
// A change that came from outside (another device's text) is NOT a step: [reset] drops
// the history, so an undo can never write back the text from before it and overwrite the
// other device's text silently (review A2).
import 'dart:async';

import 'package:flutter/widgets.dart';

class BoundedUndoHistory extends ValueNotifier<UndoHistoryValue> {
  BoundedUndoHistory({
    this.maxEntries = 200,
    this.maxUnits = 4000000,
    this.groupFor = const Duration(milliseconds: 500),
  }) : super(UndoHistoryValue.empty);

  /// States kept at most (the current one included).
  final int maxEntries;

  /// UTF-16 units of all kept states together at most (the current one is always kept).
  final int maxUnits;

  /// Typing within this time of a step's start joins that step (a timer, so fake time
  /// in tests works).
  final Duration groupFor;

  final List<TextEditingValue> _states = [];
  int _index = -1;
  int _units = 0;
  bool _sealed = true;
  Timer? _group;

  /// States held now (tests).
  int get length => _states.length;

  /// UTF-16 units held now (tests).
  int get units => _units;

  bool get canUndo => _index > 0;
  bool get canRedo => _index >= 0 && _index < _states.length - 1;

  /// Forgets everything; [current] is the only state.
  void reset(TextEditingValue current) {
    _states
      ..clear()
      ..add(current);
    _index = 0;
    _units = current.text.length;
    _seal();
    _publish();
  }

  void _seal() {
    _sealed = true;
    _group?.cancel();
    _group = null;
  }

  /// The text changed (typing or a programmatic edit). [single]: this change is a step
  /// of its own (the next typing starts a new step too).
  void record(TextEditingValue v, {bool single = false}) {
    if (_index < 0) {
      reset(v);
      return;
    }
    if (_states[_index].text == v.text) {
      _states[_index] = v;
      return;
    }
    _dropRedo();
    final joins = !single && !_sealed && _index > 0;
    if (joins) {
      _units += v.text.length - _states[_index].text.length;
      _states[_index] = v;
    } else {
      _states.add(v);
      _index = _states.length - 1;
      _units += v.text.length;
      _seal();
      if (!single) {
        _sealed = false;
        _group = Timer(groupFor, _seal);
      }
    }
    _trim();
    _publish();
  }

  /// The state one step back, or null. The caller puts it in the field (and must not
  /// [record] it).
  TextEditingValue? undo() {
    if (!canUndo) return null;
    _index--;
    _seal();
    _publish();
    return _states[_index];
  }

  /// The state one step forward, or null.
  TextEditingValue? redo() {
    if (!canRedo) return null;
    _index++;
    _seal();
    _publish();
    return _states[_index];
  }

  void _dropRedo() {
    while (_states.length - 1 > _index) {
      _units -= _states.removeLast().text.length;
    }
  }

  void _trim() {
    while (_states.length > 1 &&
        (_states.length > maxEntries || _units > maxUnits)) {
      _units -= _states.removeAt(0).text.length;
      _index--;
    }
  }

  void _publish() =>
      value = UndoHistoryValue(canUndo: canUndo, canRedo: canRedo);

  @override
  void dispose() {
    _group?.cancel();
    super.dispose();
  }
}
