// installGlobalErrorHandlers / appErrorWidgetBuilder
// (docs/plans/01-infra.md 4.5.3, 6.7 and 9.1).

import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/errors/app_error_widget.dart';
import 'package:noteapp/src/errors/error_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('installGlobalErrorHandlers', () {
    late FlutterExceptionHandler? originalFlutter;
    late ErrorCallback? originalPlatform;
    late AppErrorLog log;
    late List<FlutterErrorDetails> chainedFlutter;
    late List<Object> chainedPlatform;
    late VoidCallback restore;

    setUp(() {
      originalFlutter = FlutterError.onError;
      originalPlatform = PlatformDispatcher.instance.onError;
      chainedFlutter = [];
      chainedPlatform = [];
      // Stand-ins for whatever was installed before (chained after logging).
      FlutterError.onError = chainedFlutter.add;
      PlatformDispatcher.instance.onError = (error, stack) {
        chainedPlatform.add(error);
        return false;
      };
      log = AppErrorLog();
      restore = installGlobalErrorHandlers(log, presentToConsole: false);
    });

    tearDown(() {
      restore();
      FlutterError.onError = originalFlutter;
      PlatformDispatcher.instance.onError = originalPlatform;
    });

    test('FlutterError.reportError is logged, then chained', () {
      final details = FlutterErrorDetails(
        exception: StateError('build failed'),
        library: 'feature_library',
      );
      FlutterError.reportError(details);
      expect(log.records.single.source, AppErrorSource.flutter);
      expect(log.records.single.summary, 'Bad state: build failed');
      expect(log.records.single.details, contains('feature_library'));
      expect(chainedFlutter, [same(details)]);
    });

    test('PlatformDispatcher.onError is logged, chained and handled', () {
      final handled = PlatformDispatcher.instance.onError!(
        Exception('async'),
        StackTrace.fromString('#0 zone'),
      );
      expect(handled, isTrue);
      expect(log.records.single.source, AppErrorSource.platform);
      expect(log.records.single.summary, 'Exception: async');
      expect(log.records.single.stackTrace, '#0 zone');
      expect(chainedPlatform.single, isA<Exception>());
    });

    test('the restore callback puts the previous handlers back', () {
      final ourFlutter = FlutterError.onError;
      final ourPlatform = PlatformDispatcher.instance.onError;
      final ourBuilder = ErrorWidget.builder;
      restore();
      expect(FlutterError.onError, isNot(same(ourFlutter)));
      expect(PlatformDispatcher.instance.onError, isNot(same(ourPlatform)));
      FlutterError.reportError(FlutterErrorDetails(exception: 'after'));
      expect(log.records, isEmpty);
      expect(chainedFlutter.single.exception, 'after');
      // Not release mode: the error widget builder was left alone.
      expect(ErrorWidget.builder, same(ourBuilder));
    });
  });

  testWidgets('appErrorWidgetBuilder shows the grey box text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (_) => appErrorWidgetBuilder(
              FlutterErrorDetails(exception: Exception('x')),
            ),
          ),
        ),
      ),
    );
    expect(find.text(AppStrings.errorWidgetMessage), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('appErrorWidgetBuilder works without MaterialApp', (
    tester,
  ) async {
    await tester.pumpWidget(
      appErrorWidgetBuilder(FlutterErrorDetails(exception: Exception('x'))),
    );
    expect(find.text('이 부분을 표시하지 못했어요'), findsOneWidget);
  });
}
