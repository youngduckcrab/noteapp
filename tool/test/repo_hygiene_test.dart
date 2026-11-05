// .gitignore and .gitattributes (docs/plans/m5-7/01-infra.md 3.1, contract
// 00-overview 7.4.5 / 7.4.7 v2.1): asks git itself (`git check-ignore`,
// `git check-attr`) about sample paths, so the real rules are tested, not
// the file text. Skipped when git or the repository is not available.

import 'dart:io';

import 'package:test/test.dart';

import 'support/fixture_workspace.dart';

const _pluginSwift =
    'packages/pencil_bridge/ios/pencil_bridge/Sources/pencil_bridge/'
    'PencilBridgePlugin.swift';

bool _gitAvailable() {
  try {
    return Process.runSync('git', [
          'rev-parse',
          '--is-inside-work-tree',
        ], workingDirectory: repoRoot).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}

/// Whether git ignores [path] (it does not need to exist).
bool _ignored(String path) {
  final result = Process.runSync('git', [
    'check-ignore',
    '--no-index',
    '-q',
    path,
  ], workingDirectory: repoRoot);
  expect(result.exitCode, isIn([0, 1]), reason: '${result.stderr}');
  return result.exitCode == 0;
}

/// `git check-attr` values of [path]: attribute → value.
Map<String, String> _attributes(String path) {
  final result = Process.runSync('git', [
    'check-attr',
    '-a',
    path,
  ], workingDirectory: repoRoot);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return {
    for (final line in '${result.stdout}'.trim().split('\n'))
      if (line.split(': ') case [_, final name, final value]) name: value,
  };
}

void main() {
  final skip = _gitAvailable() ? false : 'git or the repository not available';

  group('.gitignore (contract 7.4.7)', () {
    test('functions/ sources, lock and the demo env are NOT ignored', () {
      for (final path in [
        'functions/.env.demo-noteapp',
        'functions/package.json',
        'functions/package-lock.json',
        'functions/tsconfig.json',
        'functions/src/index.ts',
        'functions/test/fake_engine.test.ts',
        'app/firebase.json',
      ]) {
        expect(_ignored(path), isFalse, reason: path);
      }
    });

    test('functions/ build output, local secrets and firebase logs are '
        'ignored', () {
      for (final path in [
        'functions/.env.local',
        'functions/.secret.local',
        'functions/lib/x.js',
        'functions/lib/test/a.test.js',
        'functions/node_modules/a',
        'functions/node_modules/.bin/firebase',
        'functions/eval-out/r.json',
        'firebase-debug.log',
        'firebase-debug.123.log',
        'functions/firebase-debug.log',
      ]) {
        expect(_ignored(path), isTrue, reason: path);
      }
    });

    test('signing material is ignored (1차 and 2차 patterns)', () {
      for (final path in [
        'app/android/key.properties',
        'x.jks',
        'app/android/upload.keystore',
        'AuthKey_ABC.p8',
        'x.p12',
        'dist.mobileprovision',
      ]) {
        expect(_ignored(path), isTrue, reason: path);
      }
    });

    test('1차 rules still hold', () {
      expect(_ignored('.dart_tool/package_config.json'), isTrue);
      expect(_ignored('app/build/web/main.dart.js'), isTrue);
      expect(_ignored('app/.flutter-plugins-dependencies'), isTrue);
      expect(_ignored('pubspec.lock'), isFalse);
      expect(_ignored('tool/chrome-fakemedia'), isFalse);
    });
  }, skip: skip);

  group('.gitattributes (contract 7.4.5 v2.1)', () {
    test('fonts, recording samples and DB fixtures are binary', () {
      for (final path in [
        'packages/ink_engine/assets/fonts/NoteSans-Regular.ttf',
        'x.otf',
        'packages/media_io/test/support/fixtures/rec.webm',
        'packages/media_io/test/support/fixtures/rec.m4a',
        'packages/note_core/test/fixtures/v1/notes.sqlite',
      ]) {
        final attributes = _attributes(path);
        expect(attributes['binary'], 'set', reason: path);
        expect(attributes['text'], 'unset', reason: path);
        expect(attributes['diff'], 'unset', reason: path);
      }
    });

    test('scripts keep LF: tool/chrome-fakemedia, *.sh, *.swift, Podfile', () {
      for (final path in [
        'tool/chrome-fakemedia',
        'functions/scripts/emulator_suite.sh',
        _pluginSwift,
        'app/ios/Podfile',
      ]) {
        final attributes = _attributes(path);
        expect(attributes['text'], 'set', reason: path);
        expect(attributes['eol'], 'lf', reason: path);
      }
    });

    test('1차 attributes still hold', () {
      expect(_attributes('app/web/icons/Icon-192.png')['binary'], 'set');
      expect(_attributes('app/web/drift_worker.js')['text'], 'unset');
      expect(_attributes('pubspec.lock')['linguist-generated'], 'true');
    });
  }, skip: skip);
}
