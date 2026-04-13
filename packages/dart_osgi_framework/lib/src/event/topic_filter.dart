/// Filters event topics using exact match or trailing wildcard patterns.
///
/// Supports:
/// - Exact match: `"com/ivi/can/THRESHOLD_EXCEEDED"`
/// - Wildcard suffix: `"com/ivi/can/*"` matches any topic under `com/ivi/can/`
/// - Root wildcard: `"*"` matches all topics
class TopicFilter {
  TopicFilter._(this.pattern, this._matcher);

  /// Parse a topic filter pattern.
  factory TopicFilter(String pattern) {
    if (pattern == '*') {
      return TopicFilter._(pattern, _matchAll);
    }
    if (pattern.endsWith('/*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      return TopicFilter._(pattern, (topic) => topic.startsWith(prefix));
    }
    // Exact match.
    return TopicFilter._(pattern, (topic) => topic == pattern);
  }

  final String pattern;
  final bool Function(String topic) _matcher;

  /// Test whether [topic] matches this filter.
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
