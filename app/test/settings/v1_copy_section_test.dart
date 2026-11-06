// V1CopySection (docs/plans/m5-7/01-infra.md 4.6.7, 6.18; contract 7.2.7
// v2.1 — CD2-23, CORE CP-17): a fake V1CopyApi through the section
// constructor. Five states (copy — web and native names · failed — quota /
// io / other · none · pending — UnimplementedError, no record · error — one
// record), the export two-step flow (chunks joined into the sheet's
// BackupFile with info.fileName and v1CopyMimeType, [취소], stream error),
// and delete (confirm → delete once → info again; cancel; error).
// The default api (the CORE B2-α declarations) on the fake store → '사본 없음'.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/dev_tools.dart' show V1DatabaseCopyInfo;
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/settings/backup_sheet.dart';
import 'package:noteapp/src/settings/v1_copy_section.dart';

import '../fakes/fake_web_platform.dart';
import '../support/settings_harness.dart';

const int _mib = 1024 * 1024;
const String _webName = 'noteapp-v1-backup.sql.txt';
const String _nativeName = 'noteapp-v1-backup.sqlite';

const ValueKey<String> _export = ValueKey<String>('app.v1Copy.export');
const ValueKey<String> _delete = ValueKey<String>('app.v1Copy.delete');
const ValueKey<String> _cancel = ValueKey<String>('app.v1Copy.cancel');
const ValueKey<String> _progress = ValueKey<String>('app.v1Copy.progress');
const ValueKey<String> _deleteConfirm = ValueKey<String>(
  'app.v1Copy.delete.confirm',
);
const ValueKey<String> _deleteCancel = ValueKey<String>(
  'app.v1Copy.delete.cancel',
);

V1DatabaseCopyInfo _copy({
  String fileName = _webName,
  int bytes = 8 * _mib + 1,
  String? failure,
}) => V1DatabaseCopyInfo(
  createdAt: DateTime(2026, 11, 6, 9, 41, 30).millisecondsSinceEpoch,
  bytes: failure == null ? bytes : 0,
  normalOpens: 2,
  fileName: fileName,
  failure: failure,
);

/// The CP-17 calls with scripted answers.
final class _FakeApi {
  /// info() answers from [infos] in order (the last repeats); an Error is
  /// thrown.
  List<Object?> infos = [null];
  int infoCalls = 0;
  StreamController<Uint8List>? reading;
  int readCalls = 0;
  int deleteCalls = 0;
  Error? deleteError;
  Completer<void>? deleteGate;
  final List<NoteStore> stores = [];

  /// Closes the last read stream (tests that leave it open).
  Future<void> close() async => reading?.close();

  V1CopyApi get api => V1CopyApi(
    info: (store) async {
      stores.add(store);
      final answer =
          infos[infoCalls < infos.length ? infoCalls : infos.length - 1];
      infoCalls++;
      if (answer == null || answer is V1DatabaseCopyInfo) {
        return answer as V1DatabaseCopyInfo?;
      }
      throw answer as Error;
    },
    read: (store) {
      readCalls++;
      reading = StreamController<Uint8List>();
      return reading!.stream;
    },
    delete: (store) async {
      deleteCalls++;
      await deleteGate?.future;
      if (deleteError case final error?) throw error;
    },
  );
}

Future<SettingsHarness> _pump(
  WidgetTester tester,
  _FakeApi fake, {
  FakeWebPlatform? web,
  Size logical = ipadPortrait,
}) async {
  final harness = SettingsHarness(web: web);
  await harness.pump(
    tester,
    sectionPage(V1CopySection(api: fake.api)),
    logical: logical,
  );
  await tester.pump();
  return harness;
}

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).enabled;

void main() {
  test('v1CopyMimeType: .sqlite, .txt, anything else', () {
    expect(v1CopyMimeType(_nativeName), 'application/vnd.sqlite3');
    expect(v1CopyMimeType(_webName), 'text/plain');
    expect(v1CopyMimeType('noteapp-v1-backup.db'), 'application/octet-stream');
    expect(v1CopyMimeType('COPY.SQLITE'), 'application/vnd.sqlite3');
  });

  group('states', () {
    testWidgets('copy — web name: date, size, opens, file name, two buttons', (
      tester,
    ) async {
      final fake = _FakeApi()..infos = [_copy(bytes: 12 * _mib + 300 * 1024)];
      final h = await _pump(tester, fake);
      expect(
        find.text('사본 있음: 2026-11-06 09:41 · 12.3 MB · 정상 열기 2번'),
        findsOneWidget,
      );
      expect(find.text(_webName), findsOneWidget);
      expect(find.byKey(_export), findsOneWidget);
      expect(find.byKey(_delete), findsOneWidget);
      expect(find.text(AppStrings.v1CopyExport), findsOneWidget);
      expect(find.text(AppStrings.v1CopyDelete), findsOneWidget);
      // The section asks with the app's store.
      expect(fake.stores.single, same(h.store));
      expect(h.errorLog.totalCount, 0);
    });

    testWidgets('copy — native name', (tester) async {
      final fake = _FakeApi()..infos = [_copy(fileName: _nativeName)];
      await _pump(tester, fake);
      expect(find.text(_nativeName), findsOneWidget);
      expect(find.byKey(_export), findsOneWidget);
    });

    testWidgets('failed: quota · io · other (and an unknown code) → the '
        'sentence, no buttons', (tester) async {
      for (final (code, reason) in [
        ('quota', '저장 공간 부족'),
        ('io', '읽기·쓰기 오류'),
        ('other', '알 수 없는 오류'),
        ('mystery', '알 수 없는 오류'),
      ]) {
        final fake = _FakeApi()..infos = [_copy(failure: code)];
        final h = await _pump(tester, fake);
        expect(
          find.text('사본을 만들지 못했어요($reason) — 이전 판 데이터는 새 판으로 옮겨졌어요'),
          findsOneWidget,
          reason: code,
        );
        expect(find.byKey(_export), findsNothing);
        expect(find.byKey(_delete), findsNothing);
        expect(h.errorLog.totalCount, 0);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('none (null) → 사본 없음, no buttons', (tester) async {
      final fake = _FakeApi()..infos = [null];
      await _pump(tester, fake);
      expect(find.text(AppStrings.v1CopyNone), findsOneWidget);
      expect(find.text('사본 없음'), findsOneWidget);
      expect(find.byKey(_export), findsNothing);
    });

    testWidgets('pending: UnimplementedError(CORE T24) → no buttons, no '
        'record', (tester) async {
      final fake = _FakeApi()..infos = [UnimplementedError('CORE T24')];
      final h = await _pump(tester, fake);
      expect(find.text('이 판의 저장소에서는 아직 볼 수 없어요'), findsOneWidget);
      expect(find.byKey(_export), findsNothing);
      expect(h.errorLog.totalCount, 0);
    });

    testWidgets('error: any other exception → the note + one record', (
      tester,
    ) async {
      final fake = _FakeApi()..infos = [StateError('kv read failed')];
      final h = await _pump(tester, fake);
      expect(find.text(AppStrings.v1CopyInfoError), findsOneWidget);
      expect(find.byKey(_export), findsNothing);
      expect(h.errorLog.totalCount, 1);
      final record = h.errorLog.records.single;
      expect(record.source, AppErrorSource.manual);
      expect(record.summary, contains('kv read failed'));
      expect(record.details, 'v1DatabaseCopyInfo failed');
    });

    testWidgets('loading line until info() answers', (tester) async {
      final gate = Completer<V1DatabaseCopyInfo?>();
      final h = SettingsHarness();
      await h.pump(
        tester,
        sectionPage(
          V1CopySection(
            api: V1CopyApi(
              info: (_) => gate.future,
              read: (_) => const Stream.empty(),
              delete: (_) async {},
            ),
          ),
        ),
      );
      expect(find.text(AppStrings.v1CopyLoading), findsOneWidget);
      gate.complete(null);
      await tester.pump();
      expect(find.text(AppStrings.v1CopyNone), findsOneWidget);
    });

    testWidgets('asked each time the section is shown', (tester) async {
      final fake = _FakeApi();
      await _pump(tester, fake);
      expect(fake.infoCalls, 1);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, fake);
      expect(fake.infoCalls, 2);
    });

    testWidgets('the default api (CORE B2-α declarations) on the fake store '
        '→ 사본 없음', (tester) async {
      final h = SettingsHarness();
      await h.pump(tester, sectionPage(const V1CopySection()));
      await tester.pump();
      expect(find.text(AppStrings.v1CopyNone), findsOneWidget);
      expect(h.errorLog.totalCount, 0);
    });

    testWidgets('landscape: rows and buttons fit', (tester) async {
      final fake = _FakeApi()..infos = [_copy(fileName: _nativeName)];
      await _pump(tester, fake, logical: ipadLandscape);
      expect(find.byKey(_export), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('내보내기', () {
    for (final name in [_webName, _nativeName]) {
      testWidgets('$name: 4 MiB + 4 MiB + 1 B → one BackupFile '
          '(bytes joined, info.fileName, v1CopyMimeType) → download', (
        tester,
      ) async {
        final web = FakeWebPlatform();
        final fake = _FakeApi()..infos = [_copy(fileName: name)];
        await _pump(tester, fake, web: web);

        await tester.tap(find.byKey(_export));
        await tester.pump();
        expect(fake.readCalls, 1);
        expect(find.byKey(_progress), findsOneWidget);
        expect(find.text('준비 중… 0 MB / 8.0 MB'), findsOneWidget);
        // Both buttons are disabled while preparing.
        expect(_enabled(tester, _export), isFalse);
        expect(_enabled(tester, _delete), isFalse);

        final a = Uint8List(4 * _mib)..fillRange(0, 4 * _mib, 1);
        final b = Uint8List(4 * _mib)..fillRange(0, 4 * _mib, 2);
        final c = Uint8List.fromList([3]);
        fake.reading!.add(a);
        await tester.pump();
        expect(find.text('준비 중… 4.0 MB / 8.0 MB'), findsOneWidget);
        fake.reading!
          ..add(b)
          ..add(c);
        await tester.pump();
        expect(find.byType(BackupReadySheet), findsNothing);
        await fake.reading!.close();
        await tester.pumpAndSettle();

        expect(find.byType(BackupReadySheet), findsOneWidget);
        expect(find.byKey(_progress), findsNothing);
        final sheet = tester.widget<BackupReadySheet>(
          find.byType(BackupReadySheet),
        );
        expect(sheet.file.fileName, name);
        expect(sheet.file.mimeType, v1CopyMimeType(name));
        expect(sheet.file.bytes.length, 8 * _mib + 1);
        expect(sheet.file.bytes[0], 1);
        expect(sheet.file.bytes[4 * _mib - 1], 1);
        expect(sheet.file.bytes[4 * _mib], 2);
        expect(sheet.file.bytes[8 * _mib - 1], 2);
        expect(sheet.file.bytes.last, 3);

        await tester.tap(find.byKey(const Key('backup-download')));
        await tester.pumpAndSettle();
        final download = web.downloads.single;
        expect(download.fileName, name);
        expect(download.mimeType, v1CopyMimeType(name));
        expect(download.bytes, same(sheet.file.bytes));
        expect(find.text(AppStrings.backupDownloaded), findsOneWidget);
        // Back to the copy state, buttons enabled.
        expect(_enabled(tester, _export), isTrue);
      });
    }

    testWidgets('[취소] while preparing → the subscription ends, no sheet, '
        'nothing written', (tester) async {
      final web = FakeWebPlatform();
      final fake = _FakeApi()..infos = [_copy()];
      final h = await _pump(tester, fake, web: web);
      await tester.tap(find.byKey(_export));
      await tester.pump();
      fake.reading!.add(Uint8List(_mib));
      await tester.pump();
      expect(fake.reading!.hasListener, isTrue);

      await tester.tap(find.byKey(_cancel));
      await tester.pumpAndSettle();
      expect(fake.reading!.hasListener, isFalse);
      expect(find.byKey(_progress), findsNothing);
      expect(find.byType(BackupReadySheet), findsNothing);
      expect(web.downloads, isEmpty);
      expect(_enabled(tester, _export), isTrue);
      expect(h.errorLog.totalCount, 0);
    });

    testWidgets('stream error → 사본을 읽지 못했어요 + one record, no sheet', (
      tester,
    ) async {
      final fake = _FakeApi()..infos = [_copy()];
      final h = await _pump(tester, fake);
      await tester.tap(find.byKey(_export));
      await tester.pump();
      fake.reading!
        ..add(Uint8List(16))
        ..addError(StateError('This store has no v1 database copy'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.v1CopyReadFailed), findsOneWidget);
      expect(find.byType(BackupReadySheet), findsNothing);
      expect(find.byKey(_progress), findsNothing);
      expect(h.errorLog.totalCount, 1);
      expect(h.errorLog.records.single.details, 'readV1DatabaseCopy failed');
      expect(_enabled(tester, _export), isTrue);
    });

    testWidgets('leaving the section while preparing cancels the reading', (
      tester,
    ) async {
      final fake = _FakeApi()..infos = [_copy()];
      await _pump(tester, fake);
      await tester.tap(find.byKey(_export));
      await tester.pump();
      expect(fake.reading!.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(fake.reading!.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('지우기', () {
    testWidgets('confirm → delete once → info again → 사본 없음', (tester) async {
      final fake = _FakeApi()..infos = [_copy(), null];
      final h = await _pump(tester, fake);
      expect(fake.infoCalls, 1);
      fake.deleteGate = Completer<void>();

      await tester.tap(find.byKey(_delete));
      await tester.pumpAndSettle();
      expect(find.text('이전 판 DB 사본을 지워요. 되돌릴 수 없어요.'), findsOneWidget);
      await tester.tap(find.byKey(_deleteConfirm));
      await tester.pump();
      expect(fake.deleteCalls, 1);
      // Both buttons are disabled while deleting.
      expect(_enabled(tester, _export), isFalse);
      expect(_enabled(tester, _delete), isFalse);

      fake.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(fake.infoCalls, 2);
      expect(find.text(AppStrings.v1CopyNone), findsOneWidget);
      expect(find.byKey(_delete), findsNothing);
      expect(h.errorLog.totalCount, 0);
    });

    testWidgets('취소 → no delete', (tester) async {
      final fake = _FakeApi()..infos = [_copy()];
      await _pump(tester, fake);
      await tester.tap(find.byKey(_delete));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_deleteCancel));
      await tester.pumpAndSettle();
      expect(fake.deleteCalls, 0);
      expect(fake.infoCalls, 1);
      expect(find.byKey(_delete), findsOneWidget);
    });

    testWidgets('delete error → 사본을 지우지 못했어요 + one record; the copy '
        'stays', (tester) async {
      final fake = _FakeApi()
        ..infos = [_copy()]
        ..deleteError = StateError('unlink failed');
      final h = await _pump(tester, fake);
      await tester.tap(find.byKey(_delete));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_deleteConfirm));
      await tester.pumpAndSettle();
      expect(fake.deleteCalls, 1);
      expect(find.text(AppStrings.v1CopyDeleteFailed), findsOneWidget);
      expect(h.errorLog.totalCount, 1);
      expect(h.errorLog.records.single.details, 'deleteV1DatabaseCopy failed');
      expect(_enabled(tester, _delete), isTrue);
      expect(fake.infoCalls, 1);
    });
  });
}
