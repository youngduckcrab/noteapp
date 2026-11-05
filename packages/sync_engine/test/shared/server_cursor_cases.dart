// ServerCursor cases shared by the VM test (common/server_cursor_test.dart)
// and Chrome (web/pure_logic_browser_test.dart, T3): microseconds stay below
// 2^53 so the web int is exact.
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

void serverCursorCases() {
  test('parses decimal digits only', () {
    expect(ServerCursor.parse('0'), ServerCursor.zero);
    expect(ServerCursor.parse('1793750400000000').micros, 1793750400000000);
    expect(ServerCursor.parse('007').micros, 7);
    for (final bad in ['', '-1', '+1', '1.5', ' 1', '1 ', '1e3', 'abc']) {
      expect(() => ServerCursor.parse(bad), throwsFormatException, reason: bad);
    }
  });

  test('accepts values below 2^53 and rejects the rest', () {
    expect(ServerCursor.parse('9007199254740991').micros, 9007199254740991);
    expect(() => ServerCursor.parse('9007199254740992'), throwsFormatException);
    expect(
      () => ServerCursor.parse('10000000000000000'),
      throwsFormatException,
    );
    expect(ServerCursor.parse('0009007199254740991').micros, 9007199254740991);
  });

  test('tryParse returns null for null and malformed text', () {
    expect(ServerCursor.tryParse(null), isNull);
    expect(ServerCursor.tryParse('x1'), isNull);
    expect(ServerCursor.tryParse('42'), const ServerCursor(42));
  });

  test('toString is the decimal micros and parses back', () {
    const c = ServerCursor(1793750400123456);
    expect(c.toString(), '1793750400123456');
    expect(ServerCursor.parse(c.toString()), c);
  });

  test('orders by micros', () {
    const a = ServerCursor(10), b = ServerCursor(20);
    expect(a < b, isTrue);
    expect(b > a, isTrue);
    expect(a >= a, isTrue);
    expect(a >= b, isFalse);
    expect(a.compareTo(b), lessThan(0));
    expect(ServerCursor.max(a, b), b);
    expect(ServerCursor.max(b, a), b);
    expect([b, a]..sort(), [a, b]);
  });

  test('minus clamps at zero', () {
    const c = ServerCursor(5000000);
    expect(c.minus(const Duration(seconds: 2)), const ServerCursor(3000000));
    expect(c.minus(const Duration(seconds: 5)), ServerCursor.zero);
    expect(c.minus(const Duration(minutes: 5)), ServerCursor.zero);
    expect(ServerCursor.zero.minus(const Duration(days: 1)), ServerCursor.zero);
  });

  test('converts from and to UTC DateTime', () {
    final t = DateTime.utc(2026, 11, 1, 12, 30, 15, 250);
    final c = ServerCursor.fromDateTime(t);
    expect(c.micros, t.microsecondsSinceEpoch);
    expect(c.toDateTime(), t);
    expect(c.toDateTime().isUtc, isTrue);
    expect(ServerCursor.fromDateTime(t.toLocal()), c);
  });
}
