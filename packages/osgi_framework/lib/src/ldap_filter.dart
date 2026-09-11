/// LDAP-style property filters, as the OSGi service registry uses them.
///
/// Supported:
///
///  * equality `(key=value)` and presence `(key=*)`
///  * `(key>=value)` and `(key<=value)` -- numeric when both sides are numbers,
///    string comparison otherwise
///  * `(&(a)(b)...)`, `(|(a)(b)...)` and `(!(a))`
///
/// Not supported: substring patterns, `~=`, and backslash escapes. A `*` inside
/// a value is compared literally, so `(name=nav*)` matches only the string
/// `nav*` -- it narrows to nothing rather than widening to a prefix match.
/// `~=` is rejected outright. Keys are case-sensitive, and a collection-valued
/// property is compared by its `toString()`, not element by element.
///
/// A property whose value is null is treated as absent.
sealed class LdapFilter {
  const LdapFilter();

  /// Longest filter string [parse] accepts, so a runaway or hostile string
  /// cannot make parsing expensive.
  static const int maxInputLength = 4096;

  /// Deepest nesting [parse] accepts, so recursion cannot exhaust the stack.
  static const int maxDepth = 32;

  /// Parse [input].
  ///
  /// Throws [FilterParseException], which is a [FormatException], on malformed
  /// input or when a limit above is exceeded.
  static LdapFilter parse(String input) {
    final String trimmed = input.trim();
    if (trimmed.length > maxInputLength) {
      throw FilterParseException(
        'Filter exceeds maximum length of $maxInputLength characters',
        '${trimmed.substring(0, 80)}...',
      );
    }
    final _FilterParser parser = _FilterParser(trimmed);
    final LdapFilter filter = parser.parseFilter();
    if (parser._pos != trimmed.length) {
      throw FilterParseException(
        'Unexpected characters after filter at position ${parser._pos}',
        trimmed,
        parser._pos,
      );
    }
    return filter;
  }

  /// Whether [properties] satisfy this filter.
  bool matches(Map<String, Object?> properties);
}

/// `(key=value)`: the property's `toString()` equals [value].
class EqualityFilter extends LdapFilter {
  const EqualityFilter(this.attribute, this.value);

  final String attribute;
  final String value;

  @override
  bool matches(Map<String, Object?> properties) {
    final Object? property = properties[attribute];
    return property != null && property.toString() == value;
  }
}

/// `(key=*)`: the property is present and not null.
class PresenceFilter extends LdapFilter {
  const PresenceFilter(this.attribute);

  final String attribute;

  @override
  bool matches(Map<String, Object?> properties) =>
      properties[attribute] != null;
}

/// `(key>=value)`.
class GreaterOrEqualFilter extends LdapFilter {
  const GreaterOrEqualFilter(this.attribute, this.value);

  final String attribute;
  final String value;

  @override
  bool matches(Map<String, Object?> properties) {
    final Object? property = properties[attribute];
    return property != null && _compare(property, value) >= 0;
  }
}

/// `(key<=value)`.
class LessOrEqualFilter extends LdapFilter {
  const LessOrEqualFilter(this.attribute, this.value);

  final String attribute;
  final String value;

  @override
  bool matches(Map<String, Object?> properties) {
    final Object? property = properties[attribute];
    return property != null && _compare(property, value) <= 0;
  }
}

/// `(&(a)(b)...)`: every child matches.
class AndFilter extends LdapFilter {
  const AndFilter(this.children);

  final List<LdapFilter> children;

  @override
  bool matches(Map<String, Object?> properties) =>
      children.every((LdapFilter f) => f.matches(properties));
}

/// `(|(a)(b)...)`: at least one child matches.
class OrFilter extends LdapFilter {
  const OrFilter(this.children);

  final List<LdapFilter> children;

  @override
  bool matches(Map<String, Object?> properties) =>
      children.any((LdapFilter f) => f.matches(properties));
}

/// `(!(a))`: the child does not match.
class NotFilter extends LdapFilter {
  const NotFilter(this.child);

  final LdapFilter child;

  @override
  bool matches(Map<String, Object?> properties) => !child.matches(properties);
}

/// Raised when a filter string cannot be parsed.
///
/// A [FormatException], so code that depends only on `osgi_api` can catch it
/// without naming this type.
class FilterParseException extends FormatException {
  FilterParseException(super.message, String super.source, [super.offset]);

  /// The filter string, or its first 80 characters when it was too long.
  String get input => source as String;

  @override
  String toString() => 'FilterParseException: $message in "$source"';
}

/// Numeric when both sides are numbers, so `(height>=720)` does not compare
/// `"1080"` and `"720"` as strings.
int _compare(Object property, String value) {
  final num? left = property is num
      ? property
      : num.tryParse(property.toString());
  final num? right = num.tryParse(value);
  if (left != null && right != null) return left.compareTo(right);
  return property.toString().compareTo(value);
}

// Recursive descent over the grammar in the class comment.
class _FilterParser {
  _FilterParser(this._input);

  final String _input;
  int _pos = 0;
  int _depth = 0;

  /// Characters that end an attribute name. `~` and `!` are here so `~=` and
  /// `!=` are rejected rather than read as part of the name; `(` and `)` so a
  /// misplaced parenthesis is an error rather than an odd attribute.
  static const String _attributeStops = '=<>~!()';

  LdapFilter parseFilter() {
    _depth++;
    if (_depth > LdapFilter.maxDepth) {
      throw FilterParseException(
        'Filter exceeds maximum nesting depth of ${LdapFilter.maxDepth}',
        _input,
        _pos,
      );
    }
    _expect('(');
    final LdapFilter filter = switch (_peek()) {
      '&' => AndFilter(_parseList()),
      '|' => OrFilter(_parseList()),
      '!' => _parseNot(),
      _ => _parseItem(),
    };
    _expect(')');
    _depth--;
    return filter;
  }

  LdapFilter _parseNot() {
    _pos++; // '!'
    return NotFilter(parseFilter());
  }

  List<LdapFilter> _parseList() {
    _pos++; // '&' or '|'
    final List<LdapFilter> filters = <LdapFilter>[];
    while (_peek() == '(') {
      filters.add(parseFilter());
    }
    if (filters.isEmpty) {
      throw FilterParseException(
        'Expected at least one filter at position $_pos',
        _input,
        _pos,
      );
    }
    return filters;
  }

  LdapFilter _parseItem() {
    final int start = _pos;
    while (_pos < _input.length && !_attributeStops.contains(_input[_pos])) {
      _pos++;
    }
    final String attribute = _input.substring(start, _pos);
    if (attribute.isEmpty) {
      throw FilterParseException(
        'Expected attribute name at position $_pos',
        _input,
        _pos,
      );
    }

    if (_tryConsume('>=')) return GreaterOrEqualFilter(attribute, _readValue());
    if (_tryConsume('<=')) return LessOrEqualFilter(attribute, _readValue());
    if (_tryConsume('=')) {
      final String value = _readValue();
      return value == '*'
          ? PresenceFilter(attribute)
          : EqualityFilter(attribute, value);
    }
    throw FilterParseException(
      'Expected operator (=, >=, <=) at position $_pos',
      _input,
      _pos,
    );
  }

  String _readValue() {
    final int start = _pos;
    while (_pos < _input.length && _input[_pos] != ')') {
      _pos++;
    }
    return _input.substring(start, _pos);
  }

  String _peek() {
    if (_pos >= _input.length) {
      throw FilterParseException('Unexpected end of input', _input, _pos);
    }
    return _input[_pos];
  }

  void _expect(String ch) {
    if (_pos >= _input.length || _input[_pos] != ch) {
      throw FilterParseException(
        'Expected "$ch" at position $_pos',
        _input,
        _pos,
      );
    }
    _pos++;
  }

  bool _tryConsume(String token) {
    if (!_input.startsWith(token, _pos)) return false;
    _pos += token.length;
    return true;
  }
}
