import 'package:osgi_framework/osgi_framework.dart';
import 'package:test/test.dart';

void main() {
  group('EqualityFilter', () {
    const LdapFilter filter = EqualityFilter('color', 'red');

    test('matches an equal property', () {
      expect(filter.matches(<String, Object?>{'color': 'red'}), isTrue);
    });

    test('does not match a different or missing property', () {
      expect(filter.matches(<String, Object?>{'color': 'blue'}), isFalse);
      expect(filter.matches(<String, Object?>{'size': 'large'}), isFalse);
    });

    test('compares a non-string property by toString', () {
      expect(
        const EqualityFilter(
          'count',
          '42',
        ).matches(<String, Object?>{'count': 42}),
        isTrue,
      );
    });

    test('a null property is absent', () {
      expect(
        const EqualityFilter(
          'color',
          'null',
        ).matches(<String, Object?>{'color': null}),
        isFalse,
      );
    });
  });

  group('PresenceFilter', () {
    const LdapFilter filter = PresenceFilter('key');

    test('matches a present property', () {
      expect(filter.matches(<String, Object?>{'key': 'anything'}), isTrue);
    });

    test('does not match an absent or null property', () {
      expect(filter.matches(<String, Object?>{'other': 'x'}), isFalse);
      expect(filter.matches(<String, Object?>{'key': null}), isFalse);
    });
  });

  group('GreaterOrEqualFilter', () {
    test('compares numerically when both sides are numbers', () {
      const LdapFilter filter = GreaterOrEqualFilter('height', '720');
      expect(filter.matches(<String, Object?>{'height': 1080}), isTrue);
      expect(filter.matches(<String, Object?>{'height': '720'}), isTrue);
      // As strings, '1080' < '720'. That is the bug numeric comparison avoids.
      expect(filter.matches(<String, Object?>{'height': '1080'}), isTrue);
      expect(filter.matches(<String, Object?>{'height': 480}), isFalse);
    });

    test('compares strings otherwise', () {
      const LdapFilter filter = GreaterOrEqualFilter('name', 'beta');
      expect(filter.matches(<String, Object?>{'name': 'gamma'}), isTrue);
      expect(filter.matches(<String, Object?>{'name': 'beta'}), isTrue);
      expect(filter.matches(<String, Object?>{'name': 'alpha'}), isFalse);
    });

    test('does not match a missing property', () {
      expect(
        const GreaterOrEqualFilter('height', '3').matches(<String, Object?>{}),
        isFalse,
      );
    });
  });

  group('LessOrEqualFilter', () {
    test('compares numerically when both sides are numbers', () {
      const LdapFilter filter = LessOrEqualFilter('version', '10');
      expect(filter.matches(<String, Object?>{'version': 9}), isTrue);
      expect(filter.matches(<String, Object?>{'version': '10'}), isTrue);
      expect(filter.matches(<String, Object?>{'version': 11.5}), isFalse);
    });

    test('compares strings otherwise', () {
      const LdapFilter filter = LessOrEqualFilter('name', 'beta');
      expect(filter.matches(<String, Object?>{'name': 'alpha'}), isTrue);
      expect(filter.matches(<String, Object?>{'name': 'gamma'}), isFalse);
    });

    test('does not match a missing property', () {
      expect(
        const LessOrEqualFilter('version', '5').matches(<String, Object?>{}),
        isFalse,
      );
    });
  });

  group('composites', () {
    const LdapFilter a1 = EqualityFilter('a', '1');
    const LdapFilter b2 = EqualityFilter('b', '2');

    test('AND needs every child', () {
      const LdapFilter filter = AndFilter(<LdapFilter>[a1, b2]);
      expect(filter.matches(<String, Object?>{'a': '1', 'b': '2'}), isTrue);
      expect(filter.matches(<String, Object?>{'a': '1', 'b': '9'}), isFalse);
    });

    test('OR needs one child', () {
      const LdapFilter filter = OrFilter(<LdapFilter>[a1, b2]);
      expect(filter.matches(<String, Object?>{'a': '1', 'b': '9'}), isTrue);
      expect(filter.matches(<String, Object?>{'a': '9', 'b': '9'}), isFalse);
    });

    test('NOT negates', () {
      const LdapFilter filter = NotFilter(a1);
      expect(filter.matches(<String, Object?>{'a': '1'}), isFalse);
      expect(filter.matches(<String, Object?>{'a': '2'}), isTrue);
    });
  });

  group('LdapFilter.parse', () {
    test('equality', () {
      final LdapFilter filter = LdapFilter.parse('(color=red)');
      expect(filter, isA<EqualityFilter>());
      expect(filter.matches(<String, Object?>{'color': 'red'}), isTrue);
    });

    test('presence', () {
      expect(LdapFilter.parse('(key=*)'), isA<PresenceFilter>());
    });

    test('>= and <=', () {
      expect(LdapFilter.parse('(version>=3)'), isA<GreaterOrEqualFilter>());
      expect(LdapFilter.parse('(version<=5)'), isA<LessOrEqualFilter>());
    });

    test('AND, OR and NOT', () {
      expect(LdapFilter.parse('(&(a=1)(b=2))'), isA<AndFilter>());
      expect(LdapFilter.parse('(|(a=1)(b=2))'), isA<OrFilter>());
      expect(LdapFilter.parse('(!(a=1))'), isA<NotFilter>());
    });

    test('nesting', () {
      final LdapFilter filter = LdapFilter.parse('(&(a=1)(|(b=2)(c=3)))');
      expect(filter.matches(<String, Object?>{'a': '1', 'b': '2'}), isTrue);
      expect(filter.matches(<String, Object?>{'a': '1', 'c': '3'}), isTrue);
      expect(filter.matches(<String, Object?>{'a': '1', 'b': '9'}), isFalse);
      expect(filter.matches(<String, Object?>{'a': '0', 'b': '2'}), isFalse);
    });

    test('surrounding whitespace is ignored', () {
      expect(LdapFilter.parse('  (a=1)\n'), isA<EqualityFilter>());
    });

    test('a * inside a value is literal, not a substring match', () {
      final LdapFilter filter = LdapFilter.parse('(name=nav*)');
      expect(filter.matches(<String, Object?>{'name': 'navigation'}), isFalse);
      expect(filter.matches(<String, Object?>{'name': 'nav*'}), isTrue);
    });

    group('rejects', () {
      for (final (String what, String input) in <(String, String)>[
        ('a missing opening paren', 'key=value'),
        ('a missing closing paren', '(key=value'),
        ('trailing characters', '(key=value)extra'),
        ('an empty attribute', '(=value)'),
        ('a missing operator', '(key)'),
        ('~=, which is unsupported', '(key~=value)'),
        ('!=, which is not LDAP', '(key!=value)'),
        ('an empty AND', '(&)'),
        ('NOT with two operands', '(!(a=1)(b=2))'),
        ('a parenthesis inside an attribute', '((a=1))'),
        ('empty input', ''),
      ]) {
        test(what, () {
          expect(
            () => LdapFilter.parse(input),
            throwsA(isA<FilterParseException>()),
          );
        });
      }

      test('as a FormatException with the position', () {
        expect(
          () => LdapFilter.parse('(key=value'),
          throwsA(
            isA<FormatException>().having(
              (FormatException e) => e.offset,
              'offset',
              10,
            ),
          ),
        );
      });
    });

    group('limits', () {
      String nestedNots(int count) {
        String filter = '(a=1)';
        for (int i = 0; i < count; i++) {
          filter = '(!$filter)';
        }
        return filter;
      }

      test('accepts nesting up to the maximum depth', () {
        expect(
          () => LdapFilter.parse(nestedNots(LdapFilter.maxDepth - 1)),
          returnsNormally,
        );
      });

      test('rejects nesting beyond it', () {
        expect(
          () => LdapFilter.parse(nestedNots(LdapFilter.maxDepth)),
          throwsA(
            isA<FilterParseException>().having(
              (FilterParseException e) => e.message,
              'message',
              contains('maximum nesting depth'),
            ),
          ),
        );
      });

      test('accepts input up to the maximum length', () {
        final String filter = '(key=${'x' * (LdapFilter.maxInputLength - 6)})';
        expect(filter.length, LdapFilter.maxInputLength);
        expect(() => LdapFilter.parse(filter), returnsNormally);
      });

      test('rejects longer input, echoing only its start', () {
        final String filter = '(key=${'x' * LdapFilter.maxInputLength})';
        expect(
          () => LdapFilter.parse(filter),
          throwsA(
            isA<FilterParseException>()
                .having(
                  (FilterParseException e) => e.message,
                  'message',
                  contains('maximum length'),
                )
                .having(
                  (FilterParseException e) => e.input.length,
                  'input',
                  lessThan(100),
                ),
          ),
        );
      });
    });
  });

  test('FilterParseException names the filter', () {
    final FilterParseException e = FilterParseException('bad input', '(broken');
    expect(e.toString(), 'FilterParseException: bad input in "(broken"');
  });
}
