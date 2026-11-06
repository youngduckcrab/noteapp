// T26a (m5-7/03-ink 8.1, 4.10): InkFonts — one load (the same Future while it
// runs), the file bytes, a failure is reported and the next call retries, a source
// that never answers ends in TimeoutException after 5 s (both functions) and its
// late bytes are dropped, implicit loads pause 30 s after a failure while a direct
// ensureLoaded always retries; covers().
//
// The committed font files are read from assets/fonts/ (VM, dart:io) through
// debugSetInkFontSource: the package pubspec does not list them as assets yet
// (INFRA change request — R2-B3 progress log).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/text/fonts.dart';
import 'package:ink_engine/testing.dart';

Uint8List _file(bool bold) =>
    File('assets/fonts/NoteSans-${bold ? 'Bold' : 'Regular'}.ttf')
        .readAsBytesSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final realNow = InkFontsDebug.nowUs;

  tearDown(() {
    InkFontsDebug.nowUs = realNow;
    debugSetInkFontSource(null);
  });

  test(
    'loads once; the second call while loading is the same Future',
    () async {
      var calls = 0;
      debugSetInkFontSource(({required bool bold}) async {
        calls++;
        return _file(bold);
      });
      expect(InkFontsDebug.isLoaded, isFalse);
      final a = InkFonts.ensureLoaded();
      final b = InkFonts.ensureLoaded();
      expect(identical(a, b), isTrue);
      await a;
      expect(InkFontsDebug.isLoaded, isTrue);
      expect(calls, 2, reason: 'regular + bold, once');
      await InkFonts.ensureLoaded();
      expect(calls, 2);
    },
  );

  test('noteSansBytes = the file; read once', () async {
    var calls = 0;
    debugSetInkFontSource(({required bool bold}) async {
      calls++;
      return _file(bold);
    });
    final regular = await InkFonts.noteSansBytes();
    final bold = await InkFonts.noteSansBytes(bold: true);
    expect(
      regular.length,
      File('assets/fonts/NoteSans-Regular.ttf').lengthSync(),
    );
    expect(bold.length, File('assets/fonts/NoteSans-Bold.ttf').lengthSync());
    await InkFonts.noteSansBytes();
    await InkFonts.ensureLoaded(); // the bytes already read are used
    expect(calls, 2);
  });

  test('a failing source → that error; the next call tries again', () async {
    var fail = true;
    var calls = 0;
    debugSetInkFontSource(({required bool bold}) async {
      calls++;
      if (fail) throw StateError('no bytes');
      return _file(bold);
    });
    await expectLater(InkFonts.ensureLoaded(), throwsStateError);
    expect(InkFontsDebug.isLoaded, isFalse);
    expect(InkFontsDebug.isSettled, isTrue, reason: 'failed = settled');
    fail = false;
    await InkFonts.ensureLoaded();
    expect(InkFontsDebug.isLoaded, isTrue);
    expect(calls, greaterThanOrEqualTo(3));
  });

  test('a source that never answers: 5 s → TimeoutException (both), late '
      'bytes dropped, implicit loads pause 30 s, direct calls retry', () {
    fakeAsync((async) {
      InkFontsDebug.nowUs = () => async.elapsed.inMicroseconds;
      final pending = <Completer<Uint8List>>[];
      debugSetInkFontSource(({required bool bold}) {
        final c = Completer<Uint8List>();
        pending.add(c);
        return c.future;
      });
      Object? loadError, bytesError;
      InkFonts.ensureLoaded().catchError((Object e) => loadError = e);
      async.elapse(const Duration(milliseconds: 4999));
      expect(loadError, isNull);
      async.elapse(const Duration(milliseconds: 2));
      expect(loadError, isA<TimeoutException>());
      final asked = pending.length;
      InkFonts.noteSansBytes().catchError((Object e) {
        bytesError = e;
        return Uint8List(0);
      });
      async.elapse(const Duration(seconds: 5, milliseconds: 1));
      expect(bytesError, isA<TimeoutException>());
      // late bytes are dropped: nothing gets registered, nothing is cached
      for (final c in pending) {
        if (!c.isCompleted) c.complete(Uint8List(4));
      }
      async.flushMicrotasks();
      expect(InkFontsDebug.isLoaded, isFalse);
      // implicit loads within 30 s of the failure start nothing
      final before = pending.length;
      expect(asked, greaterThan(0));
      InkFontsDebug.loadImplicitly();
      async.flushMicrotasks();
      expect(pending.length, before);
      expect(InkFontsDebug.isSettled, isTrue);
      // a direct call always tries again
      InkFonts.ensureLoaded().catchError((Object _) {});
      async.flushMicrotasks();
      expect(pending.length, greaterThan(before));
      async.elapse(const Duration(seconds: 6));
      // 30 s after that failure an implicit load starts again
      final again = pending.length;
      async.elapse(const Duration(seconds: 31));
      InkFontsDebug.loadImplicitly();
      async.flushMicrotasks();
      expect(pending.length, greaterThan(again));
      async.elapse(const Duration(seconds: 6));
    });
  });

  test(
    'covers: the KS X 1001 subset, spaces and controls count as covered',
    () {
      var hangul = 0;
      for (var c = 0xAC00; c <= 0xD7A3; c++) {
        if (InkFonts.covers(String.fromCharCode(c))) hangul++;
      }
      expect(hangul, 2350);
      expect(InkFonts.covers('똠'), isFalse); // outside KS X 1001
      expect(InkFonts.covers('안녕 hello\n\t①₩'), isTrue);
      expect(InkFonts.covers(''), isTrue);
      expect(InkFonts.covers('ㄱㅎㅏ'), isTrue); // compatibility jamo
      expect(InkFonts.covers('漢'), isFalse);
      expect(InkFonts.covers('😀'), isFalse);
    },
  );

  test('the family name and the asset keys', () {
    expect(InkFonts.noteSans, 'NoteSans');
    for (final f in ['NoteSans-Regular.ttf', 'NoteSans-Bold.ttf', 'OFL.txt']) {
      expect(File('assets/fonts/$f').existsSync(), isTrue, reason: f);
    }
  });
}
