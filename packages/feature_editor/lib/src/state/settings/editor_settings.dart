// lib/src/state/settings/editor_settings.dart — contract 00-overview 7.2.17
// ('EditorSettings / InputMode / PageFlipMode / PalmRejectionSettings /
// GestureSettings — EDITOR 4.8, with `final ink.PressureMode pressureMode`'),
// 04-editor 4.8; stored form 04-editor 6.14, contract 7.4.6. 2nd round:
// GestureSettings v2 (m5-7/00-overview 7.2.10, m5-7/04-editor 4.3.2) and the
// three EditorSettings fields of m5-7/04-editor 4.3.3 (stored form 6.18).
//
// Pure value types. The JSON helpers are the stored form of the two CORE
// setting keys 'editor.settings.device' and 'editor.settings.synced'; loading
// and saving them is EditorSettingsNotifier's job (task E-06).
import 'package:collection/collection.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

/// How touch input is interpreted.
enum InputMode {
  /// Fingers draw until a stylus is seen in this app (then behaves like
  /// [penOnly]). Default: works on first launch with a finger or a mouse.
  auto,

  /// Stylus draws; fingers only scroll/zoom/gesture.
  penOnly,

  /// One finger draws with the current tool; two or more fingers navigate.
  fingerDrawing,
}

enum PageFlipMode { verticalScroll, horizontalPaged }

// Valid ranges of the stored palm-rejection values (04-editor 4.8). A stored
// value outside its range decodes to the default (04-editor 6.14).
const int _penCooldownMaxMs = 1500;
const double _touchRadiusMin = 20;
const double _touchRadiusMax = 120;

@immutable
class PalmRejectionSettings {
  const PalmRejectionSettings({
    this.penCooldown = const Duration(milliseconds: 400),
    this.treatHoverAsPenActivity = true,
    this.maxTouchRadius = 45.0,
  });

  /// Touches that START within this time after the last stylus activity are
  /// rejected. Range 0–1500 ms, step 50 ms.
  final Duration penCooldown;

  /// Stylus hover events count as stylus activity (pen near the screen).
  final bool treatHoverAsPenActivity;

  /// Touches whose reported radiusMajor (logical px) exceeds this are
  /// rejected. Ignored when the platform reports 0 (web). Range 20–120.
  final double maxTouchRadius;

  PalmRejectionSettings copyWith({
    Duration? penCooldown,
    bool? treatHoverAsPenActivity,
    double? maxTouchRadius,
  }) => PalmRejectionSettings(
    penCooldown: penCooldown ?? this.penCooldown,
    treatHoverAsPenActivity:
        treatHoverAsPenActivity ?? this.treatHoverAsPenActivity,
    maxTouchRadius: maxTouchRadius ?? this.maxTouchRadius,
  );

  /// `{"cooldownMs":400,"hover":true,"maxRadius":45.0}` (04-editor 6.14).
  Map<String, Object?> toJson() => {
    'cooldownMs': penCooldown.inMilliseconds,
    'hover': treatHoverAsPenActivity,
    'maxRadius': maxTouchRadius,
  };

  /// Unknown keys ignored; a missing, mistyped or out-of-range field takes
  /// its default. Number fields accept ints and doubles (contract 7.4.6).
  factory PalmRejectionSettings.fromJson(Map<String, Object?> json) {
    const defaults = PalmRejectionSettings();
    final cooldownMs = _numIn(json['cooldownMs'], 0, _penCooldownMaxMs);
    return PalmRejectionSettings(
      penCooldown: cooldownMs == null
          ? defaults.penCooldown
          : Duration(milliseconds: cooldownMs.round()),
      treatHoverAsPenActivity: _boolOr(
        json['hover'],
        defaults.treatHoverAsPenActivity,
      ),
      maxTouchRadius:
          _numIn(
            json['maxRadius'],
            _touchRadiusMin,
            _touchRadiusMax,
          )?.toDouble() ??
          defaults.maxTouchRadius,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PalmRejectionSettings &&
          other.penCooldown == penCooldown &&
          other.treatHoverAsPenActivity == treatHoverAsPenActivity &&
          other.maxTouchRadius == maxTouchRadius;

  @override
  int get hashCode =>
      Object.hash(penCooldown, treatHoverAsPenActivity, maxTouchRadius);

  @override
  String toString() =>
      'PalmRejectionSettings(cooldown: ${penCooldown.inMilliseconds} ms, '
      'hover: $treatHoverAsPenActivity, maxRadius: $maxTouchRadius)';
}

// --- gestures: 추가 (v1.4 bool keys kept for reading / writing compatibility) ---
// 2nd-round contract m5-7/00-overview 7.2.10; EDITOR details m5-7/04-editor
// 4.3.2. R2-B5 (foundation): the model and its JSON. The input router still
// reads the three v1.4 bools (they follow the actions — withAction); the
// actions take effect from E2-04b / E2-05.
enum EditorGesture {
  twoFingerTap,
  threeFingerTap,
  fingerLongPress,
  penButton,
  invertedStylus,
  pencilDoubleTap,
  pencilSqueeze,
}

enum EditorAction {
  none,
  undo,
  redo,
  contextMenu,
  eraserWhileHeld,
  lassoWhileHeld,
  toggleEraser,
  previousTool,
  toolPalette,
  colorPalette,
  followSystem,
}

@immutable
class GestureSettings {
  const GestureSettings({
    this.twoFingerTapUndo = true,
    this.threeFingerTapRedo = true,
    this.longPressMenu = true,
    this.actions = const {},
  });

  // v1.4 bools: a false bool reads as EditorAction.none when [actions] has
  // no entry for that gesture (actionFor ②).
  final bool twoFingerTapUndo;
  final bool threeFingerTapRedo;
  final bool longPressMenu;

  final Map<EditorGesture, EditorAction> actions; // missing key → defaultFor

  /// Every gesture at defaultFor (bools true, actions empty).
  static const GestureSettings defaults = GestureSettings();

  /// ① [actions] entry inside allowedFor ② the v1.4 bool of the gesture is
  /// false → none ③ defaultFor (04-editor 4.3.2).
  EditorAction actionFor(EditorGesture gesture) {
    final explicit = actions[gesture];
    if (explicit != null && allowedFor(gesture).contains(explicit)) {
      return explicit;
    }
    if (_boolOf(gesture) == false) return EditorAction.none;
    return defaultFor(gesture);
  }

  /// The contract 7.2.10 table ('기본').
  static EditorAction defaultFor(EditorGesture gesture) => switch (gesture) {
    EditorGesture.twoFingerTap => EditorAction.undo,
    EditorGesture.threeFingerTap => EditorAction.redo,
    EditorGesture.fingerLongPress => EditorAction.contextMenu,
    EditorGesture.penButton => EditorAction.eraserWhileHeld,
    EditorGesture.invertedStylus => EditorAction.eraserWhileHeld,
    EditorGesture.pencilDoubleTap => EditorAction.followSystem,
    EditorGesture.pencilSqueeze => EditorAction.followSystem,
  };

  /// The contract 7.2.10 table ('고를 수 있는 동작'), in table order.
  static Set<EditorAction> allowedFor(EditorGesture gesture) =>
      switch (gesture) {
        EditorGesture.twoFingerTap => _tapActions,
        EditorGesture.threeFingerTap => _tapActions,
        EditorGesture.fingerLongPress => const {
          EditorAction.none,
          EditorAction.contextMenu,
        },
        EditorGesture.penButton => const {
          EditorAction.none,
          EditorAction.eraserWhileHeld,
          EditorAction.lassoWhileHeld,
        },
        EditorGesture.invertedStylus => const {
          EditorAction.none,
          EditorAction.eraserWhileHeld,
        },
        EditorGesture.pencilDoubleTap => const {
          EditorAction.none,
          EditorAction.followSystem,
          EditorAction.toggleEraser,
          EditorAction.previousTool,
          EditorAction.colorPalette,
          EditorAction.toolPalette,
          EditorAction.undo,
        },
        EditorGesture.pencilSqueeze => const {
          EditorAction.none,
          EditorAction.followSystem,
          EditorAction.toolPalette,
          EditorAction.colorPalette,
          EditorAction.toggleEraser,
        },
      };

  static const Set<EditorAction> _tapActions = {
    EditorAction.none,
    EditorAction.undo,
    EditorAction.redo,
    EditorAction.toggleEraser,
  };

  /// The v1.4 bool of [gesture]; null for the gestures without one.
  bool? _boolOf(EditorGesture gesture) => switch (gesture) {
    EditorGesture.twoFingerTap => twoFingerTapUndo,
    EditorGesture.threeFingerTap => threeFingerTapRedo,
    EditorGesture.fingerLongPress => longPressMenu,
    _ => null,
  };

  /// v1.4 copyWith + [actions]. Entries whose action is not in
  /// allowedFor(gesture) are dropped.
  GestureSettings copyWith({
    bool? twoFingerTapUndo,
    bool? threeFingerTapRedo,
    bool? longPressMenu,
    Map<EditorGesture, EditorAction>? actions,
  }) => GestureSettings(
    twoFingerTapUndo: twoFingerTapUndo ?? this.twoFingerTapUndo,
    threeFingerTapRedo: threeFingerTapRedo ?? this.threeFingerTapRedo,
    longPressMenu: longPressMenu ?? this.longPressMenu,
    actions: actions == null
        ? _allowedOnly(this.actions)
        : Map.unmodifiable(_allowedOnly(actions)),
  );

  /// actions with [gesture] → [action] (the v1.4 bool of that gesture
  /// follows: action != none). An action outside allowedFor(gesture) changes
  /// nothing (like copyWith, which drops it).
  ///
  /// [action] == defaultFor(gesture) removes the entry, except for a gesture
  /// whose v1.4 bool was false: there it stays explicit (04-editor 4.3.2).
  GestureSettings withAction(EditorGesture gesture, EditorAction action) {
    if (!allowedFor(gesture).contains(action)) return this;
    final next = Map<EditorGesture, EditorAction>.of(_allowedOnly(actions));
    if (action == defaultFor(gesture) && _boolOf(gesture) != false) {
      next.remove(gesture);
    } else {
      next[gesture] = action;
    }
    final on = action != EditorAction.none;
    return GestureSettings(
      twoFingerTapUndo: gesture == EditorGesture.twoFingerTap
          ? on
          : twoFingerTapUndo,
      threeFingerTapRedo: gesture == EditorGesture.threeFingerTap
          ? on
          : threeFingerTapRedo,
      longPressMenu: gesture == EditorGesture.fingerLongPress
          ? on
          : longPressMenu,
      actions: Map.unmodifiable(next),
    );
  }

  /// JSON: v1.4 keys + "actions": {"twoFingerTap": "undo", …}. Read: actions[k] wins, else the
  /// v1.4 bool (false → none), else default; unknown names ignored. Write: both (bool = action != none).
  ///
  /// `{"twoFingerUndo":true,"threeFingerRedo":true,"longPressMenu":true,
  /// "actions":{…}}` — "actions" holds the explicit entries only, by gesture
  /// name (04-editor 4.3.2).
  Map<String, Object?> toJson() {
    final explicit = _allowedOnly(actions);
    final gestures = explicit.keys.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return {
      'twoFingerUndo':
          actionFor(EditorGesture.twoFingerTap) != EditorAction.none,
      'threeFingerRedo':
          actionFor(EditorGesture.threeFingerTap) != EditorAction.none,
      'longPressMenu':
          actionFor(EditorGesture.fingerLongPress) != EditorAction.none,
      'actions': {for (final g in gestures) g.name: explicit[g]!.name},
    };
  }

  /// Unknown keys ignored; a missing or mistyped v1.4 bool takes its default
  /// (true). "actions" that is not an object is ignored as a whole; unknown
  /// gestures, unknown actions and actions outside allowedFor are dropped
  /// without a report (a newer version wrote them). The three bools are then
  /// set from actionFor, so the value is consistent (bool = action != none).
  factory GestureSettings.fromJson(Map<String, Object?> json) {
    const defaults = GestureSettings.defaults;
    final read = GestureSettings(
      twoFingerTapUndo: _boolOr(
        json['twoFingerUndo'],
        defaults.twoFingerTapUndo,
      ),
      threeFingerTapRedo: _boolOr(
        json['threeFingerRedo'],
        defaults.threeFingerTapRedo,
      ),
      longPressMenu: _boolOr(json['longPressMenu'], defaults.longPressMenu),
      actions: _actionsFromJson(json['actions']),
    );
    return GestureSettings(
      twoFingerTapUndo:
          read.actionFor(EditorGesture.twoFingerTap) != EditorAction.none,
      threeFingerTapRedo:
          read.actionFor(EditorGesture.threeFingerTap) != EditorAction.none,
      longPressMenu:
          read.actionFor(EditorGesture.fingerLongPress) != EditorAction.none,
      actions: read.actions,
    );
  }

  static Map<EditorGesture, EditorAction> _actionsFromJson(Object? value) {
    final json = _mapOrNull(value);
    if (json == null) return const {};
    final gestures = EditorGesture.values.asNameMap();
    final names = EditorAction.values.asNameMap();
    final out = <EditorGesture, EditorAction>{};
    for (final MapEntry(:key, :value) in json.entries) {
      final gesture = gestures[key];
      final action = value is String ? names[value] : null;
      if (gesture == null || action == null) continue;
      if (!allowedFor(gesture).contains(action)) continue;
      out[gesture] = action;
    }
    return Map.unmodifiable(out);
  }

  /// [actions] without the entries outside allowedFor (unmodifiable).
  static Map<EditorGesture, EditorAction> _allowedOnly(
    Map<EditorGesture, EditorAction> actions,
  ) {
    if (actions.entries.every((e) => allowedFor(e.key).contains(e.value))) {
      return actions;
    }
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in actions.entries)
        if (allowedFor(key).contains(value)) key: value,
    });
  }

  static const _actionMaps = MapEquality<EditorGesture, EditorAction>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureSettings &&
          other.twoFingerTapUndo == twoFingerTapUndo &&
          other.threeFingerTapRedo == threeFingerTapRedo &&
          other.longPressMenu == longPressMenu &&
          _actionMaps.equals(other.actions, actions);

  @override
  int get hashCode => Object.hash(
    twoFingerTapUndo,
    threeFingerTapRedo,
    longPressMenu,
    _actionMaps.hash(actions),
  );

  @override
  String toString() =>
      'GestureSettings(twoFingerUndo: $twoFingerTapUndo, '
      'threeFingerRedo: $threeFingerTapRedo, longPressMenu: $longPressMenu, '
      'actions: {${[for (final e in actions.entries) '${e.key.name}: ${e.value.name}'].join(', ')}})';
}

@immutable
class EditorSettings {
  const EditorSettings({
    this.inputMode = InputMode.auto,
    this.palmRejection = const PalmRejectionSettings(),
    this.gestures = GestureSettings.defaults,
    this.pageFlipMode = PageFlipMode.verticalScroll,
    this.pressureMode = ink.PressureMode.auto,
    this.showDevOverlay = false,
    this.stylusSeen = false,
    this.shapeAssist = true,
    this.playbackHighlight = ink.InkPlaybackStyle.dimUnwritten,
    this.tapToSeek = true,
  });

  final InputMode inputMode; // device
  final PalmRejectionSettings palmRejection; // device
  final GestureSettings gestures; // synced
  final PageFlipMode pageFlipMode; // synced
  final ink.PressureMode pressureMode; // device
  final bool showDevOverlay; // device

  /// A stylus event has been observed at least once on this device (persisted, device).
  final bool stylusSeen;

  /// (2nd round) Auto shape correction while holding the pen still (U14: on,
  /// can be turned off). Synced. Used from E2-15.
  final bool shapeAssist;

  /// (2nd round) How playback marks the strokes — the INK enum as is. Synced.
  /// Used from E2-17.
  final ink.InkPlaybackStyle playbackHighlight;

  /// (2nd round) A finger tap on a recorded stroke seeks the recording
  /// (contract 7.4.4 '탭 재생 켬'). Device. Used from E2-16 / E2-17.
  final bool tapToSeek;

  /// Effective "fingers do not draw" flag.
  bool get isPenOnlyEffective =>
      inputMode == InputMode.penOnly ||
      (inputMode == InputMode.auto && stylusSeen);

  EditorSettings copyWith({
    InputMode? inputMode,
    PalmRejectionSettings? palmRejection,
    GestureSettings? gestures,
    PageFlipMode? pageFlipMode,
    ink.PressureMode? pressureMode,
    bool? showDevOverlay,
    bool? stylusSeen,
    bool? shapeAssist,
    ink.InkPlaybackStyle? playbackHighlight,
    bool? tapToSeek,
  }) => EditorSettings(
    inputMode: inputMode ?? this.inputMode,
    palmRejection: palmRejection ?? this.palmRejection,
    gestures: gestures ?? this.gestures,
    pageFlipMode: pageFlipMode ?? this.pageFlipMode,
    pressureMode: pressureMode ?? this.pressureMode,
    showDevOverlay: showDevOverlay ?? this.showDevOverlay,
    stylusSeen: stylusSeen ?? this.stylusSeen,
    shapeAssist: shapeAssist ?? this.shapeAssist,
    playbackHighlight: playbackHighlight ?? this.playbackHighlight,
    tapToSeek: tapToSeek ?? this.tapToSeek,
  );

  /// The fields stored under the key of [scope] (6.14, 2nd round 6.18):
  ///   device: {"v":1, "inputMode":"auto", "palm":{...}, "pressure":"auto",
  ///            "dev":false, "stylusSeen":false, "tapToSeek":true}
  ///   synced: {"v":1, "gestures":{...}, "pageFlip":"verticalScroll",
  ///            "shapeAssist":true, "playbackHighlight":"dimUnwritten"}
  Map<String, Object?> toJson(core.SettingScope scope) => switch (scope) {
    core.SettingScope.device => {
      'v': _formatVersion,
      'inputMode': inputMode.name,
      'palm': palmRejection.toJson(),
      'pressure': pressureMode.name,
      'dev': showDevOverlay,
      'stylusSeen': stylusSeen,
      'tapToSeek': tapToSeek,
    },
    core.SettingScope.synced => {
      'v': _formatVersion,
      'gestures': gestures.toJson(),
      'pageFlip': pageFlipMode.name,
      'shapeAssist': shapeAssist,
      'playbackHighlight': playbackHighlight.name,
    },
  };

  /// Unknown keys ignored; invalid values → defaults. "pressure" accepts
  /// "auto" | "alwaysReal" | "alwaysSimulated" and the draft values
  /// "always" (→ alwaysReal) / "never" (→ alwaysSimulated).
  /// "playbackHighlight" is an ink.InkPlaybackStyle name.
  factory EditorSettings.fromJson({
    Map<String, Object?> device = const {},
    Map<String, Object?> synced = const {},
  }) {
    // "v" is not checked: a newer format keeps the fields this version
    // knows, and those are read the same way (04-editor 6.14).
    const defaults = EditorSettings();
    final palm = _mapOrNull(device['palm']);
    final gestures = _mapOrNull(synced['gestures']);
    return EditorSettings(
      inputMode: _enumOr(
        device['inputMode'],
        InputMode.values,
        defaults.inputMode,
      ),
      palmRejection: palm == null
          ? defaults.palmRejection
          : PalmRejectionSettings.fromJson(palm),
      gestures: gestures == null
          ? defaults.gestures
          : GestureSettings.fromJson(gestures),
      pageFlipMode: _enumOr(
        synced['pageFlip'],
        PageFlipMode.values,
        defaults.pageFlipMode,
      ),
      pressureMode: _pressureModeOr(device['pressure'], defaults.pressureMode),
      showDevOverlay: _boolOr(device['dev'], defaults.showDevOverlay),
      stylusSeen: _boolOr(device['stylusSeen'], defaults.stylusSeen),
      shapeAssist: _boolOr(synced['shapeAssist'], defaults.shapeAssist),
      playbackHighlight: _enumOr(
        synced['playbackHighlight'],
        ink.InkPlaybackStyle.values,
        defaults.playbackHighlight,
      ),
      tapToSeek: _boolOr(device['tapToSeek'], defaults.tapToSeek),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorSettings &&
          other.inputMode == inputMode &&
          other.palmRejection == palmRejection &&
          other.gestures == gestures &&
          other.pageFlipMode == pageFlipMode &&
          other.pressureMode == pressureMode &&
          other.showDevOverlay == showDevOverlay &&
          other.stylusSeen == stylusSeen &&
          other.shapeAssist == shapeAssist &&
          other.playbackHighlight == playbackHighlight &&
          other.tapToSeek == tapToSeek;

  @override
  int get hashCode => Object.hash(
    inputMode,
    palmRejection,
    gestures,
    pageFlipMode,
    pressureMode,
    showDevOverlay,
    stylusSeen,
    shapeAssist,
    playbackHighlight,
    tapToSeek,
  );

  @override
  String toString() =>
      'EditorSettings(inputMode: ${inputMode.name}, $palmRejection, '
      '$gestures, pageFlip: ${pageFlipMode.name}, '
      'pressure: ${pressureMode.name}, dev: $showDevOverlay, '
      'stylusSeen: $stylusSeen, shapeAssist: $shapeAssist, '
      'playbackHighlight: ${playbackHighlight.name}, tapToSeek: $tapToSeek)';
}

/// First field of both stored objects (04-editor 6.14).
const int _formatVersion = 1;

/// Draft wire values of the pressure mode, read for compatibility.
const Map<String, ink.PressureMode> _draftPressureModes = {
  'always': ink.PressureMode.alwaysReal,
  'never': ink.PressureMode.alwaysSimulated,
};

ink.PressureMode _pressureModeOr(Object? value, ink.PressureMode fallback) {
  if (value is! String) return fallback;
  return ink.PressureMode.values.asNameMap()[value] ??
      _draftPressureModes[value] ??
      fallback;
}

T _enumOr<T extends Enum>(Object? value, List<T> values, T fallback) {
  if (value is! String) return fallback;
  return values.asNameMap()[value] ?? fallback;
}

bool _boolOr(Object? value, bool fallback) => value is bool ? value : fallback;

/// [value] when it is a finite number in [min, max], else null.
num? _numIn(Object? value, num min, num max) {
  if (value is! num || !value.isFinite) return null;
  return value < min || value > max ? null : value;
}

/// A JSON object as `Map<String, Object?>`; null for anything else. Entries
/// with non-string keys are dropped.
Map<String, Object?>? _mapOrNull(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is! Map<Object?, Object?>) return null;
  return {
    for (final entry in value.entries)
      if (entry.key case final String key) key: entry.value,
  };
}
