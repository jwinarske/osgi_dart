/// LDAP-style property filter for OSGi service matching.
///
/// Supports:
/// - Equality: `(key=value)`
/// - Greater-or-equal: `(key>=value)`
/// - Less-or-equal: `(key<=value)`
/// - Presence: `(key=*)`
/// - AND: `(&(filter1)(filter2))`
/// - OR: `(|(filter1)(filter2))`
/// - NOT: `(!(filter))`
///
/// Values are compared as strings by default. If both sides parse as
/// [num], numeric comparison is used for `>=` and `<=`.
sealed class LdapFilter {
  const LdapFilter();

  /// Parse an LDAP filter string.
  ///
  /// Throws [FilterParseException] on malformed input.
  static LdapFilter parse(String input) {
    final parser = _FilterParser(input.trim());
    final filter = parser.parseFilter();
    if (parser._pos != parser._input.length) {
      throw FilterParseException(
        'Unexpected characters after filter at position ${parser._pos}',
        input,
      );
    }
    return filter;
  }

  /// Evaluate this filter against a property map.
  bool matches(Map<String, Object> properties);
}

/// Matches when a property equals a value.
class EqualityFilter extends LdapFilter {
  const EqualityFilter(this.attribute, this.value);
  final String attribute;
  final String value;

  @override
  bool matches(Map<String, Object> properties) {
    final prop = properties[attribute];
    if (prop == null) return false;
    return prop.toString() == value;
  }
}

/// Matches when a property is present (any value).
class PresenceFilter extends LdapFilter {
  const PresenceFilter(this.attribute);
  final String attribute;

  @override
  bool matches(Map<String, Object> properties) =>
      properties.containsKey(attribute);
}

/// Matches when a property is >= a value (numeric if possible, else string).
class GreaterOrEqualFilter extends LdapFilter {
  const GreaterOrEqualFilter(this.attribute, this.value);
  final String attribute;
  final String value;

  @override
  bool matches(Map<String, Object> properties) {
    final prop = properties[attribute];
    if (prop == null) return false;
    final propNum = num.tryParse(prop.toString());
    final valNum = num.tryParse(value);
    if (propNum != null && valNum != null) return propNum >= valNum;
    return prop.toString().compareTo(value) >= 0;
  }
}

/// Matches when a property is <= a value (numeric if possible, else string).
class LessOrEqualFilter extends LdapFilter {
  const LessOrEqualFilter(this.attribute, this.value);
  final String attribute;
  final String value;

  @override
  bool matches(Map<String, Object> properties) {
    final prop = properties[attribute];
    if (prop == null) return false;
    final propNum = num.tryParse(prop.toString());
    final valNum = num.tryParse(value);
    if (propNum != null && valNum != null) return propNum <= valNum;
    return prop.toString().compareTo(value) <= 0;
  }
}

/// Matches when all child filters match.
class AndFilter extends LdapFilter {
  const AndFilter(this.children);
  final List<LdapFilter> children;

  @override
  bool matches(Map<String, Object> properties) =>
      children.every((f) => f.matches(properties));
}

/// Matches when any child filter matches.
class OrFilter extends LdapFilter {
  const OrFilter(this.children);
  final List<LdapFilter> children;

  @override
  bool matches(Map<String, Object> properties) =>
      children.any((f) => f.matches(properties));
}

/// Matches when the child filter does NOT match.
class NotFilter extends LdapFilter {
  const NotFilter(this.child);
  final LdapFilter child;

  @override
  bool matches(Map<String, Object> properties) => !child.matches(properties);
}

/// Thrown when a filter string cannot be parsed.
class FilterParseException implements Exception {
  FilterParseException(this.message, this.input);
  final String message;
  final String input;

  @override
  String toString() => 'FilterParseException: $message in "$input"';
}

// ── Recursive descent parser ────────────────────────────────────────

class _FilterParser {
  _FilterParser(this._input);

  final String _input;
  int _pos = 0;

  LdapFilter parseFilter() {
    _expect('(');
    final filter = _parseFilterComp();
    _expect(')');
    return filter;
  }

  LdapFilter _parseFilterComp() {
    final ch = _peek();
    return switch (ch) {
      '&' => _parseAnd(),
      '|' => _parseOr(),
      '!' => _parseNot(),
      _ => _parseItem(),
    };
  }

  LdapFilter _parseAnd() {
    _advance(); // consume '&'
    return AndFilter(_parseFilterList());
  }

  LdapFilter _parseOr() {
    _advance(); // consume '|'
    return OrFilter(_parseFilterList());
  }

  LdapFilter _parseNot() {
    _advance(); // consume '!'
    return NotFilter(parseFilter());
  }

  List<LdapFilter> _parseFilterList() {
    final filters = <LdapFilter>[];
    while (_peek() == '(') {
      filters.add(parseFilter());
    }
    if (filters.isEmpty) {
      throw FilterParseException(
        'Expected at least one filter at position $_pos',
        _input,
      );
    }
    return filters;
  }

  LdapFilter _parseItem() {
    final attr = _readUntilAny('>=<!');
    if (attr.isEmpty) {
      throw FilterParseException(
        'Expected attribute name at position $_pos',
        _input,
      );
    }

    if (_tryConsume('>=')) {
      final value = _readUntil(')');
      return GreaterOrEqualFilter(attr, value);
    }
    if (_tryConsume('<=')) {
      final value = _readUntil(')');
      return LessOrEqualFilter(attr, value);
    }
    if (_tryConsume('=')) {
      final value = _readUntil(')');
      if (value == '*') return PresenceFilter(attr);
      return EqualityFilter(attr, value);
    }

    throw FilterParseException(
      'Expected operator (=, >=, <=) at position $_pos',
      _input,
    );
  }

  String _peek() {
    if (_pos >= _input.length) {
      throw FilterParseException('Unexpected end of input', _input);
    }
    return _input[_pos];
  }

  void _advance() => _pos++;

  void _expect(String ch) {
    if (_pos >= _input.length || _input[_pos] != ch) {
      throw FilterParseException('Expected "$ch" at position $_pos', _input);
    }
    _pos++;
  }

  bool _tryConsume(String s) {
    if (_input.startsWith(s, _pos)) {
      _pos += s.length;
      return true;
    }
    return false;
  }

  String _readUntil(String stopChar) {
    final start = _pos;
    while (_pos < _input.length && _input[_pos] != stopChar) {
      _pos++;
    }
    return _input.substring(start, _pos);
  }

  String _readUntilAny(String stopChars) {
    final start = _pos;
    while (_pos < _input.length && !stopChars.contains(_input[_pos])) {
      _pos++;
    }
    return _input.substring(start, _pos);
  }
}
