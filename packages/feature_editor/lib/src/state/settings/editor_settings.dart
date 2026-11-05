// lib/src/state/settings/editor_settings.dart — contract 00-overview 7.2.17
// ('EditorSettings / InputMode / PageFlipMode / PalmRejectionSettings /
// GestureSettings — EDITOR 4.8, with `final ink.PressureMode pressureMode`'),
// 04-editor 4.8; stored form 04-editor 6.14, contract 7.4.6.
//
// Pure value types. The JSON helpers are the stored form of the two CORE
// setting keys 'editor.settings.device' and 'editor.settings.synced'; loading
// and saving them is EditorSettingsNotifier's job (task E-06).
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

/// M1: on/off only (contract 7.8). M5 adds per-gesture action mapping.
@immutable
class GestureSettings {
  const GestureSettings({
    this.twoFingerTapUndo = true,
    this.threeFingerTapRedo = true,
    this.longPressMenu = true,
  });

  final bool twoFingerTapUndo;
  final bool threeFingerTapRedo;
  final bool longPressMenu;

  GestureSettings copyWith({
    bool? twoFingerTapUndo,
    bool? threeFingerTapRedo,
    bool? longPressMenu,
  }) => GestureSettings(
    twoFingerTapUndo: twoFingerTapUndo ?? this.twoFingerTapUndo,
    threeFingerTapRedo: threeFingerTapRedo ?? this.threeFingerTapRedo,
    longPressMenu: longPressMenu ?? this.longPressMenu,
  );

  /// `{"twoFingerUndo":true,"threeFingerRedo":true,"longPressMenu":true}`
  /// (04-editor 6.14).
  Map<String, Object?> toJson() => {
    'twoFingerUndo': twoFingerTapUndo,
    'threeFingerRedo': threeFingerTapRedo,
    'longPressMenu': longPressMenu,
  };

  /// Unknown keys ignored; a missing or mistyped field takes its default.
  factory GestureSettings.fromJson(Map<String, Object?> json) {
    const defaults = GestureSettings();
    return GestureSettings(
      twoFingerTapUndo: _boolOr(
        json['twoFingerUndo'],
        defaults.twoFingerTapUndo,
      ),
      threeFingerTapRedo: _boolOr(
        json['threeFingerRedo'],
        defaults.threeFingerTapRedo,
      ),
      longPressMenu: _boolOr(json['longPressMenu'], defaults.longPressMenu),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureSettings &&
          other.twoFingerTapUndo == twoFingerTapUndo &&
          other.threeFingerTapRedo == threeFingerTapRedo &&
          other.longPressMenu == longPressMenu;

  @override
  int get hashCode =>
      Object.hash(twoFingerTapUndo, threeFingerTapRedo, longPressMenu);

  @override
  String toString() =>
      'GestureSettings(twoFingerUndo: $twoFingerTapUndo, '
      'threeFingerRedo: $threeFingerTapRedo, longPressMenu: $longPressMenu)';
}

@immutable
class EditorSettings {
  const EditorSettings({
    this.inputMode = InputMode.auto,
    this.palmRejection = const PalmRejectionSettings(),
    this.gestures = const GestureSettings(),
    this.pageFlipMode = PageFlipMode.verticalScroll,
    this.pressureMode = ink.PressureMode.auto,
    this.showDevOverlay = false,
    this.stylusSeen = false,
  });

  final InputMode inputMode; // device
  final PalmRejectionSettings palmRejection; // device
  final GestureSettings gestures; // synced
  final PageFlipMode pageFlipMode; // synced
  final ink.PressureMode pressureMode; // device
  final bool showDevOverlay; // device

  /// A stylus event has been observed at least once on this device (persisted, device).
  final bool stylusSeen;

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
  }) => EditorSettings(
    inputMode: inputMode ?? this.inputMode,
    palmRejection: palmRejection ?? this.palmRejection,
    gestures: gestures ?? this.gestures,
    pageFlipMode: pageFlipMode ?? this.pageFlipMode,
    pressureMode: pressureMode ?? this.pressureMode,
    showDevOverlay: showDevOverlay ?? this.showDevOverlay,
    stylusSeen: stylusSeen ?? this.stylusSeen,
  );

  /// The fields stored under the key of [scope] (6.14):
  ///   device: {"v":1, "inputMode":"auto", "palm":{...}, "pressure":"auto",
  ///            "dev":false, "stylusSeen":false}
  ///   synced: {"v":1, "gestures":{...}, "pageFlip":"verticalScroll"}
  Map<String, Object?> toJson(core.SettingScope scope) => switch (scope) {
    core.SettingScope.device => {
      'v': _formatVersion,
      'inputMode': inputMode.name,
      'palm': palmRejection.toJson(),
      'pressure': pressureMode.name,
      'dev': showDevOverlay,
      'stylusSeen': stylusSeen,
    },
    core.SettingScope.synced => {
      'v': _formatVersion,
      'gestures': gestures.toJson(),
      'pageFlip': pageFlipMode.name,
    },
  };

  /// Unknown keys ignored; invalid values → defaults. "pressure" accepts
  /// "auto" | "alwaysReal" | "alwaysSimulated" and the draft values
  /// "always" (→ alwaysReal) / "never" (→ alwaysSimulated).
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
          other.stylusSeen == stylusSeen;

  @override
  int get hashCode => Object.hash(
    inputMode,
    palmRejection,
    gestures,
    pageFlipMode,
    pressureMode,
    showDevOverlay,
    stylusSeen,
  );

  @override
  String toString() =>
      'EditorSettings(inputMode: ${inputMode.name}, $palmRejection, '
      '$gestures, pageFlip: ${pageFlipMode.name}, '
      'pressure: ${pressureMode.name}, dev: $showDevOverlay, '
      'stylusSeen: $stylusSeen)';
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
