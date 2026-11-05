/// The result type of `ws check` rules.
library;

/// One rule violation (or warning) reported by `ws check`.
///
/// Printed as `path:line: [rule] message` (docs/plans/01-infra.md 4.2).
final class RuleViolation implements Comparable<RuleViolation> {
  const RuleViolation({
    required this.rule,
    required this.path,
    required this.line,
    required this.message,
    this.isWarning = false,
  });

  /// Rule id, e.g. `R8` or `R9w` for the R9 warning.
  final String rule;

  /// Repo-relative path with `/` separators.
  final String path;

  /// 1-based line (1 when the problem is about the whole file).
  final int line;

  final String message;

  /// Warnings (R9w) only fail `ws check --strict`.
  final bool isWarning;

  String format() => '$path:$line: [$rule] $message';

  @override
  int compareTo(RuleViolation other) {
    final byPath = path.compareTo(other.path);
    if (byPath != 0) return byPath;
    final byLine = line.compareTo(other.line);
    if (byLine != 0) return byLine;
    final byRule = rule.compareTo(other.rule);
    if (byRule != 0) return byRule;
    return message.compareTo(other.message);
  }

  @override
  bool operator ==(Object other) =>
      other is RuleViolation &&
      other.rule == rule &&
      other.path == path &&
      other.line == line &&
      other.message == message &&
      other.isWarning == isWarning;

  @override
  int get hashCode => Object.hash(rule, path, line, message, isWarning);

  @override
  String toString() => format();
}
