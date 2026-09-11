/// Matches event topics against a subscription pattern.
///
///  * `com/ivi/can/THRESHOLD_EXCEEDED` -- exactly that topic.
///  * `com/ivi/can/*` -- every topic below `com/ivi/can/`, at any depth, but
///    not `com/ivi/can` itself.
///  * `*` -- every topic.
///
/// `*` is a wildcard only as the whole last segment. Anywhere else --
/// `com/ivi/can*`, `com/*/can` -- the pattern is rejected: read literally it
/// would silently match nothing, and the subscriber would never know why.
class TopicFilter {
  TopicFilter._(this.pattern, this._matcher);

  /// Throws [ArgumentError] for a `*` anywhere but the whole last segment.
  factory TopicFilter(String pattern) {
    if (pattern == '*') return TopicFilter._(pattern, _matchAll);
    final bool isPrefix = pattern.endsWith('/*');
    final String fixed = isPrefix
        ? pattern.substring(0, pattern.length - 1)
        : pattern;
    if (fixed.contains('*')) {
      throw ArgumentError.value(
        pattern,
        'pattern',
        '"*" is a wildcard only as the whole last segment',
      );
    }
    if (isPrefix) {
      return TopicFilter._(pattern, (String topic) => topic.startsWith(fixed));
    }
    return TopicFilter._(pattern, (String topic) => topic == pattern);
  }

  final String pattern;
  final bool Function(String topic) _matcher;

  /// Whether [topic] matches this filter.
  bool matches(String topic) => _matcher(topic);

  static bool _matchAll(String topic) => true;

  @override
  String toString() => 'TopicFilter($pattern)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicFilter && pattern == other.pattern;

  @override
  int get hashCode => pattern.hashCode;
}
