// API surface of media_io (2nd-round contract 00-overview 7.2.12 and 7.6, m5-7/06-pdf 4.2.6,
// 4.3.2, 8.1 T30).
//
// 1. Export lists: lib/media_io.dart exports with `show` only, and the shown names are exactly
//    the contract's seven; services, engines, errors and the runtime stay internal.
//    lib/testing.dart offers exactly the 7.6 helpers.
// 2. Compile-time shape: every contract function, constructor and member is referenced with
//    the contract types (typed tear-offs), so a renamed / retyped / removed member breaks the
//    build. MediaIoConfig has the contract defaults.
// 3. The fakes are plain `extends` of the three platform classes (no mixin).
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:record_platform_interface/record_platform_interface.dart';

/// Contract 7.2.12 (06-pdf 4.2.6): the seven names, nothing else.
const Set<String> barrelNames = {
  'initializeMediaIo',
  'MediaIoConfig',
  'mediaIoOverrides',
  'supportedImageSources',
  'importImageForNote',
  'RecordingPanel',
  'mediaDevOverlayLinesProvider',
};

/// Contract 7.6 / 06-pdf 4.3.2.
const Set<String> testingNames = {
  'registerMediaWebPlugins',
  'FakeRecordPlatform',
  'FakeJustAudioPlatform',
  'FakeImagePickerPlatform',
  'installFakeMediaPlatforms',
  'MediaFakePlatforms',
};

/// Internal (06-pdf 4.2.5, 4.2.6, 3.3): never exported by either entry point.
const Set<String> internalNames = {
  'MediaIoRuntime',
  'MediaIoException',
  'MediaErrorCode',
  'MediaRecorderService',
  'JustAudioPlaybackService',
  'MediaStringsKo',
  'MediaTuning',
  'MediaTestHooks',
  'mediaFakesVmOnlyMessage',
  'registerMediaWebPluginsImpl',
  'createMediaTestDirectory',
  'writeMediaTestFile',
};

String _read(String path) => File(path).readAsStringSync();

/// Every `export` directive of [source]: (uri, shown names or null without `show`).
List<(String, Set<String>?)> _exports(String source) {
  final out = <(String, Set<String>?)>[];
  final directive = RegExp(r'''^export\s+'([^']+)'([^;]*);''', multiLine: true);
  for (final m in directive.allMatches(source)) {
    final show = RegExp(r'\bshow\b([\s\S]*)').firstMatch(m.group(2)!);
    out.add((
      m.group(1)!,
      show == null
          ? null
          : {
              for (final n in show.group(1)!.split(','))
                if (n.trim().isNotEmpty) n.trim(),
            },
    ));
  }
  return out;
}

/// Public top-level declarations of a library file found at column 0.
Set<String> _publicTopLevelNames(String source) {
  final names = <String>{};
  final typeDecl = RegExp(
    r'^(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*'
    r'(?:class|enum|mixin|typedef|extension(?:\s+type)?)\s+(\w+)',
    multiLine: true,
  );
  for (final m in typeDecl.allMatches(source)) {
    names.add(m.group(1)!);
  }
  final function = RegExp(r'^[A-Za-z_][\w<>?, ]*\s+(\w+)\(', multiLine: true);
  for (final m in function.allMatches(source)) {
    names.add(m.group(1)!);
  }
  final variable = RegExp(
    r'^(?:final|const|var|late)\s+(?:[\w<>?, ]+\s+)?(\w+)\s*=',
    multiLine: true,
  );
  for (final m in variable.allMatches(source)) {
    names.add(m.group(1)!);
  }
  return names.where((n) => !n.startsWith('_')).toSet();
}

void main() {
  group('export lists (contract 7.2.12, 7.6)', () {
    test('lib/media_io.dart show list = the seven contract names', () {
      final names = <String>{};
      for (final (uri, shown) in _exports(_read('lib/media_io.dart'))) {
        expect(
          shown,
          isNotNull,
          reason: 'media_io.dart exports $uri without show',
        );
        expect(
          uri,
          startsWith('src/'),
          reason: 'media_io.dart re-exports $uri',
        );
        names.addAll(shown!);
      }
      expect(names, barrelNames);
      expect(names.intersection(internalNames), isEmpty);
    });

    test('lib/testing.dart offers exactly the 7.6 helpers', () {
      final source = _read('lib/testing.dart');
      final exported = <String>{};
      for (final (uri, shown) in _exports(source)) {
        expect(
          shown,
          isNotNull,
          reason: 'testing.dart exports $uri without show',
        );
        expect(uri, 'src/testing/fake_platforms.dart');
        exported.addAll(shown!);
      }
      expect({...exported, ..._publicTopLevelNames(source)}, testingNames);
      expect(testingNames.intersection(barrelNames), isEmpty);
    });

    test('only lib/media_io.dart and lib/testing.dart at the top of lib/', () {
      final entries = [
        for (final f in Directory('lib').listSync())
          if (f is File) f.uri.pathSegments.last,
      ]..sort();
      expect(entries, ['media_io.dart', 'testing.dart']);
    });
  });

  group('contract 7.2.12 shapes', () {
    test('functions and providers have the contract types', () {
      final Future<void> Function({MediaIoConfig config}) init =
          initializeMediaIo;
      final List<Override> Function({MediaIoConfig? config}) overrides =
          mediaIoOverrides;
      final Set<core.ImageImportSource> Function() sources =
          supportedImageSources;
      final Future<core.ImportedImage?> Function(
        BuildContext context,
        core.ImageImportSource source,
      )
      import = importImageForNote;
      final Provider<ValueListenable<List<String>>> lines =
          mediaDevOverlayLinesProvider;
      expect([
        init,
        overrides,
        sources,
        import,
        lines,
      ], everyElement(isNotNull));
      expect(mediaDevOverlayLinesProvider.name, 'mediaDevOverlayLinesProvider');
    });

    test('MediaIoConfig: const, the contract defaults, fields', () {
      const config = MediaIoConfig();
      final int bitRate = config.bitRate;
      final int sampleRate = config.sampleRate;
      final bool allowNonAacOnWeb = config.allowNonAacOnWeb;
      final int webDraftChunkMs = config.webDraftChunkMs;
      final bool androidForegroundService = config.androidForegroundService;
      expect(
        [
          bitRate,
          sampleRate,
          allowNonAacOnWeb,
          webDraftChunkMs,
          androidForegroundService,
        ],
        [64000, 44100, true, 1000, true],
      );
      const custom = MediaIoConfig(
        bitRate: 96000,
        sampleRate: 48000,
        allowNonAacOnWeb: false,
        webDraftChunkMs: 500,
        androidForegroundService: false,
      );
      expect(custom.bitRate, 96000);
      expect(custom.androidForegroundService, isFalse);
    });

    test('RecordingPanel: a ConsumerWidget with the contract constructor', () {
      void changed(bool value) {}
      void close() {}
      final tap = ValueNotifier(false);
      addTearDown(tap.dispose);
      final panel = RecordingPanel(
        key: const ValueKey('panel'),
        noteId: 'n1',
        tapToSeek: tap,
        onTapToSeekChanged: changed,
        onClose: close,
      );
      expect(panel, isA<ConsumerWidget>());
      final String noteId = panel.noteId;
      final ValueListenable<bool> tapToSeek = panel.tapToSeek;
      final ValueChanged<bool> onChanged = panel.onTapToSeekChanged;
      final VoidCallback onClose = panel.onClose;
      expect([noteId, tapToSeek, onChanged, onClose], everyElement(isNotNull));
      expect(panel.key, const ValueKey('panel'));
    });
  });

  group('testing.dart shapes (7.6, 06-pdf 4.3.2)', () {
    test('plain extends of the platform classes, the documented members', () {
      final record = FakeRecordPlatform();
      final RecordPlatform asRecord = record;
      final FakeRecordPlatform Function({bool permission}) install =
          FakeRecordPlatform.install;
      final Uint8List bytes = record.fileBytes;
      final void Function(RecordState state) emit = record.emitState;
      final List<String> recordCalls = record.calls;
      expect([
        asRecord,
        install,
        bytes,
        emit,
        recordCalls,
      ], everyElement(isNotNull));
      expect(
        FakeRecordPlatform(permission: false, encoders: {AudioEncoder.wav}),
        isA<RecordPlatform>(),
      );

      final player = FakeJustAudioPlatform(
        defaultDuration: const Duration(seconds: 3),
      );
      final JustAudioPlatform asPlayer = player;
      final FakeJustAudioPlatform Function() installPlayer =
          FakeJustAudioPlatform.install;
      final void Function(Duration position) setPosition = player.setPosition;
      final void Function() complete = player.complete;
      final void Function() failNextLoad = player.failNextLoad;
      final List<String> playerCalls = player.calls;
      expect([
        asPlayer,
        installPlayer,
        setPosition,
        complete,
        failNextLoad,
        playerCalls,
      ], everyElement(isNotNull));

      final picker = FakeImagePickerPlatform();
      final ImagePickerPlatform asPicker = picker;
      final void Function(Uint8List? bytes, {String name}) enqueue =
          picker.enqueue;
      expect([asPicker, enqueue], everyElement(isNotNull));

      final void Function() register = registerMediaWebPlugins;
      final MediaFakePlatforms Function({bool micPermission}) installAll =
          installFakeMediaPlatforms;
      expect([register, installAll], everyElement(isNotNull));
    });

    test('MediaFakePlatforms members', () {
      final fakes = installFakeMediaPlatforms();
      addTearDown(fakes.dispose);
      final FakeRecordPlatform record = fakes.record;
      final FakeJustAudioPlatform player = fakes.player;
      final FakeImagePickerPlatform picker = fakes.picker;
      final void Function() dispose = fakes.dispose;
      expect([record, player, picker, dispose], everyElement(isNotNull));
    });

    test('no MockPlatformInterfaceMixin in the fakes (v2.1, review M-1)', () {
      final source = _read('lib/src/testing/fake_platforms.dart');
      expect(source, isNot(contains('with MockPlatformInterfaceMixin')));
      for (final base in [
        'RecordPlatform',
        'JustAudioPlatform',
        'ImagePickerPlatform',
      ]) {
        expect(
          RegExp('final class Fake\\w+ extends $base \\{').hasMatch(source),
          isTrue,
          reason: base,
        );
      }
    });
  });
}
