// lib/src/ui/settings/editor_settings_sections.dart — contract 00-overview
// 7.2.17 ('Settings sections (Column only, no Scaffold)'), 04-editor 4.9.
//
// INFRA's settings screen puts these inside its ListView, in the order
// editor.input → editor.pen → 일반 › editor.page → editor.developer, and draws
// the section titles itself (01-infra 4.5.8). Each widget is a Column without
// a Scaffold or its own scrolling. They edit the same global providers as the
// editor (editorSettingsProvider, editorToolProvider), so the two places
// always agree.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/dev_tools.dart' as dev;
import 'package:note_core/note_core.dart' as core;

import '../../state/settings/editor_settings.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../../state/settings/pre_roll.dart';
import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import '../pen/pen_advanced_controls.dart';
import '../pen/pen_type_selector.dart';

/// Keys of the section controls (tests; not exported).
abstract final class SettingsSectionKeys {
  static const inputMode = ValueKey('editor.settings.inputMode');
  static const inputModeHint = ValueKey('editor.settings.inputMode.hint');
  static const penCooldown = ValueKey('editor.settings.penCooldown');
  static const hoverAsPen = ValueKey('editor.settings.hoverAsPen');
  static const maxTouchRadius = ValueKey('editor.settings.maxTouchRadius');
  static const twoFingerTapUndo = ValueKey('editor.settings.twoFingerTapUndo');
  static const threeFingerTapRedo = ValueKey(
    'editor.settings.threeFingerTapRedo',
  );
  static const longPressMenu = ValueKey('editor.settings.longPressMenu');
  static const fixedGestures = ValueKey('editor.settings.fixedGestures');
  static const resetInput = ValueKey('editor.settings.resetInput');
  static const pressureMode = ValueKey('editor.settings.pressureMode');
  static const pressureState = ValueKey('editor.settings.pressureState');
  static const penType = ValueKey('editor.settings.penType');
  static const resetPenDefaults = ValueKey('editor.settings.resetPenDefaults');
  static const resetPenDefaultsConfirm = ValueKey(
    'editor.settings.resetPenDefaults.confirm',
  );
  static const pageFlip = ValueKey('editor.settings.pageFlip');
  static const devOverlay = ValueKey('editor.settings.devOverlay');
  static const devOverlayHint = ValueKey('editor.settings.devOverlay.hint');
  static const seedSyntheticNote = ValueKey('editor.settings.seedSynthetic');
  // (v2) 일반 › 페이지 › 필기 재생 (m5-7/04-editor 6.15.3)
  static const playbackTapToSeek = ValueKey(
    'editor.settings.playback.tapToSeek',
  );
  static const playbackPreRoll = ValueKey('editor.settings.playback.preRoll');
  static const playbackHighlight = ValueKey(
    'editor.settings.playback.highlight',
  );
}

/// 입력: 입력 모드(자동/펜 전용/손가락 필기), 팜 리젝션(펜 직후 터치 무시 시간,
/// 펜 hover 중 터치 무시, 접촉 반경 — 지원 기기 안내 문구 포함),
/// 제스처(두 손가락 탭 되돌리기, 세 손가락 탭 다시 실행, 길게 누르기 메뉴 켜기/끄기,
/// 나머지 제스처는 읽기 전용 표).
class EditorInputSettingsSection extends ConsumerWidget {
  const EditorInputSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(editorSettingsProvider);
    final notifier = ref.read(editorSettingsProvider.notifier);
    final palm = settings.palmRejection;
    final gestures = settings.gestures;
    final hintStyle = _hintStyle(context);
    final cooldownMs = palm.penCooldown.inMilliseconds.clamp(0, 1500);
    final radius = palm.maxTouchRadius.clamp(20.0, 120.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label(EditorStrings.inputMode),
        _Padded(
          SegmentedButton<InputMode>(
            key: SettingsSectionKeys.inputMode,
            segments: const [
              ButtonSegment(
                value: InputMode.auto,
                label: Text(EditorStrings.inputModeAuto),
              ),
              ButtonSegment(
                value: InputMode.penOnly,
                label: Text(EditorStrings.inputModePenOnly),
              ),
              ButtonSegment(
                value: InputMode.fingerDrawing,
                label: Text(EditorStrings.inputModeFingerDrawing),
              ),
            ],
            selected: {settings.inputMode},
            onSelectionChanged: (s) => notifier.setInputMode(s.single),
          ),
        ),
        _Padded(
          Text(
            switch (settings.inputMode) {
              InputMode.auto => EditorStrings.inputModeAutoHint,
              InputMode.penOnly => EditorStrings.inputModePenOnlyHint,
              InputMode.fingerDrawing =>
                EditorStrings.inputModeFingerDrawingHint,
            },
            key: SettingsSectionKeys.inputModeHint,
            style: hintStyle,
          ),
        ),
        const _Label(EditorStrings.palmRejection),
        _Padded(Text(EditorStrings.penCooldownLabel(cooldownMs))),
        Semantics(
          label: EditorStrings.penCooldown,
          child: Slider(
            key: SettingsSectionKeys.penCooldown,
            value: cooldownMs.toDouble(),
            max: 1500,
            divisions: 30, // 50 ms steps
            onChanged: (v) => notifier.setPalmRejection(
              palm.copyWith(
                penCooldown: Duration(milliseconds: (v / 50).round() * 50),
              ),
            ),
          ),
        ),
        SwitchListTile(
          key: SettingsSectionKeys.hoverAsPen,
          title: const Text(EditorStrings.hoverAsPen),
          subtitle: const Text(EditorStrings.hoverAsPenHint),
          value: palm.treatHoverAsPenActivity,
          onChanged: (v) => notifier.setPalmRejection(
            palm.copyWith(treatHoverAsPenActivity: v),
          ),
        ),
        _Padded(Text(EditorStrings.maxTouchRadiusLabel(radius.round()))),
        Semantics(
          label: EditorStrings.maxTouchRadius,
          child: Slider(
            key: SettingsSectionKeys.maxTouchRadius,
            value: radius,
            min: 20,
            max: 120,
            divisions: 20, // 5 px steps
            onChanged: (v) => notifier.setPalmRejection(
              palm.copyWith(maxTouchRadius: (v / 5).roundToDouble() * 5),
            ),
          ),
        ),
        _Padded(Text(EditorStrings.maxTouchRadiusHint, style: hintStyle)),
        const _Label(EditorStrings.gestures),
        SwitchListTile(
          key: SettingsSectionKeys.twoFingerTapUndo,
          title: const Text(EditorStrings.twoFingerTapUndo),
          value: gestures.twoFingerTapUndo,
          onChanged: (v) =>
              notifier.setGestures(gestures.copyWith(twoFingerTapUndo: v)),
        ),
        SwitchListTile(
          key: SettingsSectionKeys.threeFingerTapRedo,
          title: const Text(EditorStrings.threeFingerTapRedo),
          value: gestures.threeFingerTapRedo,
          onChanged: (v) =>
              notifier.setGestures(gestures.copyWith(threeFingerTapRedo: v)),
        ),
        SwitchListTile(
          key: SettingsSectionKeys.longPressMenu,
          title: const Text(EditorStrings.longPressMenu),
          value: gestures.longPressMenu,
          onChanged: (v) =>
              notifier.setGestures(gestures.copyWith(longPressMenu: v)),
        ),
        const _Label(EditorStrings.fixedGestures),
        _Padded(
          Table(
            key: SettingsSectionKeys.fixedGestures,
            columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)},
            children: [
              for (final (gesture, action) in EditorStrings.fixedGestureTable)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(gesture),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(action, style: hintStyle),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: SettingsSectionKeys.resetInput,
            onPressed: () => notifier
              ..setInputMode(InputMode.auto)
              ..setPalmRejection(const PalmRejectionSettings())
              ..setGestures(GestureSettings.defaults),
            child: const Text(EditorStrings.resetInput),
          ),
        ),
      ],
    );
  }
}

/// 펜: 필압 사용(자동/항상 사용/사용 안 함 = ink.PressureMode, 현재 감지 상태는
/// ink.pressureCapabilityProvider), 그리고 현재 펜 종류(editorToolProvider.penType)의
/// 필압 곡선(부드럽게/보통/단단하게)·필압 감도·손떨림 보정·(형광펜일 때) 직선 보정,
/// '펜 종류별 기본값으로 초기화'(core.StrokeStyle.defaultsFor). 펜 종류 선택 칩으로
/// 다른 종류의 값도 편집할 수 있다(펜 팝업 '고급'과 같은 값 — 6.9.3).
class EditorPenSettingsSection extends ConsumerWidget {
  const EditorPenSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _PenSectionBody();
}

/// The pen section's body: remembers which pen type's values it edits (a
/// chip here does not change the editor's current pen).
class _PenSectionBody extends ConsumerStatefulWidget {
  const _PenSectionBody();

  @override
  ConsumerState<_PenSectionBody> createState() => _PenSectionBodyState();
}

class _PenSectionBodyState extends ConsumerState<_PenSectionBody> {
  core.PenTool? _tool; // null = the current pen type

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(EditorStrings.resetPenDefaultsTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(EditorStrings.cancel),
          ),
          FilledButton(
            key: SettingsSectionKeys.resetPenDefaultsConfirm,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(EditorStrings.reset),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(editorToolProvider.notifier).resetPenDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(
      editorSettingsProvider.select((s) => s.pressureMode),
    );
    final stylus = ref.watch(
      ink.pressureCapabilityProvider.select((s) => s.stylus),
    );
    final current = ref.watch(editorToolProvider.select((s) => s.penType));
    final tool = _tool ?? current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label(EditorStrings.pressureMode),
        _Padded(
          SegmentedButton<ink.PressureMode>(
            key: SettingsSectionKeys.pressureMode,
            segments: const [
              ButtonSegment(
                value: ink.PressureMode.auto,
                label: Text(EditorStrings.pressureModeAuto),
              ),
              ButtonSegment(
                value: ink.PressureMode.alwaysReal,
                label: Text(EditorStrings.pressureModeReal),
              ),
              ButtonSegment(
                value: ink.PressureMode.alwaysSimulated,
                label: Text(EditorStrings.pressureModeSimulated),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ref
                .read(editorSettingsProvider.notifier)
                .setPressureMode(s.single),
          ),
        ),
        _Padded(
          Text(
            EditorStrings.pressureState(switch (stylus) {
              ink.PressureCapability.unknown => EditorStrings.pressureDetecting,
              ink.PressureCapability.supported =>
                EditorStrings.pressureSupported,
              ink.PressureCapability.unsupported =>
                EditorStrings.pressureUnsupported,
            }),
            key: SettingsSectionKeys.pressureState,
            style: _hintStyle(context),
          ),
        ),
        const _Label(EditorStrings.penTypeToEdit),
        _Padded(
          PenTypeSelector(
            key: SettingsSectionKeys.penType,
            selected: tool,
            onSelected: (t) => setState(() => _tool = t),
          ),
        ),
        _Padded(PenAdvancedControls(tool: tool)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: SettingsSectionKeys.resetPenDefaults,
            onPressed: () => unawaited(_confirmReset()),
            child: const Text(EditorStrings.resetPenDefaults),
          ),
        ),
      ],
    );
  }
}

/// 일반 › 페이지 넘김: 세로 스크롤 / 좌우 넘기기. (v2, m5-7/04-editor 6.15.3)
/// 필기 재생: 필기를 탭해 그 부분 재생(device), 탭한 곳보다 앞에서 재생
/// (0~5 s, 0.5 s 단위 — 놓을 때 저장, editor.playback.preRollMs), 강조 방식
/// (안 쓴 필기 흐리게 / 방금 쓴 필기만 강조).
class EditorPageSettingsSection extends ConsumerWidget {
  const EditorPageSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flip = ref.watch(
      editorSettingsProvider.select((s) => s.pageFlipMode),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label(EditorStrings.pageFlip),
        _Padded(
          SegmentedButton<PageFlipMode>(
            key: SettingsSectionKeys.pageFlip,
            segments: const [
              ButtonSegment(
                value: PageFlipMode.verticalScroll,
                label: Text(EditorStrings.pageFlipVertical),
              ),
              ButtonSegment(
                value: PageFlipMode.horizontalPaged,
                label: Text(EditorStrings.pageFlipHorizontal),
              ),
            ],
            selected: {flip},
            onSelectionChanged: (s) => ref
                .read(editorSettingsProvider.notifier)
                .setPageFlipMode(s.single),
          ),
        ),
        _Padded(Text(EditorStrings.pageFlipHint, style: _hintStyle(context))),
        const _PlaybackRows(),
      ],
    );
  }
}

/// (v2) 필기 재생 rows of the page section.
class _PlaybackRows extends ConsumerWidget {
  const _PlaybackRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tapToSeek = ref.watch(
      editorSettingsProvider.select((s) => s.tapToSeek),
    );
    final style = ref.watch(
      editorSettingsProvider.select((s) => s.playbackHighlight),
    );
    final settings = ref.read(editorSettingsProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label(EditorStrings.playbackSection),
        SwitchListTile(
          key: SettingsSectionKeys.playbackTapToSeek,
          title: const Text(EditorStrings.tapToSeek),
          value: tapToSeek,
          onChanged: settings.setTapToSeek,
        ),
        const _PreRollSlider(),
        const _Label(EditorStrings.playbackHighlight),
        _Padded(
          SegmentedButton<ink.InkPlaybackStyle>(
            key: SettingsSectionKeys.playbackHighlight,
            segments: const [
              ButtonSegment(
                value: ink.InkPlaybackStyle.dimUnwritten,
                label: Text(EditorStrings.playbackDimUnwritten),
              ),
              ButtonSegment(
                value: ink.InkPlaybackStyle.highlightRecent,
                label: Text(EditorStrings.playbackHighlightRecent),
              ),
            ],
            selected: {style},
            onSelectionChanged: (s) => settings.setPlaybackHighlight(s.single),
          ),
        ),
      ],
    );
  }
}

/// 0~5 s in 0.5 s steps; the value is stored when the thumb is let go
/// (PreRollMsNotifier — 500 ms debounce, synced).
class _PreRollSlider extends ConsumerStatefulWidget {
  const _PreRollSlider();

  @override
  ConsumerState<_PreRollSlider> createState() => _PreRollSliderState();
}

class _PreRollSliderState extends ConsumerState<_PreRollSlider> {
  static const _step = 500;

  /// The value while dragging (null: the stored one).
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(editorPreRollMsProvider);
    final value = _dragging ?? stored.toDouble();
    final shown = (value / _step).round() * _step;
    return ListTile(
      title: const Text(EditorStrings.playbackPreRoll),
      subtitle: Slider(
        key: SettingsSectionKeys.playbackPreRoll,
        min: PreRollMsNotifier.minMs.toDouble(),
        max: PreRollMsNotifier.maxMs.toDouble(),
        divisions: (PreRollMsNotifier.maxMs - PreRollMsNotifier.minMs) ~/ _step,
        value: value.clamp(
          PreRollMsNotifier.minMs.toDouble(),
          PreRollMsNotifier.maxMs.toDouble(),
        ),
        label: EditorStrings.playbackPreRollLabel(shown),
        onChanged: (v) => setState(() => _dragging = v),
        onChangeEnd: (v) {
          setState(() => _dragging = null);
          ref
              .read(editorPreRollMsProvider.notifier)
              .set((v / _step).round() * _step);
        },
      ),
      trailing: Text(EditorStrings.playbackPreRollLabel(shown)),
    );
  }
}

/// 개발자 표시 켜기/끄기, 켜는 다른 방법 안내, '합성 노트 만들기'(core seedSyntheticNote,
/// 6.12.4).
class EditorDeveloperSettingsSection extends ConsumerWidget {
  const EditorDeveloperSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const _DeveloperSectionBody();
}

class _DeveloperSectionBody extends ConsumerStatefulWidget {
  const _DeveloperSectionBody();

  @override
  ConsumerState<_DeveloperSectionBody> createState() =>
      _DeveloperSectionBodyState();
}

class _DeveloperSectionBodyState extends ConsumerState<_DeveloperSectionBody> {
  bool _seeding = false;

  /// seedSyntheticNote(store, title: 'perf-test', pages: 50,
  /// strokesPerPage: 300) → "합성 노트를 만들었어요 …" (6.12.4). A failure is
  /// reported and shows '실행하지 못했어요'.
  Future<void> _seed() async {
    if (_seeding) return;
    setState(() => _seeding = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final store = ref.read(core.noteStoreProvider);
    var message = EditorStrings.seedSyntheticNoteDone;
    try {
      await dev.seedSyntheticNote(
        store,
        title: 'perf-test',
        pages: 50,
        strokesPerPage: 300,
      );
    } on Object catch (error, stack) {
      message = EditorStrings.commandFailed;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while seeding a synthetic note'),
        ),
      );
    }
    if (mounted) setState(() => _seeding = false);
    if (messenger != null && messenger.mounted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = ref.watch(
      editorSettingsProvider.select((s) => s.showDevOverlay),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: SettingsSectionKeys.devOverlay,
          title: const Text(EditorStrings.devOverlay),
          value: shown,
          onChanged: ref
              .read(editorSettingsProvider.notifier)
              .setShowDevOverlay,
        ),
        _Padded(
          Text(
            EditorStrings.devOverlayHint,
            key: SettingsSectionKeys.devOverlayHint,
            style: _hintStyle(context),
          ),
        ),
        ListTile(
          key: SettingsSectionKeys.seedSyntheticNote,
          enabled: !_seeding,
          title: const Text(EditorStrings.seedSyntheticNote),
          subtitle: const Text(EditorStrings.seedSyntheticNoteHint),
          trailing: _seeding
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: () => unawaited(_seed()),
        ),
      ],
    );
  }
}

TextStyle? _hintStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodySmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
}

/// A small heading inside a section (INFRA draws the section title).
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// ListTile's horizontal inset (16).
class _Padded extends StatelessWidget {
  const _Padded(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: child,
  );
}
