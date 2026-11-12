// lib/src/ondevice/mfr_tokenizer.dart — (internal) the on-device math
// engine's detokenizer: the byte-level BPE vocabulary of the model's
// tokenizer.json (Hugging Face `tokenizers`, model BPE, decoder ByteLevel).
//
// Decoding only (the engine never encodes): ids → vocabulary strings,
// special ids (0–4: <pad> <s> </s> <unk> <mask>) skipped, concatenated, then
// GPT-2's bytes_to_unicode map reversed (so 'Ġ' → ' ') and the bytes read as
// UTF-8 (a byte sequence the model left unfinished becomes U+FFFD, like
// `tokenizers` does). Same result as `Tokenizer.decode(ids,
// skip_special_tokens=True)` of the reference (test/unit/mfr_tokenizer_test).
import 'dart:convert';

final class MfrTokenizer {
  MfrTokenizer._(this._vocab, this._special);

  /// Reads tokenizer.json's `model.vocab` (token → id) and `added_tokens`
  /// (the special ids). Throws [FormatException] for another layout.
  factory MfrTokenizer.fromJson(String json) {
    final root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('tokenizer.json: not an object');
    }
    final model = root['model'];
    if (model is! Map<String, Object?> || model['vocab'] is! Map) {
      throw const FormatException('tokenizer.json: no model.vocab');
    }
    final vocab = (model['vocab']! as Map).cast<String, Object?>();
    var size = 0;
    for (final id in vocab.values) {
      if (id is! int || id < 0) {
        throw const FormatException('tokenizer.json: bad vocab id');
      }
      if (id >= size) size = id + 1;
    }
    final byId = List<String?>.filled(size, null);
    vocab.forEach((token, id) => byId[id! as int] = token);
    final special = <int>{};
    final added = root['added_tokens'];
    if (added is List) {
      for (final t in added) {
        if (t is Map && t['special'] == true && t['id'] is int) {
          special.add(t['id'] as int);
        }
      }
    }
    return MfrTokenizer._(byId, special);
  }

  final List<String?> _vocab;
  final Set<int> _special;

  int get vocabSize => _vocab.length;

  /// The text of [ids] (special and unknown ids skipped).
  String decode(Iterable<int> ids) {
    final bytes = <int>[];
    for (final id in ids) {
      if (id < 0 || id >= _vocab.length || _special.contains(id)) continue;
      final token = _vocab[id];
      if (token == null) continue;
      for (final rune in token.runes) {
        final b = _unicodeToByte[rune];
        if (b != null) {
          bytes.add(b);
        } else {
          // Not a byte-level symbol (never in this vocabulary): keep it.
          bytes.addAll(utf8.encode(String.fromCharCode(rune)));
        }
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// GPT-2's bytes_to_unicode, reversed: the printable Latin-1 bytes map to
/// themselves, the other 68 bytes to U+0100 onwards in byte order.
final Map<int, int> _unicodeToByte = () {
  final map = <int, int>{};
  bool printable(int b) =>
      (b >= 0x21 && b <= 0x7e) ||
      (b >= 0xa1 && b <= 0xac) ||
      (b >= 0xae && b <= 0xff);
  var next = 0;
  for (var b = 0; b < 256; b++) {
    if (printable(b)) {
      map[b] = b;
    } else {
      map[256 + next] = b;
      next++;
    }
  }
  return map;
}();
