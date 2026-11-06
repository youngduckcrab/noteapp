// resolveNativeStoragePaths (J4 — docs/plans/m5-7/01-infra.md 4.6.3, 6.9;
// contract 00-overview 7.2.6 v2.1 공통-1): the path strings, the
// `<support>/noteapp/` folder it creates (recursive, idempotent — the
// `assets/` folder and the files are CORE's), and every failure passed on.
//
// The app does not depend on path_provider_platform_interface (contract 7.5),
// so PathProviderPlatform.instance is not replaced: its default
// implementation talks to the `plugins.flutter.io/path_provider` method
// channel, which this test answers through the test binary messenger
// (`flutter test` registers no Dart plugin, so no real platform answers).
// The last group runs the DEFAULT CoreModule (nativePaths =
// resolveNativeStoragePaths) on that channel.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/storage/native_storage_paths.dart';
import 'package:path_provider/path_provider.dart'
    show MissingPlatformDirectoryException;

import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_web_platform.dart';

const _channel = MethodChannel('plugins.flutter.io/path_provider');

/// Answers getApplicationSupportDirectory with [answer] (null → the
/// platform has no such directory; a thrown PlatformException → a channel
/// error). Returns the method names the channel received.
List<String> _answerSupportDirectory(Object? Function() answer) {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        if (call.method != 'getApplicationSupportDirectory') {
          throw MissingPluginException(call.method);
        }
        return answer();
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('noteapp_paths_');
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  group('resolveNativeStoragePaths (native side on the VM)', () {
    test(
      '<support>/noteapp/noteapp.sqlite and <support>/noteapp/assets; '
      'the noteapp/ folder exists afterwards, assets/ is left to CORE',
      () async {
        final support = '${temp.path}/support';
        Directory(support).createSync();
        final calls = _answerSupportDirectory(() => support);

        final paths = await resolveNativeStoragePaths();

        expect(calls, ['getApplicationSupportDirectory']);
        expect(
          paths,
          NativeStoragePaths(
            databasePath: '$support/noteapp/noteapp.sqlite',
            assetDirectoryPath: '$support/noteapp/assets',
          ),
        );
        expect(Directory('$support/noteapp').existsSync(), isTrue);
        expect(Directory('$support/noteapp/assets').existsSync(), isFalse);
        expect(File('$support/noteapp/noteapp.sqlite').existsSync(), isFalse);
        // Same parent folder → same volume (CORE renames within one dir).
        expect(
          File(paths!.databasePath).parent.path,
          Directory(paths.assetDirectoryPath).parent.path,
        );
      },
    );

    test('a support directory that does not exist yet is created with it '
        '(recursive)', () async {
      final support = '${temp.path}/a/b/Application Support';
      _answerSupportDirectory(() => support);
      final paths = await resolveNativeStoragePaths();
      expect(paths!.databasePath, '$support/noteapp/noteapp.sqlite');
      expect(Directory('$support/noteapp').existsSync(), isTrue);
    });

    test(
      'a trailing slash on the support path gives no double slash',
      () async {
        final support = '${temp.path}/support';
        _answerSupportDirectory(() => '$support/');
        final paths = await resolveNativeStoragePaths();
        expect(paths!.databasePath, '$support/noteapp/noteapp.sqlite');
        expect(paths.assetDirectoryPath, '$support/noteapp/assets');
      },
    );

    test('a second call (the folder and CORE files exist) gives the same '
        'paths and keeps what is there', () async {
      final support = '${temp.path}/support';
      _answerSupportDirectory(() => support);
      final first = await resolveNativeStoragePaths();
      File(first!.databasePath).writeAsStringSync('db');
      Directory(first.assetDirectoryPath).createSync();
      final second = await resolveNativeStoragePaths();
      expect(second, first);
      expect(File(first.databasePath).readAsStringSync(), 'db');
      expect(Directory(first.assetDirectoryPath).existsSync(), isTrue);
    });

    test('no support directory (the platform answers null) → '
        'MissingPlatformDirectoryException', () async {
      _answerSupportDirectory(() => null);
      await expectLater(
        resolveNativeStoragePaths(),
        throwsA(isA<MissingPlatformDirectoryException>()),
      );
    });

    test('a channel error is passed on', () async {
      _answerSupportDirectory(
        () => throw PlatformException(code: 'io', message: 'denied'),
      );
      await expectLater(
        resolveNativeStoragePaths(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'io')),
      );
    });

    test('no plugin at all → MissingPluginException is passed on', () async {
      // No mock handler: the channel has no implementation.
      await expectLater(
        resolveNativeStoragePaths(),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('the folder cannot be created (a file is in the way) → '
        'FileSystemException', () async {
      final support = '${temp.path}/support';
      Directory(support).createSync();
      File('$support/noteapp').writeAsStringSync('not a folder');
      _answerSupportDirectory(() => support);
      await expectLater(
        resolveNativeStoragePaths(),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('the default CoreModule (nativePaths = resolveNativeStoragePaths)', () {
    AppModuleContext context(AppErrorLog log) => AppModuleContext(
      buildInfo: BuildInfo.local,
      runtimeInfo: const RuntimeInfo(
        isWeb: false,
        renderer: WebRenderer.notWeb,
        isStandalone: false,
      ),
      web: FakeWebPlatform(),
      ownerId: kLocalOwnerId,
      errorLog: log,
    );

    test(
      'opens CORE with BOTH native fields under <support>/noteapp/',
      () async {
        final support = '${temp.path}/support';
        _answerSupportDirectory(() => support);
        final opener = fakeOpenNoteStore();
        final log = AppErrorLog();
        final ctx = context(log);
        await CoreModule(open: opener.call).start(ctx);

        final config = opener.lastConfig!;
        expect(config.nativeDatabasePath, '$support/noteapp/noteapp.sqlite');
        expect(config.nativeAssetDirectoryPath, '$support/noteapp/assets');
        expect(
          ctx.maybe<NativeStoragePaths>()?.databasePath,
          config.nativeDatabasePath,
        );
        expect(log.records, isEmpty);
      },
    );

    test('no plugin → one record (source: module) and neither field', () async {
      final opener = fakeOpenNoteStore();
      final log = AppErrorLog();
      await CoreModule(open: opener.call).start(context(log));
      expect(log.records, hasLength(1));
      expect(log.records.single.source, AppErrorSource.module);
      expect(log.records.single.summary, contains('MissingPluginException'));
      expect(opener.lastConfig!.nativeDatabasePath, isNull);
      expect(opener.lastConfig!.nativeAssetDirectoryPath, isNull);
    });
  });
}
