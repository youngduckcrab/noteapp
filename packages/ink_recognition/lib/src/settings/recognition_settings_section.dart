// lib/src/settings/recognition_settings_section.dart — contract
// m5-7/00-overview 7.2.11 (m5-7/05-library 6.18, 6.19).
//
// The settings screen's '인식' section body (1차 7.4.11 section rules: a
// Column only — no Scaffold, title or scroll; the parent gives the width;
// while the settings load every input is disabled at opacity 0.38, like
// LibrarySettingsSection). The section itself has no state (contract: a
// const ConsumerWidget — review S-14); stateful rows are private widgets.
//
// L2-18 (P-A): the handwriting group (language, Wi-Fi only, automatic
// indexing + the 6.19 status line; without an available engine — the web,
// desktops — the fixed sentence and the group disabled) and the math group
// (engine, consent). Every change is stored at once (CORE settings); a value
// set on another device shows (settingsSnapshotProvider).
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/report_error.dart';
import '../indexer/indexer_status.dart';
import '../l10n/recognition_strings.dart';
import '../ports/math_recognizer.dart';
import '../ports/model_admin.dart';
import '../providers.dart';
import 'recognition_settings_keys.dart';

/// Appendix C keys of the section (INFRA V5 · V6 — not contract).
abstract final class RecognitionSettingsUiKeys {
  static const ValueKey<String> language = ValueKey('recog.settings.language');
  static const ValueKey<String> wifiOnly = ValueKey('recog.settings.wifiOnly');
  static const ValueKey<String> autoIndex = ValueKey(
    'recog.settings.autoIndex',
  );
  static const ValueKey<String> consent = ValueKey('recog.settings.consent');
  static const ValueKey<String> mathEngine = ValueKey(
    'recog.settings.mathEngine',
  );
  static const ValueKey<String> status = ValueKey('recog.settings.status');
  static const ValueKey<String> unsupported = ValueKey(
    'recog.settings.unsupported',
  );

  /// One language choice ('ko' | 'en').
  static ValueKey<String> languageOf(String tag) =>
      ValueKey('recog.settings.language.$tag');
}

/// The 6.19 settings text of [status] (null = no indexer): '상태: ' + the
/// phase text, and for `off` the plain sentence.
String indexerStatusText(HandwritingIndexerStatus? status) {
  final s = status ?? const HandwritingIndexerStatus();
  const prefix = RecognitionStrings.statusPrefix;
  final waitingWifi = s.lastError?.contains('waiting for Wi-Fi') ?? false;
  return switch (s.phase) {
    HandwritingIndexerPhase.off => RecognitionStrings.indexerOff,
    HandwritingIndexerPhase.disabled =>
      '$prefix${RecognitionStrings.indexerDisabled}',
    HandwritingIndexerPhase.waitingModel =>
      '$prefix${RecognitionStrings.indexerWaitingModel}'
          '${waitingWifi ? RecognitionStrings.indexerWaitingWifi : ''}',
    HandwritingIndexerPhase.idle =>
      '$prefix${RecognitionStrings.indexerIdle(s.indexedPages)}',
    HandwritingIndexerPhase.waitingInput =>
      '$prefix${RecognitionStrings.indexerWaitingInput(s.queuedPages)}',
    HandwritingIndexerPhase.recognizing =>
      '$prefix${RecognitionStrings.indexerRecognizing(s.queuedPages)}',
    HandwritingIndexerPhase.paused =>
      '$prefix${RecognitionStrings.indexerPaused}',
  };
}

class RecognitionSettingsSection extends ConsumerWidget {
  const RecognitionSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(core.settingsSnapshotProvider);
    final loaded = snapshot.hasValue;
    final values = snapshot.value ?? const core.SettingsSnapshot({});
    final recognizer = ref.watch(handwritingRecognizerProvider);
    final math = ref.watch(mathRecognizerProvider);
    // G-1: never on the web, whatever the engine says.
    final available = !kIsWeb && recognizer.isAvailable;
    final asksBeforeCellular = switch (recognizer) {
      RecognizerModelAdmin(enforcesWifiOnly: false) => true,
      _ => false,
    };

    void save<T>(core.SettingKey<T> key, T value) {
      final settings = ref.read(core.settingsRepositoryProvider);
      unawaited(
        settings
            .set(key, value)
            .then<void>(
              (_) {},
              onError: (Object e, StackTrace s) =>
                  reportRecognitionError(e, s, 'saving ${key.name}'),
            ),
      );
    }

    final language = recognitionLanguageOf(
      values.get(RecognitionSettingsKeys.language),
    );
    final manualMath = math is ManualOnlyMathRecognizer || !math.isAvailable;

    return IgnorePointer(
      ignoring: !loaded,
      child: Opacity(
        opacity: loaded ? 1 : 0.38,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GroupHeader(RecognitionStrings.handwritingGroup),
            if (!available)
              _Notice(
                key: RecognitionSettingsUiKeys.unsupported,
                text: kIsWeb
                    ? RecognitionStrings.webUnsupported
                    : RecognitionStrings.unsupported,
              ),
            _LanguageChoice(
              value: language,
              enabled: available,
              onChanged: (tag) => save(RecognitionSettingsKeys.language, tag),
            ),
            SwitchListTile(
              key: RecognitionSettingsUiKeys.wifiOnly,
              title: const Text(RecognitionStrings.wifiOnlyTitle),
              subtitle: asksBeforeCellular
                  ? const Text(RecognitionStrings.wifiOnlyAskFirst)
                  : null,
              value: values.get(RecognitionSettingsKeys.modelWifiOnly),
              onChanged: available
                  ? (v) => save(RecognitionSettingsKeys.modelWifiOnly, v)
                  : null,
            ),
            SwitchListTile(
              key: RecognitionSettingsUiKeys.autoIndex,
              title: const Text(RecognitionStrings.autoIndexTitle),
              subtitle: const _IndexerStatusLine(),
              value: values.get(RecognitionSettingsKeys.autoIndex),
              onChanged: available
                  ? (v) => save(RecognitionSettingsKeys.autoIndex, v)
                  : null,
            ),
            const _GroupHeader(RecognitionStrings.mathGroup),
            ListTile(
              key: RecognitionSettingsUiKeys.mathEngine,
              title: const Text(RecognitionStrings.mathEngineTitle),
              subtitle: Text(
                manualMath
                    ? RecognitionStrings.mathEngineManual
                    : RecognitionStrings.mathEngineServer,
              ),
            ),
            SwitchListTile(
              key: RecognitionSettingsUiKeys.consent,
              title: const Text(RecognitionStrings.consentSwitch),
              subtitle: const Text(RecognitionStrings.consentBody),
              isThreeLine: true,
              value: values.get(RecognitionSettingsKeys.mathConsent),
              onChanged: (v) => save(RecognitionSettingsKeys.mathConsent, v),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// The fixed sentence above a disabled handwriting group.
class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// 인식 언어 ( ● 한국어 ○ English ) — recog.language.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    key: RecognitionSettingsUiKeys.language,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        enabled: enabled,
        title: const Text(RecognitionStrings.languageTitle),
      ),
      RadioGroup<String>(
        groupValue: value,
        onChanged: (tag) {
          if (enabled && tag != null && tag != value) onChanged(tag);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tag in kRecognitionLanguages)
              RadioListTile<String>(
                key: RecognitionSettingsUiKeys.languageOf(tag),
                value: tag,
                enabled: enabled,
                title: Text(RecognitionStrings.languageLabel(tag)),
              ),
          ],
        ),
      ),
    ],
  );
}

/// The indexer status under '검색용 자동 인식' (6.19); no indexer (web, no
/// engine) → '이 기기에서는 자동 인식을 쓸 수 없어요'.
class _IndexerStatusLine extends ConsumerWidget {
  const _IndexerStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexer = ref.watch(handwritingIndexerProvider);
    if (indexer == null) {
      return Text(
        indexerStatusText(null),
        key: RecognitionSettingsUiKeys.status,
      );
    }
    return ValueListenableBuilder<HandwritingIndexerStatus>(
      valueListenable: indexer.status,
      builder: (context, status, _) => Text(
        indexerStatusText(status),
        key: RecognitionSettingsUiKeys.status,
      ),
    );
  }
}
