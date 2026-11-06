// lib/src/ui/draft_download.dart — the web '파일로 내려받기' two steps (m5-7/06-pdf 6.10.4, D19 —
// 검토 S-5; PDF T36b). Internal.
//
// ① [파일로 내려받기]: readAll → (WebM) the head patch → Blob + object URL (the byte reference is
// dropped once the Blob exists) → the button becomes [저장하기]. ② [저장하기]: the link is clicked
// synchronously inside the tap. The URL is revoked when the button goes away (sheet / panel
// closed). The draft is never deleted here ([지우기] decides).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../platform/file_download.dart';
import '../record/buffer_ledger.dart';
import '../record/recording_output.dart';
import 'strings_ko.dart';

/// Step ① for [draft]: its bytes (WebM: Info > Duration patched from the timeline, the clock
/// value when that fails) as a prepared download named like the saved asset (6.6.3).
Future<PreparedFileDownload?> prepareDraftDownload(
  core.NoteStore store,
  FileDownloads downloads,
  core.RecordingDraft draft,
) async {
  var bytes = await store.recordingDrafts.readAll(draft.draftId);
  if (bytes.isEmpty) return null;
  if (isWebmMime(draft.mimeType)) {
    final measured = await measureRecording(
      bytes,
      mimeType: draft.mimeType,
      clockMs: draft.activeMs,
    );
    final ledger = BufferLedger();
    final out = patchRecordingHead(
      bytes,
      mimeType: draft.mimeType,
      durationMs: measured.durationMs,
      hold: ledger.hold(bytes.length),
      ledger: ledger,
    );
    bytes = out.bytes;
    ledger.release(out.hold);
  }
  return downloads.prepare(
    bytes,
    mimeType: draft.mimeType,
    fileName: recordingFileName(draft.startedAt, draft.mimeType),
  );
}

class DraftDownloadButton extends StatefulWidget {
  const DraftDownloadButton({super.key, required this.prepare, this.onError});

  /// Step ① (called on the first tap).
  final Future<PreparedFileDownload?> Function() prepare;
  final void Function(Object error, StackTrace stack)? onError;

  @override
  State<DraftDownloadButton> createState() => _DraftDownloadButtonState();
}

class _DraftDownloadButtonState extends State<DraftDownloadButton> {
  PreparedFileDownload? _prepared;
  bool _preparing = false;

  Future<void> _prepare() async {
    setState(() => _preparing = true);
    PreparedFileDownload? prepared;
    try {
      prepared = await widget.prepare();
    } on Object catch (e, s) {
      widget.onError?.call(e, s);
    }
    if (!mounted) {
      prepared?.revoke();
      return;
    }
    setState(() {
      _preparing = false;
      _prepared = prepared;
    });
  }

  /// Step ②: synchronous in the tap handler (no await before save).
  void _save() => _prepared?.save();

  @override
  void dispose() {
    _prepared?.revoke();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prepared = _prepared;
    if (prepared != null) {
      return TextButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save_alt),
        label: const Text(MediaStringsKo.saveFile),
      );
    }
    return TextButton.icon(
      onPressed: _preparing ? null : _prepare,
      icon: _preparing
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download),
      label: const Text(MediaStringsKo.downloadFile),
    );
  }
}
