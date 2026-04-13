import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('TopicFilter', () {
    group('exact match', () {
      test('matches identical topic', () {
        final filter = TopicFilter('com/ivi/can/THRESHOLD_EXCEEDED');
        expect(filter.matches('com/ivi/can/THRESHOLD_EXCEEDED'), isTrue);
      });

      test('rejects different topic', () {
        final filter = TopicFilter('com/ivi/can/THRESHOLD_EXCEEDED');
        expect(filter.matches('com/ivi/can/OTHER'), isFalse);
      });

      test('rejects prefix of pattern', () {
        final filter = TopicFilter('com/ivi/can/THRESHOLD_EXCEEDED');
        expect(filter.matches('com/ivi/can'), isFalse);
      });

      test('rejects extension of pattern', () {
        final filter = TopicFilter('com/ivi/can');
        expect(filter.matches('com/ivi/can/EXTRA'), isFalse);
      });
    });

    group('wildcard suffix', () {
      test('matches topic under prefix', () {
        final filter = TopicFilter('com/ivi/*');
        expect(filter.matches('com/ivi/can/THRESHOLD'), isTrue);
      });

      test('matches immediate child', () {
        final filter = TopicFilter('com/ivi/*');
        expect(filter.matches('com/ivi/foo'), isTrue);
      });

      test('rejects topic not under prefix', () {
        final filter = TopicFilter('com/ivi/*');
        expect(filter.matches('com/other/foo'), isFalse);
      });

      test('rejects partial prefix match', () {
        final filter = TopicFilter('com/ivi/*');
        expect(filter.matches('com/ivix/foo'), isFalse);
      });
    });

    group('root wildcard', () {
      test('matches any topic', () {
        final filter = TopicFilter('*');
        expect(filter.matches('com/ivi/can/THRESHOLD'), isTrue);
        expect(filter.matches('anything'), isTrue);
        expect(filter.matches(''), isTrue);
      });
    });

    group('toString()', () {
      test('includes pattern', () {
        expect(TopicFilter('com/ivi/*').toString(), 'TopicFilter(com/ivi/*)');
      });

      test('exact pattern', () {
        expect(
          TopicFilter('com/ivi/can').toString(),
          'TopicFilter(com/ivi/can)',
        );
      });

      test('root wildcard', () {
        expect(TopicFilter('*').toString(), 'TopicFilter(*)');
      });
    });

    group('equality and hashCode', () {
      test('equal filters with same pattern', () {
        final a = TopicFilter('com/ivi/*');
        final b = TopicFilter('com/ivi/*');
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('not equal with different pattern', () {
        final a = TopicFilter('com/ivi/*');
        final b = TopicFilter('com/other/*');
        expect(a, isNot(equals(b)));
      });

      test('identical filter equals itself', () {
        final filter = TopicFilter('com/ivi/*');
        expect(filter == filter, isTrue);
      });

      test('not equal to non-TopicFilter', () {
        final filter = TopicFilter('com/ivi/*');
        // ignore: unrelated_type_equality_checks
        expect(filter == 'com/ivi/*', isFalse);
      });
    });

    group('edge cases', () {
      test('empty topic with exact match', () {
        final filter = TopicFilter('');
        expect(filter.matches(''), isTrue);
        expect(filter.matches('anything'), isFalse);
      });

      test('pattern with no slash', () {
        final filter = TopicFilter('simple');
        expect(filter.matches('simple'), isTrue);
        expect(filter.matches('other'), isFalse);
      });

      test('root wildcard matches empty string', () {
        final filter = TopicFilter('*');
        expect(filter.matches(''), isTrue);
      });
    });
  });
}
