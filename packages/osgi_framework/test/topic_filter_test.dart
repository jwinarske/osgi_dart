import 'package:osgi_framework/osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('exact', () {
    final TopicFilter filter = TopicFilter('com/ivi/can/THRESHOLD_EXCEEDED');

    test('matches only the identical topic', () {
      expect(filter.matches('com/ivi/can/THRESHOLD_EXCEEDED'), isTrue);
      expect(filter.matches('com/ivi/can/OTHER'), isFalse);
      expect(filter.matches('com/ivi/can'), isFalse);
      expect(filter.matches('com/ivi/can/THRESHOLD_EXCEEDED/MORE'), isFalse);
    });
  });

  group('prefix', () {
    final TopicFilter filter = TopicFilter('com/ivi/*');

    test('matches topics below the prefix at any depth', () {
      expect(filter.matches('com/ivi/foo'), isTrue);
      expect(filter.matches('com/ivi/can/THRESHOLD'), isTrue);
    });

    test('does not match the prefix itself or a lookalike', () {
      expect(filter.matches('com/ivi'), isFalse);
      expect(filter.matches('com/ivix/foo'), isFalse);
      expect(filter.matches('com/other/foo'), isFalse);
    });
  });

  test('* matches every topic', () {
    final TopicFilter filter = TopicFilter('*');
    expect(filter.matches('com/ivi/can/THRESHOLD'), isTrue);
    expect(filter.matches('anything'), isTrue);
  });

  group('rejects a * that is not the whole last segment', () {
    for (final String pattern in <String>[
      'com/ivi/can*',
      'com/*/can',
      '*/can',
      'com/ivi/**',
    ]) {
      test(pattern, () {
        expect(() => TopicFilter(pattern), throwsArgumentError);
      });
    }
  });

  test('equality and hashCode follow the pattern', () {
    expect(TopicFilter('com/ivi/*'), TopicFilter('com/ivi/*'));
    expect(
      TopicFilter('com/ivi/*').hashCode,
      TopicFilter('com/ivi/*').hashCode,
    );
    expect(TopicFilter('com/ivi/*'), isNot(TopicFilter('com/other/*')));
  });

  test('toString() shows the pattern', () {
    expect(TopicFilter('com/ivi/*').toString(), 'TopicFilter(com/ivi/*)');
  });
}
