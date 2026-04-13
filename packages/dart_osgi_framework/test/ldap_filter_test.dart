import 'package:dart_osgi_framework/dart_osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  // ── Direct filter subclass tests ──────────────────────────────────

  group('EqualityFilter', () {
    test('matches when property equals value', () {
      final filter = EqualityFilter('color', 'red');
      expect(filter.matches({'color': 'red'}), isTrue);
    });

    test('does not match when property differs', () {
      final filter = EqualityFilter('color', 'red');
      expect(filter.matches({'color': 'blue'}), isFalse);
    });

    test('does not match when property is missing', () {
      final filter = EqualityFilter('color', 'red');
      expect(filter.matches({'size': 'large'}), isFalse);
    });

    test('compares via toString on non-string values', () {
      final filter = EqualityFilter('count', '42');
      expect(filter.matches({'count': 42}), isTrue);
    });
  });

  group('PresenceFilter', () {
    test('matches when property is present', () {
      final filter = PresenceFilter('key');
      expect(filter.matches({'key': 'anything'}), isTrue);
    });

    test('does not match when property is absent', () {
      final filter = PresenceFilter('key');
      expect(filter.matches({'other': 'value'}), isFalse);
    });
  });

  group('GreaterOrEqualFilter', () {
    test('numeric >= match', () {
      final filter = GreaterOrEqualFilter('version', '3');
      expect(filter.matches({'version': '5'}), isTrue);
      expect(filter.matches({'version': '3'}), isTrue);
    });

    test('numeric >= no match', () {
      final filter = GreaterOrEqualFilter('version', '3');
      expect(filter.matches({'version': '2'}), isFalse);
    });

    test('string >= comparison when not numeric', () {
      final filter = GreaterOrEqualFilter('name', 'beta');
      expect(filter.matches({'name': 'gamma'}), isTrue);
      expect(filter.matches({'name': 'beta'}), isTrue);
      expect(filter.matches({'name': 'alpha'}), isFalse);
    });

    test('returns false when property is missing', () {
      final filter = GreaterOrEqualFilter('version', '3');
      expect(filter.matches({}), isFalse);
    });
  });

  group('LessOrEqualFilter', () {
    test('numeric <= match', () {
      final filter = LessOrEqualFilter('version', '5');
      expect(filter.matches({'version': '3'}), isTrue);
      expect(filter.matches({'version': '5'}), isTrue);
    });

    test('numeric <= no match', () {
      final filter = LessOrEqualFilter('version', '5');
      expect(filter.matches({'version': '7'}), isFalse);
    });

    test('string <= comparison when not numeric', () {
      final filter = LessOrEqualFilter('name', 'beta');
      expect(filter.matches({'name': 'alpha'}), isTrue);
      expect(filter.matches({'name': 'beta'}), isTrue);
      expect(filter.matches({'name': 'gamma'}), isFalse);
    });

    test('returns false when property is missing', () {
      final filter = LessOrEqualFilter('version', '5');
      expect(filter.matches({}), isFalse);
    });
  });

  group('AndFilter', () {
    test('matches when all children match', () {
      final filter = AndFilter([
        EqualityFilter('a', '1'),
        EqualityFilter('b', '2'),
      ]);
      expect(filter.matches({'a': '1', 'b': '2'}), isTrue);
    });

    test('fails when one child does not match', () {
      final filter = AndFilter([
        EqualityFilter('a', '1'),
        EqualityFilter('b', '2'),
      ]);
      expect(filter.matches({'a': '1', 'b': '9'}), isFalse);
    });
  });

  group('OrFilter', () {
    test('matches when at least one child matches', () {
      final filter = OrFilter([
        EqualityFilter('a', '1'),
        EqualityFilter('b', '2'),
      ]);
      expect(filter.matches({'a': '1', 'b': '9'}), isTrue);
    });

    test('fails when no children match', () {
      final filter = OrFilter([
        EqualityFilter('a', '1'),
        EqualityFilter('b', '2'),
      ]);
      expect(filter.matches({'a': '9', 'b': '9'}), isFalse);
    });
  });

  group('NotFilter', () {
    test('negates child filter', () {
      final filter = NotFilter(EqualityFilter('a', '1'));
      expect(filter.matches({'a': '1'}), isFalse);
      expect(filter.matches({'a': '2'}), isTrue);
    });
  });

  // ── Parser tests ──────────────────────────────────────────────────

  group('LdapFilter.parse', () {
    test('simple equality "(key=value)"', () {
      final filter = LdapFilter.parse('(color=red)');
      expect(filter, isA<EqualityFilter>());
      expect(filter.matches({'color': 'red'}), isTrue);
      expect(filter.matches({'color': 'blue'}), isFalse);
    });

    test('presence "(key=*)"', () {
      final filter = LdapFilter.parse('(key=*)');
      expect(filter, isA<PresenceFilter>());
      expect(filter.matches({'key': 'anything'}), isTrue);
      expect(filter.matches({'other': 'x'}), isFalse);
    });

    test('greater or equal "(version>=3)"', () {
      final filter = LdapFilter.parse('(version>=3)');
      expect(filter, isA<GreaterOrEqualFilter>());
      expect(filter.matches({'version': '5'}), isTrue);
      expect(filter.matches({'version': '2'}), isFalse);
    });

    test('less or equal "(version<=5)"', () {
      final filter = LdapFilter.parse('(version<=5)');
      expect(filter, isA<LessOrEqualFilter>());
      expect(filter.matches({'version': '3'}), isTrue);
      expect(filter.matches({'version': '7'}), isFalse);
    });

    test('AND "(&(a=1)(b=2))"', () {
      final filter = LdapFilter.parse('(&(a=1)(b=2))');
      expect(filter, isA<AndFilter>());
      expect(filter.matches({'a': '1', 'b': '2'}), isTrue);
      expect(filter.matches({'a': '1', 'b': '9'}), isFalse);
    });

    test('OR "(|(a=1)(b=2))"', () {
      final filter = LdapFilter.parse('(|(a=1)(b=2))');
      expect(filter, isA<OrFilter>());
      expect(filter.matches({'a': '1'}), isTrue);
      expect(filter.matches({'b': '2'}), isTrue);
      expect(filter.matches({'c': '3'}), isFalse);
    });

    test('NOT "(!(a=1))"', () {
      final filter = LdapFilter.parse('(!(a=1))');
      expect(filter, isA<NotFilter>());
      expect(filter.matches({'a': '1'}), isFalse);
      expect(filter.matches({'a': '2'}), isTrue);
    });

    test('nested "(&(a=1)(|(b=2)(c=3)))"', () {
      final filter = LdapFilter.parse('(&(a=1)(|(b=2)(c=3)))');
      expect(filter.matches({'a': '1', 'b': '2'}), isTrue);
      expect(filter.matches({'a': '1', 'c': '3'}), isTrue);
      expect(filter.matches({'a': '1', 'b': '9'}), isFalse);
      expect(filter.matches({'a': '0', 'b': '2'}), isFalse);
    });

    group('parser errors', () {
      test('missing opening paren', () {
        expect(
          () => LdapFilter.parse('key=value'),
          throwsA(isA<FilterParseException>()),
        );
      });

      test('missing closing paren', () {
        expect(
          () => LdapFilter.parse('(key=value'),
          throwsA(isA<FilterParseException>()),
        );
      });

      test('unexpected characters after filter', () {
        expect(
          () => LdapFilter.parse('(key=value)extra'),
          throwsA(isA<FilterParseException>()),
        );
      });

      test('empty attribute name', () {
        expect(
          () => LdapFilter.parse('(=value)'),
          throwsA(isA<FilterParseException>()),
        );
      });

      test('missing operator', () {
        // attribute with no =, >=, or <= before closing paren
        expect(
          () => LdapFilter.parse('(key)'),
          throwsA(isA<FilterParseException>()),
        );
      });
    });

    group('security limits', () {
      test('max depth exceeded with >32 nested NOTs', () {
        // Build 33 nested NOT filters: (!(!(!(... ))))
        var filter = '(a=1)';
        for (var i = 0; i < 33; i++) {
          filter = '(!$filter)';
        }
        expect(
          () => LdapFilter.parse(filter),
          throwsA(
            isA<FilterParseException>().having(
              (e) => e.message,
              'message',
              contains('maximum nesting depth'),
            ),
          ),
        );
      });

      test('max input length exceeded with >4096 chars', () {
        final longFilter = '(key=${'x' * 4096})';
        expect(
          () => LdapFilter.parse(longFilter),
          throwsA(
            isA<FilterParseException>().having(
              (e) => e.message,
              'message',
              contains('maximum length'),
            ),
          ),
        );
      });
    });
  });

  group('FilterParseException', () {
    test('toString() includes message and input', () {
      final ex = FilterParseException('bad input', '(broken');
      expect(ex.toString(), contains('FilterParseException'));
      expect(ex.toString(), contains('bad input'));
      expect(ex.toString(), contains('(broken'));
    });
  });
}
