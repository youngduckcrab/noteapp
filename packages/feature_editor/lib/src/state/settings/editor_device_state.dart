// lib/src/state/settings/editor_device_state.dart — m5-7/04-editor 4.3.3,
// 6.11.6, 6.18, 6.20 (E2-01).
//
// EDITOR-internal per-device values, NOT exported: the web text input mode
// (developer menu), the shape-sample toggle (developer menu, P-B) and whether
// this device has seen a Pencil squeeze / barrel roll (the settings rows show
// only after that — contract 7.2.10 (v2.1), CD2-24), and (v2 — 04-editor 17)
// the editor chrome: the hidden top menu, the detached pen palette and where
// their floating buttons sit. Stored under the device
// key editor.deviceState, written 500 ms after a change like
// EditorSettingsNotifier.
import 'dart:async';

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../debounced_writer.dart';
import 'editor_setting_keys.dart';

/// 6.11.6. Native is always inline; textarea is the P-C fallback B (E2-11).
enum WebTextInputMode { inline, sheet, textarea }

@immutable
class EditorDeviceState {
  const EditorDeviceState({
    this.webTextInput = WebTextInputMode.inline,
    this.collectShapeSamples = false,
    this.seenSqueeze = false,
    this.seenBarrelRoll = false,
    this.toolbarHidden = false,
    this.seenToolbarHideHint = false,
    this.paletteDetached = false,
    this.palettePosition = defaultPalettePosition,
    this.restorePillX = defaultRestorePillX,
  });

  /// (04-editor 17) Where the palette button starts: left edge, a quarter
  /// down (fractions of the free room — see [palettePosition]).
  static const Offset defaultPalettePosition = Offset(0, 0.25);

  /// (04-editor 17) The restore pill starts centred.
  static const double defaultRestorePillX = 0.5;

  /// Developer menu, web only (6.11.6).
  final WebTextInputMode webTextInput;

  /// Developer toggle '도형 표본 모으기' (6.20, U18) — default off.
  final bool collectShapeSamples;

  /// A squeeze / barrel roll event arrived on this device (6.5.1, CD2-24).
  final bool seenSqueeze, seenBarrelRoll;

  /// (04-editor 17) '메뉴 숨기기': the toolbar and the preset row are hidden.
  final bool toolbarHidden;

  /// (04-editor 17) The first-hide hint snack bar has been shown.
  final bool seenToolbarHideHint;

  /// (04-editor 17) '팔레트로 떼어내기': the preset row is a floating palette.
  final bool paletteDetached;

  /// (04-editor 17) The palette button's top-left as fractions (0–1) of the
  /// room it can move in, so it stays inside after a rotation or resize.
  final Offset palettePosition;

  /// (04-editor 17) The restore pill's left as a fraction (0–1) of the room
  /// along the top edge.
  final double restorePillX;

  EditorDeviceState copyWith({
    WebTextInputMode? webTextInput,
    bool? collectShapeSamples,
    bool? seenSqueeze,
    bool? seenBarrelRoll,
    bool? toolbarHidden,
    bool? seenToolbarHideHint,
    bool? paletteDetached,
    Offset? palettePosition,
    double? restorePillX,
  }) => EditorDeviceState(
    webTextInput: webTextInput ?? this.webTextInput,
    collectShapeSamples: collectShapeSamples ?? this.collectShapeSamples,
    seenSqueeze: seenSqueeze ?? this.seenSqueeze,
    seenBarrelRoll: seenBarrelRoll ?? this.seenBarrelRoll,
    toolbarHidden: toolbarHidden ?? this.toolbarHidden,
    seenToolbarHideHint: seenToolbarHideHint ?? this.seenToolbarHideHint,
    paletteDetached: paletteDetached ?? this.paletteDetached,
    palettePosition: palettePosition ?? this.palettePosition,
    restorePillX: restorePillX ?? this.restorePillX,
  );

  /// {"v":2,"webTextInput":"inline","collectShapeSamples":false,
  ///  "seenSqueeze":false,"seenBarrelRoll":false,"toolbarHidden":false,
  ///  "seenToolbarHideHint":false,"paletteDetached":false,
  ///  "palettePosition":{"x":0.0,"y":0.25},"restorePillX":0.5}
  /// (v1 had no chrome fields — they decode as the defaults.)
  Map<String, Object?> toJson() => {
    'v': 2,
    'webTextInput': webTextInput.name,
    'collectShapeSamples': collectShapeSamples,
    'seenSqueeze': seenSqueeze,
    'seenBarrelRoll': seenBarrelRoll,
    'toolbarHidden': toolbarHidden,
    'seenToolbarHideHint': seenToolbarHideHint,
    'paletteDetached': paletteDetached,
    'palettePosition': {'x': palettePosition.dx, 'y': palettePosition.dy},
    'restorePillX': restorePillX,
  };

  /// Unknown / wrong-typed values → defaults, no report (values a newer app
  /// wrote, 1st-round rule).
  factory EditorDeviceState.fromJson(Map<String, Object?> json) {
    const d = EditorDeviceState();
    bool flag(String key, bool fallback) => switch (json[key]) {
      final bool b => b,
      _ => fallback,
    };
    // A fraction 0–1 (finite); anything else → the fallback.
    double? fraction(Object? v) => switch (v) {
      final num n when n.isFinite => n.toDouble().clamp(0.0, 1.0),
      _ => null,
    };
    final position = switch (json['palettePosition']) {
      final Map<Object?, Object?> m
          when fraction(m['x']) != null && fraction(m['y']) != null =>
        Offset(fraction(m['x'])!, fraction(m['y'])!),
      _ => d.palettePosition,
    };
    final mode = json['webTextInput'];
    return EditorDeviceState(
      webTextInput: WebTextInputMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => d.webTextInput,
      ),
      collectShapeSamples: flag('collectShapeSamples', d.collectShapeSamples),
      seenSqueeze: flag('seenSqueeze', d.seenSqueeze),
      seenBarrelRoll: flag('seenBarrelRoll', d.seenBarrelRoll),
      toolbarHidden: flag('toolbarHidden', d.toolbarHidden),
      seenToolbarHideHint: flag('seenToolbarHideHint', d.seenToolbarHideHint),
      paletteDetached: flag('paletteDetached', d.paletteDetached),
      palettePosition: position,
      restorePillX: fraction(json['restorePillX']) ?? d.restorePillX,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorDeviceState &&
          other.webTextInput == webTextInput &&
          other.collectShapeSamples == collectShapeSamples &&
          other.seenSqueeze == seenSqueeze &&
          other.seenBarrelRoll == seenBarrelRoll &&
          other.toolbarHidden == toolbarHidden &&
          other.seenToolbarHideHint == seenToolbarHideHint &&
          other.paletteDetached == paletteDetached &&
          other.palettePosition == palettePosition &&
          other.restorePillX == restorePillX;

  @override
  int get hashCode => Object.hash(
    webTextInput,
    collectShapeSamples,
    seenSqueeze,
    seenBarrelRoll,
    toolbarHidden,
    seenToolbarHideHint,
    paletteDetached,
    palettePosition,
    restorePillX,
  );

  @override
  String toString() =>
      'EditorDeviceState(${webTextInput.name}, samples: $collectShapeSamples, '
      'squeeze: $seenSqueeze, roll: $seenBarrelRoll, '
      'toolbarHidden: $toolbarHidden, palette: '
      '${paletteDetached ? 'detached at $palettePosition' : 'docked'}, '
      'pill: $restorePillX)';
}

/// Debounce of editor.deviceState (same as the settings keys — 6.18).
const Duration _writeDelay = Duration(milliseconds: 500);

/// Root (all notes). build() returns the defaults synchronously, then loads
/// the stored value; a setter that runs before the load completes wins.
class EditorDeviceStateNotifier extends Notifier<EditorDeviceState> {
  late DebouncedSettingWriter _writer;
  int _generation = 0;
  bool _loaded = false;

  @override
  EditorDeviceState build() {
    final settings = ref.watch(core.settingsRepositoryProvider);
    final generation = ++_generation;
    _loaded = false;
    final writer = _writer = DebouncedSettingWriter(
      settings: settings,
      key: EditorSettingKeys.deviceState,
      delay: _writeDelay,
    );
    ref.onDispose(() {
      _generation++;
      writer.dispose();
    });
    unawaited(_load(settings, generation));
    return const EditorDeviceState();
  }

  /// True after the stored value has been read (or found absent).
  bool get isLoaded => _loaded;

  Future<void> _load(core.SettingsRepository settings, int generation) async {
    Map<String, Object?> json = const {};
    try {
      json = await settings.get(EditorSettingKeys.deviceState);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while loading the editor device state'),
        ),
      );
    }
    if (generation != _generation) return;
    _loaded = true;
    if (_writer.isPending) return; // a local change wins
    state = EditorDeviceState.fromJson(json);
  }

  void _update(EditorDeviceState next) {
    if (next == state) return;
    state = next;
    final json = next.toJson();
    _writer.schedule(() => json);
  }

  void setWebTextInput(WebTextInputMode mode) =>
      _update(state.copyWith(webTextInput: mode));

  void setCollectShapeSamples(bool on) =>
      _update(state.copyWith(collectShapeSamples: on));

  /// The first squeeze on this device (6.5.1): later ones change nothing.
  void markSeenSqueeze() => _update(state.copyWith(seenSqueeze: true));

  /// The first barrel roll on this device (6.5.1).
  void markSeenBarrelRoll() => _update(state.copyWith(seenBarrelRoll: true));

  /// (04-editor 17) '메뉴 숨기기' / show the menu again.
  void setToolbarHidden(bool hidden) =>
      _update(state.copyWith(toolbarHidden: hidden));

  /// (04-editor 17) The first-hide hint has been shown.
  void markSeenToolbarHideHint() =>
      _update(state.copyWith(seenToolbarHideHint: true));

  /// (04-editor 17) Detach the preset row as a palette / dock it again.
  void setPaletteDetached(bool detached) =>
      _update(state.copyWith(paletteDetached: detached));

  /// (04-editor 17) Fractions 0–1 (clamped).
  void setPalettePosition(Offset fractions) => _update(
    state.copyWith(
      palettePosition: Offset(
        fractions.dx.clamp(0.0, 1.0),
        fractions.dy.clamp(0.0, 1.0),
      ),
    ),
  );

  /// (04-editor 17) A fraction 0–1 (clamped).
  void setRestorePillX(double fraction) =>
      _update(state.copyWith(restorePillX: fraction.clamp(0.0, 1.0)));

  /// Writes a pending change now (tests, leaving the screen).
  Future<void> flush() => _writer.flush();
}

final editorDeviceStateProvider =
    NotifierProvider<EditorDeviceStateNotifier, EditorDeviceState>(
      EditorDeviceStateNotifier.new,
      name: 'editorDeviceStateProvider',
    );
