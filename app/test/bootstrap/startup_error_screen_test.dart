// StartupErrorScreen and BootstrapFailure.userMessage
// (docs/plans/01-infra.md 4.5.4, 6.7, 9.1).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/startup_error_screen.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';

void _useIpad(WidgetTester tester, {bool landscape = false}) {
  tester.view
    ..physicalSize = landscape ? const Size(2752, 2064) : const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

BootstrapFailure _failure(
  Object error, {
  String moduleId = 'core',
  String moduleLabel = '노트 저장소 여는 중',
}) => BootstrapFailure(
  report: const StartupReport(steps: [], bootstrapElapsed: Duration.zero),
  moduleId: moduleId,
  moduleLabel: moduleLabel,
  error: error,
  stackTrace: StackTrace.empty,
);

NoteStoreOpenException _open(NoteStoreOpenFailure reason) =>
    NoteStoreOpenException(reason, 'open failed: ${reason.name}');

Future<void> _pump(
  WidgetTester tester, {
  required BootstrapFailure failure,
  String diagnostics = 'diag',
  VoidCallback? onRetry,
  Future<void> Function()? onResetLocalData,
  VoidCallback? onReload,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: StartupErrorScreen(
        failure: failure,
        diagnostics: diagnostics,
        onRetry: onRetry ?? () {},
        onResetLocalData: onResetLocalData,
        onReload: onReload,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('userMessage (6.7 table, 해요체)', () {
    final expected = <(String, Object), String>{
      ('storageUnavailable', _open(NoteStoreOpenFailure.storageUnavailable)):
          '이 브라우저에서는 저장소를 쓸 수 없어요. 개인정보 보호(비공개) 탭이라면 일반 탭이나 홈 화면 앱으로 열어 주세요.',
      ('migrationFailed', _open(NoteStoreOpenFailure.migrationFailed)):
          '저장된 데이터를 새 형식으로 바꾸지 못했어요. 진단 정보를 복사해 보내 주세요.',
      ('corrupted', _open(NoteStoreOpenFailure.corrupted)):
          '저장된 데이터가 손상되어 열 수 없어요. 진단 정보를 복사해 보내 주세요.',
      ('newerSchema', _open(NoteStoreOpenFailure.newerSchema)):
          '더 새로운 버전에서 저장한 데이터예요. 앱을 새로고침해 최신 버전을 받아 주세요.',
      ('unknown', _open(NoteStoreOpenFailure.unknown)):
          '저장소를 여는 중 문제가 생겼어요. 다시 시도해 주세요.',
      ('timeout', TimeoutException('slow', const Duration(seconds: 20))):
          '시작이 너무 오래 걸려요(노트 저장소 여는 중). 다시 시도해 주세요.',
      ('other', StateError('boom')): '앱을 시작하지 못했어요. 다시 시도해 주세요.',
    };
    for (final MapEntry(key: (name, error), value: message)
        in expected.entries) {
      testWidgets('$name → message on screen', (tester) async {
        _useIpad(tester);
        final failure = _failure(error);
        expect(failure.userMessage, message);
        await _pump(tester, failure: failure);
        expect(find.text('앱을 시작하지 못했어요'), findsOneWidget);
        expect(find.text(message), findsOneWidget);
      });
    }

    test('every NoteStoreOpenFailure has its own message', () {
      final messages = {
        for (final reason in NoteStoreOpenFailure.values)
          _failure(_open(reason)).userMessage,
      };
      expect(messages, hasLength(NoteStoreOpenFailure.values.length));
    });
  });

  testWidgets('retry button calls onRetry', (tester) async {
    _useIpad(tester);
    var retries = 0;
    await _pump(
      tester,
      failure: _failure(StateError('x')),
      onRetry: () => retries++,
    );
    await tester.tap(find.text(AppStrings.retry));
    expect(retries, 1);
  });

  testWidgets('details fold out with the module id and the error', (
    tester,
  ) async {
    _useIpad(tester);
    await _pump(
      tester,
      failure: _failure(StateError('disk on fire'), moduleId: 'core'),
    );
    expect(find.textContaining('disk on fire'), findsNothing);
    await tester.tap(find.text(AppStrings.startupDetails));
    await tester.pumpAndSettle();
    expect(find.text('모듈: core'), findsOneWidget);
    expect(find.textContaining('disk on fire'), findsOneWidget);
  });

  group('reload button', () {
    testWidgets('shown for newerSchema with onReload', (tester) async {
      _useIpad(tester);
      var reloads = 0;
      await _pump(
        tester,
        failure: _failure(_open(NoteStoreOpenFailure.newerSchema)),
        onReload: () => reloads++,
      );
      await tester.tap(find.text(AppStrings.reload));
      expect(reloads, 1);
    });

    testWidgets('hidden for newerSchema without onReload (not web)', (
      tester,
    ) async {
      _useIpad(tester);
      await _pump(
        tester,
        failure: _failure(_open(NoteStoreOpenFailure.newerSchema)),
      );
      expect(find.text(AppStrings.reload), findsNothing);
    });

    for (final error in <Object>[
      _open(NoteStoreOpenFailure.corrupted),
      _open(NoteStoreOpenFailure.storageUnavailable),
      TimeoutException('t'),
      StateError('s'),
    ]) {
      testWidgets('hidden for ${error.runtimeType} '
          '${error is NoteStoreOpenException ? error.reason.name : ''}', (
        tester,
      ) async {
        _useIpad(tester);
        await _pump(tester, failure: _failure(error), onReload: () {});
        expect(find.text(AppStrings.reload), findsNothing);
      });
    }
  });

  group('reset local data', () {
    testWidgets('hidden without a callback', (tester) async {
      _useIpad(tester);
      await _pump(
        tester,
        failure: _failure(_open(NoteStoreOpenFailure.corrupted)),
      );
      expect(find.text(AppStrings.resetLocalData), findsNothing);
    });

    testWidgets('two-step confirm; cancel at either step does nothing', (
      tester,
    ) async {
      _useIpad(tester);
      var resets = 0;
      await _pump(
        tester,
        failure: _failure(_open(NoteStoreOpenFailure.corrupted)),
        onResetLocalData: () async => resets++,
      );

      // Step 1 → cancel.
      await tester.tap(find.text(AppStrings.resetLocalData));
      await tester.pumpAndSettle();
      expect(
        find.text('이 기기에 저장된 노트·폴더·펜 설정이 모두 지워져요. 되돌릴 수 없어요.'),
        findsOneWidget,
      );
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(resets, 0);

      // Step 1 → continue, step 2 → cancel.
      await tester.tap(find.text(AppStrings.resetLocalData));
      await tester.pumpAndSettle();
      await tester.tap(find.text('계속'));
      await tester.pumpAndSettle();
      expect(find.text('정말 지울까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(resets, 0);

      // Both confirmed → reset once.
      await tester.tap(find.text(AppStrings.resetLocalData));
      await tester.pumpAndSettle();
      await tester.tap(find.text('계속'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('지우기'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(resets, 1);
      expect(find.text('데이터를 지우지 못했어요.'), findsNothing);
    });

    testWidgets('a failed reset shows "데이터를 지우지 못했어요."', (tester) async {
      _useIpad(tester);
      await _pump(
        tester,
        failure: _failure(_open(NoteStoreOpenFailure.corrupted)),
        onResetLocalData: () async => throw StateError('still open'),
      );
      await tester.tap(find.text(AppStrings.resetLocalData));
      await tester.pumpAndSettle();
      await tester.tap(find.text('계속'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('지우기'));
      await tester.pumpAndSettle();
      expect(find.text('데이터를 지우지 못했어요.'), findsOneWidget);
    });
  });

  testWidgets('copy diagnostics puts the text on the clipboard', (
    tester,
  ) async {
    _useIpad(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(
      tester,
      failure: _failure(StateError('x')),
      diagnostics: '[필기노트 진단 정보] test',
    );
    await tester.tap(find.text(AppStrings.copyDiagnostics));
    await tester.pumpAndSettle();
    expect(copied, '[필기노트 진단 정보] test');
    expect(find.text('진단 정보를 복사했어요.'), findsOneWidget);
  });

  for (final landscape in [false, true]) {
    testWidgets('all buttons fit (${landscape ? 'landscape' : 'portrait'})', (
      tester,
    ) async {
      _useIpad(tester, landscape: landscape);
      await _pump(
        tester,
        failure: _failure(_open(NoteStoreOpenFailure.newerSchema)),
        onReload: () {},
        onResetLocalData: () async {},
      );
      await tester.tap(find.text(AppStrings.startupDetails));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in [
        AppStrings.retry,
        AppStrings.copyDiagnostics,
        AppStrings.reload,
        AppStrings.resetLocalData,
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });
  }
}
