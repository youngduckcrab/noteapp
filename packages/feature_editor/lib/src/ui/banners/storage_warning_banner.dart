// lib/src/ui/banners/storage_warning_banner.dart — 04-editor 6.17.3 (EDITOR-S2).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../editor_strings.dart';
import 'read_only_banner.dart';

/// `core.storageWarningOf(storageInfo, latest persistence status)`: the fixed
/// sentences of contract 7.4.5 v1.1. Nothing only while the status stream
/// has not delivered its first value (the first frame — it emits the current
/// value right after listen, contract 7.2.12 v1.1). No close button.
class StorageWarningBanner extends ConsumerWidget {
  const StorageWarningBanner({super.key});

  static const bannerKey = ValueKey('editor.banner.storage');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(core.persistenceStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final warning = core.storageWarningOf(
      ref.watch(core.storageInfoProvider),
      status,
    );
    if (warning == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return switch (warning) {
      core.StorageWarning.writeFailing => BannerLine(
        key: bannerKey,
        icon: Icons.error_outline,
        text: EditorStrings.storageWriteFailing,
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      ),
      core.StorageWarning.notDurable => BannerLine(
        key: bannerKey,
        icon: Icons.warning_amber,
        text: EditorStrings.storageNotDurable,
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      ),
    };
  }
}

/// A new PersistenceStatus.lastErrorAt → snack bar '저장 중 문제가 생겼어요',
/// at most once every 5 s (by the CORE error times). Separate from the
/// banner: one or two failures notify too.
class StorageErrorNotices extends ConsumerStatefulWidget {
  const StorageErrorNotices({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StorageErrorNotices> createState() =>
      _StorageErrorNoticesState();
}

const int _minNoticeGapMs = 5000;

class _StorageErrorNoticesState extends ConsumerState<StorageErrorNotices> {
  core.EpochMillis? _lastShown;

  void _onStatus(
    AsyncValue<core.PersistenceStatus>? previous,
    AsyncValue<core.PersistenceStatus> next,
  ) {
    final at = next.value?.lastErrorAt;
    if (at == null || at == previous?.value?.lastErrorAt) return;
    final last = _lastShown;
    if (last != null && at - last < _minNoticeGapMs) return;
    _lastShown = at;
    scheduleMicrotask(() {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(EditorStrings.storageErrorSnack)),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(core.persistenceStatusProvider, _onStatus);
    return widget.child;
  }
}
