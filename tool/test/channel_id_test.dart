// previewChannelId / ws channel-id (docs/plans/01-infra.md 6.12 and 9.1).

import 'dart:convert';

import 'package:test/test.dart';

import '../src/channel_id.dart';
import '../src/cli.dart';
import 'support/fixture_workspace.dart';

String hash6(String name) =>
    fnv1a32(utf8.encode(name))
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(0, 6);

void main() {
  test('FNV-1a 32 reference values', () {
    expect(fnv1a32(const []), 0x811c9dc5);
    expect(fnv1a32(utf8.encode('a')), 0xe40c292c);
    expect(fnv1a32(utf8.encode('foobar')), 0xbf9cf968);
  });

  test('plan examples: claude/ prefix dropped, slug cut at 12', () {
    const branch = 'claude/note-app-planning-bk29xb';
    expect(previewChannelId(branch), 'b-note-app-pla-${hash6(branch)}');
    expect(
      previewChannelId('area/infra'),
      'b-area-infra-${hash6('area/infra')}',
    );
    expect(previewChannelId('main'), 'b-main-${hash6('main')}');
  });

  test('refs/heads/ is dropped before hashing', () {
    expect(
      previewChannelId('refs/heads/area/infra'),
      previewChannelId('area/infra'),
    );
  });

  test('only [a-z0-9-], at most 21 characters, no trailing dash in slug', () {
    final valid = RegExp(r'^b-[a-z0-9]+(-[a-z0-9]+)*-[0-9a-f]{6}$');
    for (final branch in [
      'Feature/Über_Große--Änderung!!',
      'a' * 80,
      'x/yyyyyyyyyyy-zzz',
      'claude/abcdefghijk-lmnop',
      '__weird__',
      'UPPER',
    ]) {
      final id = previewChannelId(branch);
      expect(id, matches(valid), reason: branch);
      expect(id.length, lessThanOrEqualTo(maxChannelIdLength), reason: branch);
    }
    // 12th character is a dash: it is dropped, not kept.
    expect(previewChannelId('abcdefghijk-lmnop'), startsWith('b-abcdefghijk-'));
    expect(previewChannelId('abcdefghijk-lmnop').length, 20);
  });

  test('deterministic; branches that differ only in case differ', () {
    expect(previewChannelId('area/infra'), previewChannelId('area/infra'));
    final lower = previewChannelId('area/infra');
    final upper = previewChannelId('Area/Infra');
    expect(lower.substring(0, 13), upper.substring(0, 13));
    expect(lower, isNot(upper));
  });

  test('an empty slug becomes "branch"', () {
    expect(previewChannelId('claude/'), 'b-branch-${hash6('claude/')}');
    expect(previewChannelId('///'), 'b-branch-${hash6('///')}');
    expect(previewChannelId('한글'), 'b-branch-${hash6('한글')}');
    expect(() => previewChannelId(''), throwsArgumentError);
  });

  test('ws channel-id prints the id; missing --branch exits 2', () async {
    final out = StringBuffer();
    final code = await runWs([
      'channel-id',
      '--branch',
      'refs/heads/area/infra',
    ], context: WsContext(root: repoRoot, out: out, err: StringBuffer()));
    expect(code, 0);
    expect(out.toString().trim(), previewChannelId('area/infra'));
    for (final args in [
      ['channel-id'],
      ['channel-id', '--branch', ''],
      ['channel-id', '--branch', 'refs/heads/'],
    ]) {
      expect(
        await runWs(
          args,
          context: WsContext(
            root: repoRoot,
            out: StringBuffer(),
            err: StringBuffer(),
          ),
        ),
        usageExitCode,
        reason: '$args',
      );
    }
  });
}
