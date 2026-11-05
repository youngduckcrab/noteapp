// lib/src/common/sort_keys.dart — contract 00-overview 7.2.2 / CORE 4.1, 6.6.
// A line-by-line port of npm `fractional-indexing` 3.2.0 (generateKeyBetween,
// generateNKeysBetween). Like 3.2.0 (and unlike 4.0.0) a >= b is an error.

/// Fractional indexing (base-62), compatible with npm `fractional-indexing` 3.2.0.
abstract final class SortKeys {
  static const String digits =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  /// Key strictly between [a] and [b]; null means open end.
  /// Throws ArgumentError if a >= b or a key is invalid.
  static String between(String? a, String? b) {
    if (a != null) _validateOrderKey(a);
    if (b != null) _validateOrderKey(b);
    if (a != null && b != null && a.compareTo(b) >= 0) {
      throw ArgumentError('$a >= $b');
    }
    if (a == null) {
      if (b == null) return 'a$_zero';
      final ib = _integerPart(b);
      final fb = b.substring(ib.length);
      if (ib == _smallestInteger) return ib + _midpoint('', fb);
      if (ib.compareTo(b) < 0) return ib;
      final res = _decrementInteger(ib);
      if (res == null) throw ArgumentError('cannot decrement any more');
      return res;
    }
    if (b == null) {
      final ia = _integerPart(a);
      final fa = a.substring(ia.length);
      final i = _incrementInteger(ia);
      return i ?? ia + _midpoint(fa, null);
    }
    final ia = _integerPart(a);
    final fa = a.substring(ia.length);
    final ib = _integerPart(b);
    final fb = b.substring(ib.length);
    if (ia == ib) return ia + _midpoint(fa, fb);
    final i = _incrementInteger(ia);
    if (i == null) throw ArgumentError('cannot increment any more');
    if (i.compareTo(b) < 0) return i;
    return ia + _midpoint(fa, null);
  }

  /// [n] ascending keys strictly between [a] and [b].
  static List<String> nBetween(String? a, String? b, int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'must not be negative');
    if (n == 0) return const [];
    if (n == 1) return [between(a, b)];
    if (b == null) {
      var c = between(a, b);
      final result = [c];
      for (var i = 0; i < n - 1; i++) {
        c = between(c, b);
        result.add(c);
      }
      return result;
    }
    if (a == null) {
      var c = between(a, b);
      final result = [c];
      for (var i = 0; i < n - 1; i++) {
        c = between(a, c);
        result.add(c);
      }
      return result.reversed.toList();
    }
    final mid = n ~/ 2;
    final c = between(a, b);
    return [...nBetween(a, c, mid), c, ...nBetween(c, b, n - mid - 1)];
  }

  static bool isValid(String key) {
    try {
      _validateOrderKey(key);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  static const String first = 'a0';

  static const String _zero = '0';
  static final String _smallestInteger = 'A${_zero * 26}';

  static String _midpoint(String a, String? b) {
    if (b != null && a.compareTo(b) >= 0) throw ArgumentError('$a >= $b');
    if (a.endsWith(_zero) || (b != null && b.endsWith(_zero))) {
      throw ArgumentError('trailing zero');
    }
    if (b != null && b.isNotEmpty) {
      var n = 0;
      while (n < b.length && (n < a.length ? a[n] : _zero) == b[n]) {
        n++;
      }
      if (n > 0) {
        return b.substring(0, n) +
            _midpoint(n < a.length ? a.substring(n) : '', b.substring(n));
      }
    }
    final digitA = a.isNotEmpty ? digits.indexOf(a[0]) : 0;
    final digitB = b != null && b.isNotEmpty
        ? digits.indexOf(b[0])
        : digits.length;
    if (digitB - digitA > 1) {
      final midDigit = (0.5 * (digitA + digitB)).round();
      return digits[midDigit];
    }
    if (b != null && b.length > 1) return b.substring(0, 1);
    return digits[digitA] + _midpoint(a.isNotEmpty ? a.substring(1) : '', null);
  }

  static int _integerLength(String head) {
    final code = head.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7A) return code - 0x61 + 2; // a..z
    if (code >= 0x41 && code <= 0x5A) return 0x5A - code + 2; // A..Z
    throw ArgumentError('invalid order key head: $head');
  }

  static void _validateInteger(String integer) {
    if (integer.length != _integerLength(integer[0])) {
      throw ArgumentError('invalid integer part of order key: $integer');
    }
  }

  static String _integerPart(String key) {
    if (key.isEmpty) throw ArgumentError('invalid order key: (empty)');
    final length = _integerLength(key[0]);
    if (length > key.length) throw ArgumentError('invalid order key: $key');
    return key.substring(0, length);
  }

  static void _validateOrderKey(String key) {
    if (key == _smallestInteger) throw ArgumentError('invalid order key: $key');
    for (var i = 0; i < key.length; i++) {
      if (!digits.contains(key[i])) {
        throw ArgumentError('invalid order key: $key');
      }
    }
    final i = _integerPart(key);
    final f = key.substring(i.length);
    if (f.endsWith(_zero)) throw ArgumentError('invalid order key: $key');
  }

  static String? _incrementInteger(String x) {
    _validateInteger(x);
    final head = x[0];
    final digs = x.substring(1).split('');
    var carry = true;
    for (var i = digs.length - 1; carry && i >= 0; i--) {
      final d = digits.indexOf(digs[i]) + 1;
      if (d == digits.length) {
        digs[i] = _zero;
      } else {
        digs[i] = digits[d];
        carry = false;
      }
    }
    if (carry) {
      if (head == 'Z') return 'a$_zero';
      if (head == 'z') return null;
      final h = String.fromCharCode(head.codeUnitAt(0) + 1);
      if (h.compareTo('a') > 0) {
        digs.add(_zero);
      } else {
        digs.removeLast();
      }
      return h + digs.join();
    }
    return head + digs.join();
  }

  static String? _decrementInteger(String x) {
    _validateInteger(x);
    final head = x[0];
    final digs = x.substring(1).split('');
    final last = digits[digits.length - 1];
    var borrow = true;
    for (var i = digs.length - 1; borrow && i >= 0; i--) {
      final d = digits.indexOf(digs[i]) - 1;
      if (d == -1) {
        digs[i] = last;
      } else {
        digs[i] = digits[d];
        borrow = false;
      }
    }
    if (borrow) {
      if (head == 'a') return 'Z$last';
      if (head == 'A') return null;
      final h = String.fromCharCode(head.codeUnitAt(0) - 1);
      if (h.compareTo('Z') < 0) {
        digs.add(last);
      } else {
        digs.removeLast();
      }
      return h + digs.join();
    }
    return head + digs.join();
  }
}

/// Total order for siblings: sortKey (binary/ASCII), then id.
int compareSortKeyThenId(String keyA, String idA, String keyB, String idB) {
  final c = keyA.compareTo(keyB);
  return c != 0 ? c : idA.compareTo(idB);
}
