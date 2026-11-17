/// (v2.17-md, C217M-11 · 12 · 15 · 16 — docs/plans/m5-7/08-markdown.md 10) The app's MD 문서
/// flows behind the slots of feature_library and feature_markdown:
///
/// - 'MD 가져오기': pdf_io's text file picker (md / markdown / txt, several at once, at
///   most [MarkdownLimits.maxImportFiles]) → CORE MarkdownImport.decode → one MD 문서 per
///   file, in the library's folder. One imported → it opens; several → 'MD 문서 N개를
///   가져왔어요' (+ the refused ones and why).
/// - '.md로 내보내기' (library ⋯ and the screen's ⋯): the text byte for byte
///   (`utf8.encode(text)`), named `PdfFileNaming.sanitize(title)` + '.md', through
///   pdf_io's DocumentFileOutput — a small sheet [공유] [저장] (web [공유] [다운로드]).
///   Share sends text/plain (named .md), save / download text/markdown.
/// - Links of the screen: no opener here (open question Q1 of 08-markdown 18 is not
///   decided) — markdownOpenLinkProvider stays null and the link sheet offers 복사 only.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:ui_kit/ui_kit.dart';

import 'document_share.dart';

/// Messages of the MD 문서 flows.
abstract final class MarkdownWiringStrings {
  static String imported(int n) => 'MD 문서 $n개를 가져왔어요';
  static String refused(int n) => '$n개는 가져오지 못했어요';
  static String onlyFirst(int max) => '파일은 한 번에 $max개까지 가져올 수 있어요';
  static const String tooLarge = '파일이 너무 커요 (최대 400 KB)';
  static const String notText = '텍스트 파일이 아니에요';
  static const String notUtf8 =
      'UTF-8 텍스트 파일만 가져올 수 있어요 — 메모장에서 UTF-8로 저장한 뒤 다시 가져와 주세요';
  static const String noTextFile = '.md · .markdown · .txt 파일만 가져올 수 있어요';
  static const String importFailed = '가져오지 못했어요';
  static const String exportTitle = '.md로 내보내기';
  static const String exportFailed = '내보내지 못했어요';
  static const String exportDone = '내보냈어요';
  static const String exportUnavailable = '이 기기에서는 내보낼 수 없어요';
  static const String noBody = '아직 내용을 받지 못한 문서는 내보낼 수 없어요';
  static const String missing = '문서를 찾을 수 없어요';

  static String reason(MarkdownDecodeFailure f) => switch (f) {
    MarkdownDecodeFailure.tooLarge => tooLarge,
    MarkdownDecodeFailure.notText => notText,
    MarkdownDecodeFailure.notUtf8 => notUtf8,
  };
}

/// The export file of an MD 문서 (10.4): exactly the text's UTF-8 bytes.
DocumentFile markdownDocumentFile({
  required String title,
  required String text,
}) {
  var name = PdfFileNaming.sanitize(title);
  if (name.isEmpty) name = MarkdownImport.fallbackTitle;
  final lower = name.toLowerCase();
  if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) name = '$name.md';
  return DocumentFile(
    name: name,
    bytes: Uint8List.fromList(utf8.encode(text)),
    mimeType: 'text/markdown',
    shareMimeType: 'text/plain',
  );
}

/// A picked file that was not imported, and why.
typedef MarkdownImportRefusal = ({String name, String reason});

/// What one 'MD 가져오기' did. [refused] has one entry per file (two files of the same
/// name count twice).
typedef MarkdownImportOutcome = ({
  List<NoteId> created,
  List<MarkdownImportRefusal> refused,
  bool cut,
});

/// Decodes and creates the picked [files] (at most maxImportFiles) in [folderId].
@visibleForTesting
Future<MarkdownImportOutcome> importMarkdownFiles(
  MarkdownRepository repo,
  List<PickedTextFile> files, {
  required FolderId? folderId,
}) async {
  final created = <NoteId>[];
  final refused = <MarkdownImportRefusal>[];
  void refuse(PickedTextFile f, String reason) =>
      refused.add((name: f.name, reason: reason));
  final take = files.take(MarkdownLimits.maxImportFiles);
  for (final f in take) {
    if (!FilePickerTextSource.hasTextExtension(f.name)) {
      refuse(f, MarkdownWiringStrings.noTextFile);
      continue;
    }
    final size = f.sizeBytes;
    if (size != null && size > MarkdownLimits.maxTextBytes) {
      refuse(f, MarkdownWiringStrings.tooLarge);
      continue;
    }
    try {
      final decoded = MarkdownImport.decode(
        await f.readBytes(),
        fileName: f.name,
      );
      if (decoded.failure case final failure?) {
        refuse(f, MarkdownWiringStrings.reason(failure));
        continue;
      }
      final note = await repo.create(
        folderId: folderId,
        title: decoded.title!,
        text: decoded.text!,
      );
      created.add(note.id);
    } on MarkdownTooLargeException {
      refuse(f, MarkdownWiringStrings.tooLarge);
    } on Object {
      refuse(f, MarkdownWiringStrings.importFailed);
    }
  }
  return (
    created: created,
    refused: refused,
    cut: files.length > MarkdownLimits.maxImportFiles,
  );
}

/// Refused files named in a message.
const int _namedRefusals = 3;

/// The message after an import (null: one document opens, nothing to say). Names the
/// refused files (up to three, then '외 N개') with each reason.
@visibleForTesting
String? markdownImportMessage(MarkdownImportOutcome o) {
  final refused = o.refused;
  String named() {
    final shown = [
      for (final r in refused.take(_namedRefusals)) '${r.name}: ${r.reason}',
    ];
    final more = refused.length - shown.length;
    return [...shown, if (more > 0) '외 $more개'].join(', ');
  }

  final parts = <String>[
    if (o.created.length > 1) MarkdownWiringStrings.imported(o.created.length),
    if (refused.isNotEmpty)
      refused.length == 1 && o.created.isEmpty
          ? '${refused.single.name}: ${refused.single.reason}'
          : '${MarkdownWiringStrings.refused(refused.length)} — ${named()}',
    if (o.cut) MarkdownWiringStrings.onlyFirst(MarkdownLimits.maxImportFiles),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// A floating snack bar that replaces the current one (the library's look, 05-library
/// 6.11); longer for import results that name files.
void _snack(ScaffoldMessengerState? messenger, String message) {
  if (messenger == null || !messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: message.length > 60 ? 8 : 4),
      ),
    );
}

/// libraryMarkdownImportActionProvider (C217M-11). The picker opens synchronously (web
/// user activation): nothing is awaited before it.
LibraryMarkdownImportAction markdownImportAction({
  TextFileSource source = const FilePickerTextSource(),
}) => (context, {folderId}) async {
  final picking = source.pickTextFiles();
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final List<PickedTextFile>? files;
  try {
    files = await picking;
  } on Object {
    _snack(messenger, MarkdownWiringStrings.importFailed);
    return null;
  }
  if (files == null) return null; // cancelled
  if (files.isEmpty) {
    _snack(messenger, MarkdownWiringStrings.noTextFile);
    return null;
  }
  final outcome = await importMarkdownFiles(
    container.read(markdownRepositoryProvider),
    files,
    folderId: folderId,
  );
  if (markdownImportMessage(outcome) case final message?) {
    _snack(messenger, message);
  }
  return outcome.created.length == 1 ? outcome.created.single : null;
};

/// The sheet of '.md로 내보내기': one button per available action of [output]. The
/// action runs in the button's tap handler (web: navigator.share / download need the
/// user activation of that tap).
Future<void> exportMarkdownText(
  BuildContext context, {
  required String title,
  required String text,
  DocumentFileOutput? output,
}) async {
  final out =
      output ?? createPlatformDocumentOutput(share: platformDocumentShare);
  final file = markdownDocumentFile(title: title, text: text);
  final actions = out.availableActions(file);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (actions.isEmpty) {
    _snack(messenger, MarkdownWiringStrings.exportUnavailable);
    return;
  }
  final outcome = await showModalBottomSheet<Future<PdfOutputOutcome>>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: const Text(MarkdownWiringStrings.exportTitle),
            subtitle: Text(file.name),
          ),
          for (final action in [
            DocumentOutputAction.share,
            DocumentOutputAction.save,
          ])
            if (actions.contains(action))
              ListTile(
                key: Key('md.export.${action.name}'),
                leading: AppIcon(
                  action == DocumentOutputAction.share
                      ? AppIconKind.share
                      : AppIconKind.exportMarkdown,
                ),
                title: Text(out.labelOf(action)),
                // Called in the tap handler; the sheet closes with the result.
                onTap: () => Navigator.of(sheet).pop(out.deliver(file, action)),
              ),
        ],
      ),
    ),
  );
  if (outcome == null) return;
  final result = await outcome;
  switch (result) {
    case PdfOutputOutcome.done:
    case PdfOutputOutcome.dismissedByUser:
      break;
    case PdfOutputOutcome.unsupported:
      _snack(messenger, MarkdownWiringStrings.exportUnavailable);
    case PdfOutputOutcome.failed || PdfOutputOutcome.needsUserGesture:
      _snack(messenger, MarkdownWiringStrings.exportFailed);
  }
}

/// libraryMarkdownExportActionProvider (C217M-11): the stored text of [noteId].
LibraryMarkdownExportAction markdownLibraryExportAction({
  DocumentFileOutput? output,
}) => (context, noteId) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final doc = await container.read(markdownRepositoryProvider).get(noteId);
  if (doc == null) {
    _snack(messenger, MarkdownWiringStrings.missing);
    return;
  }
  if (!doc.bodyPresent) {
    _snack(messenger, MarkdownWiringStrings.noBody);
    return;
  }
  if (!context.mounted) return;
  await exportMarkdownText(
    context,
    title: doc.note.title,
    text: doc.text,
    output: output,
  );
};
