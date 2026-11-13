// lib/src/ui/content/ink_search_hint.dart — (handwriting search, 05-library
// 6.19a) one short line on why handwriting is not found yet, with its
// action, under the search results and in the empty search state:
//   auto indexing off  → "손글씨도 검색하려면 '검색용 자동 인식'을 켜 주세요" [켜기]
//   model missing      → "… 인식 모델(약 20MB)을 받아야 해요" [지금 받기]
//   downloading        → "손글씨 인식 모델을 받는 중이에요"
//   waiting for Wi-Fi  → "… 받는 중이에요 (Wi-Fi에서만 받아요)" [지금 받기] —
//                        two presses (the cellular warning first, like the
//                        model rows); worded so it is not wrong on Wi-Fi
//   unsupported        → "이 기기에서는 손글씨 검색을 쓸 수 없어요"
//   failed             → "… 받지 못했어요" [지금 받기]
//   indexing           → "손글씨를 읽는 중이에요 (n쪽 남음)" (no count while
//                        the pages are still being counted)
// Nothing without the slot (libraryInkSearchProvider null) or when ready.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../integration/ink_search_slot.dart';
import '../../l10n/library_strings.dart';

abstract final class InkSearchHintKeys {
  static const ValueKey<String> hint = ValueKey('library.search.inkHint');
  static const ValueKey<String> action = ValueKey(
    'library.search.inkHint.action',
  );
}

class InkSearchHint extends ConsumerWidget {
  const InkSearchHint({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = ref.watch(libraryInkSearchProvider);
    if (slot == null) return const SizedBox.shrink();
    return ValueListenableBuilder<LibraryInkSearchState>(
      valueListenable: slot.state,
      builder: (context, state, _) => state.phase == LibraryInkSearchPhase.ready
          ? const SizedBox.shrink()
          : Padding(
              padding: padding,
              child: _HintLine(
                key: InkSearchHintKeys.hint,
                slot: slot,
                state: state,
              ),
            ),
    );
  }
}

class _HintLine extends StatefulWidget {
  const _HintLine({super.key, required this.slot, required this.state});

  final LibraryInkSearch slot;
  final LibraryInkSearchState state;

  @override
  State<_HintLine> createState() => _HintLineState();
}

class _HintLineState extends State<_HintLine> {
  /// The first [지금 받기] of a cellular download was pressed.
  bool _confirming = false;

  @override
  void didUpdateWidget(_HintLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.phase != widget.state.phase) _confirming = false;
  }

  /// [지금 받기] would use cellular data now: waiting for Wi-Fi, or an
  /// engine that does not wait for it with Wi-Fi only on.
  bool get _cellular =>
      widget.state.phase == LibraryInkSearchPhase.waitingForWifi ||
      widget.state.confirmCellularFirst;

  void _download() {
    if (_cellular && !_confirming) {
      setState(() => _confirming = true);
      return;
    }
    final cellular = _cellular;
    setState(() => _confirming = false);
    widget.slot.downloadModel(cellular: cellular);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final (
      String text,
      String? action,
      VoidCallback? onAction,
    ) = switch (state.phase) {
      LibraryInkSearchPhase.autoIndexOff => (
        LibraryStrings.inkAutoIndexOff,
        LibraryStrings.inkTurnOn,
        widget.slot.turnOnAutoIndex,
      ),
      LibraryInkSearchPhase.modelMissing => (
        _confirming
            ? LibraryStrings.inkCellularConfirm
            : LibraryStrings.inkModelMissing,
        LibraryStrings.inkDownloadNow,
        _download,
      ),
      LibraryInkSearchPhase.waitingForWifi => (
        _confirming
            ? LibraryStrings.inkCellularConfirm
            : LibraryStrings.inkWaitingForWifi,
        LibraryStrings.inkDownloadNow,
        _download,
      ),
      LibraryInkSearchPhase.modelFailed => (
        _confirming
            ? LibraryStrings.inkCellularConfirm
            : LibraryStrings.inkModelFailed,
        LibraryStrings.inkDownloadNow,
        _download,
      ),
      LibraryInkSearchPhase.modelDownloading => (
        LibraryStrings.inkModelDownloading,
        null,
        null,
      ),
      LibraryInkSearchPhase.indexing => (
        LibraryStrings.inkIndexing(state.remainingPages),
        null,
        null,
      ),
      LibraryInkSearchPhase.unsupported => (
        LibraryStrings.inkUnsupported,
        null,
        null,
      ),
      LibraryInkSearchPhase.ready => ('', null, null),
    };
    final theme = Theme.of(context);
    final busy =
        state.phase == LibraryInkSearchPhase.indexing ||
        state.phase == LibraryInkSearchPhase.modelDownloading;
    return Row(
      children: [
        Icon(
          busy ? Icons.hourglass_empty : Icons.draw_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 8),
          TextButton(
            key: InkSearchHintKeys.action,
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            onPressed: onAction,
            child: Text(action),
          ),
        ],
      ],
    );
  }
}
