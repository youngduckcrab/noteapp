/// `ws channel-id`: the Firebase Hosting preview channel of a branch
/// (docs/plans/01-infra.md 6.12).
///
/// FirebaseExtended/action-hosting-deploy only derives a channel id from
/// `pull_request` events, so pushes pass an explicit id made here.
library;

import 'dart:convert';

/// Longest result: `b-` + 12 + `-` + 6.
const int maxChannelIdLength = 21;

/// The preview channel id of [branch]:
///
/// 1. drop `refs/heads/`, lowercase, drop a leading `claude/`;
/// 2. every character outside `[a-z0-9]` becomes `-`, runs of `-` collapse,
///    leading and trailing `-` are removed;
/// 3. `slug` = the first 12 characters without a trailing `-`, or `branch`
///    when that is empty;
/// 4. `hash` = the first 6 hex digits of the 32-bit FNV-1a hash of the UTF-8
///    branch name (after dropping `refs/heads/`, before lowercasing — so
///    branches that differ only in case get different ids);
/// 5. result `b-<slug>-<hash>` (at most [maxChannelIdLength] characters).
///
/// Throws [ArgumentError] when [branch] is empty.
String previewChannelId(String branch) {
  var name = branch.trim();
  const refsHeads = 'refs/heads/';
  if (name.startsWith(refsHeads)) name = name.substring(refsHeads.length);
  if (name.isEmpty) throw ArgumentError.value(branch, 'branch', 'is empty');

  var lower = name.toLowerCase();
  const claude = 'claude/';
  if (lower.startsWith(claude)) lower = lower.substring(claude.length);
  final dashed = lower
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  var slug = dashed.length > 12 ? dashed.substring(0, 12) : dashed;
  slug = slug.replaceAll(RegExp(r'-+$'), '');
  if (slug.isEmpty) slug = 'branch';

  final hash = fnv1a32(utf8.encode(name)).toRadixString(16).padLeft(8, '0');
  return 'b-$slug-${hash.substring(0, 6)}';
}

/// 32-bit FNV-1a of [bytes] (tool-only code on the Dart VM).
int fnv1a32(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
