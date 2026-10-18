import 'decoder.dart';
import 'encoder.dart';
import 'exception.dart';
import 'options.dart';
import 'text.dart';

/// Rewrites a standard SCON document into the minified representation (§14).
///
/// The unary semicolon encoding is reversible: [expandScon] restores the
/// standard form of the same data. Comments and directives are not data, so
/// they are dropped by the rewrite.
String minifyScon(
  String source, {
  SconDecodeOptions options = const SconDecodeOptions(),
}) {
  final value = decodeScon(source, options: options);
  final lines = <_FlatLine>[];
  _flatten(value, 0, lines);
  if (lines.isEmpty) return '';
  final out = StringBuffer();
  var previousDepth = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (i > 0) {
      if (line.depth == previousDepth) {
        out.write(';');
      } else if (line.depth < previousDepth) {
        // N semicolons close N-1 levels (SCON §14).
        out.write(';' * (previousDepth - line.depth + 1));
      }
    }
    out.write(line.text);
    previousDepth = line.depth;
  }
  return out.toString();
}

/// Expands the minified representation back into standard-form SCON text.
String expandScon(String minified) {
  final tokens = _tokenize(minified);
  if (tokens.isNotEmpty && tokens.first is _Semicolons) {
    throw const SconFormatException(
        'a dedent cannot start the document', 1, 1);
  }
  final lines = <_FlatLine>[];
  var depth = 0;
  var lastOpensBlock = false;
  for (final token in tokens) {
    switch (token) {
      case _Semicolons(:final count):
        depth -= count - 1;
        if (depth < 0) {
          throw const SconFormatException(
              'a dedent goes above the document root', 1, 1);
        }
        lastOpensBlock = false;
      case _Open(:final key):
        lines.add(_FlatLine(depth, '$key:'));
        depth += 1;
        lastOpensBlock = true;
      case _ItemOpen():
        lines.add(_FlatLine(depth, '-'));
        depth += 1;
        lastOpensBlock = true;
      case _Entry(:final key, :final value):
        lines.add(_FlatLine(depth, '$key: $value'));
        lastOpensBlock = false;
      case _Item(:final value):
        lines.add(_FlatLine(depth, '- $value'));
        lastOpensBlock = false;
      case _Value(:final value):
        lines.add(_FlatLine(depth, value));
        lastOpensBlock = false;
      case _EmptyArray(:final key):
        lines.add(_FlatLine(depth, '$key[0]:'));
        lastOpensBlock = false;
    }
  }
  if (lastOpensBlock) {
    throw SconFormatException(
      '"${lines.last.text}" opens a block but nothing follows it',
      1,
      1,
    );
  }
  final out = StringBuffer();
  for (final line in lines) {
    out.writeln('${' ' * line.depth}${line.text}');
  }
  return out.toString();
}

/// Decodes a minified document directly (expand, then decode).
Object? decodeMinified(
  String minified, {
  SconDecodeOptions options = const SconDecodeOptions(),
}) =>
    decodeScon(expandScon(minified), options: options);

/// Encodes a value straight into the minified representation.
String encodeMinified(
  Object? value, {
  SconEncodeOptions options = const SconEncodeOptions(),
}) =>
    minifyScon(encodeScon(value, options: options));

class _FlatLine {
  const _FlatLine(this.depth, this.text);

  final int depth;
  final String text;
}

void _flatten(Object? value, int depth, List<_FlatLine> lines) {
  if (value is Map) {
    if (value.isEmpty) {
      throw ArgumentError(
        'SCON cannot represent an empty object: it has no marker distinct '
        'from a null value',
      );
    }
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(
            key, 'key', 'SCON object keys must be strings');
      }
      final encoded = encodeKey(key);
      final child = entry.value;
      if (child is Map) {
        lines.add(_FlatLine(depth, '$encoded:'));
        _flatten(child, depth + 1, lines);
      } else if (child is List) {
        if (child.isEmpty) {
          lines.add(_FlatLine(depth, '$encoded[0]:'));
        } else {
          lines.add(_FlatLine(depth, '$encoded:'));
          _flattenList(child, depth + 1, lines);
        }
      } else {
        lines.add(_FlatLine(depth, '$encoded: ${encodeScalarValue(child)}'));
      }
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      throw const SconUnsupportedException(
        'the minified form cannot represent an empty array',
      );
    }
    _flattenList(value, depth, lines);
    return;
  }
  lines.add(_FlatLine(depth, encodeScalarValue(value)));
}

void _flattenList(List<dynamic> list, int depth, List<_FlatLine> lines) {
  for (final item in list) {
    if (item is Map) {
      lines.add(_FlatLine(depth, '-'));
      _flatten(item, depth + 1, lines);
    } else if (item is List) {
      if (item.isEmpty) {
        throw const SconUnsupportedException(
          'the minified form cannot represent an empty array',
        );
      }
      lines.add(_FlatLine(depth, '-'));
      _flattenList(item, depth + 1, lines);
    } else {
      lines.add(_FlatLine(depth, '- ${encodeScalarValue(item)}'));
    }
  }
}

sealed class _Token {
  const _Token();
}

class _Semicolons extends _Token {
  const _Semicolons(this.count);

  final int count;
}

class _Open extends _Token {
  const _Open(this.key);

  final String key;
}

class _ItemOpen extends _Token {
  const _ItemOpen();
}

class _Entry extends _Token {
  const _Entry(this.key, this.value);

  final String key;
  final String value;
}

class _Item extends _Token {
  const _Item(this.value);

  final String value;
}

class _Value extends _Token {
  const _Value(this.value);

  final String value;
}

class _EmptyArray extends _Token {
  const _EmptyArray(this.key);

  final String key;
}

List<_Token> _tokenize(String input) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < input.length) {
    final code = input.codeUnitAt(i);
    if (code == 0x20 || code == 0x0A || code == 0x0D || code == 0x09) {
      i++;
      continue;
    }
    if (code == 0x3B) {
      var count = 0;
      while (i < input.length && input.codeUnitAt(i) == 0x3B) {
        count++;
        i++;
      }
      tokens.add(_Semicolons(count));
      continue;
    }
    if (code == 0x2D) {
      // '-' starts an array item; a key may not start with '-' unquoted, so
      // anything else after it belongs to the item (e.g. "-a: 1").
      if (i + 1 >= input.length || input.codeUnitAt(i + 1) == 0x3B) {
        tokens.add(const _ItemOpen());
        i++;
        continue;
      }
      if (input.codeUnitAt(i + 1) == 0x20) {
        i += 2;
        final value = _readValue(input, () => i, (next) => i = next);
        tokens.add(_Item(value));
        continue;
      }
      tokens.add(const _ItemOpen());
      i++;
      continue;
    }
    if (code == 0x22) {
      final quoted = _readQuoted(input, i);
      final after = quoted.end;
      var cursor = after;
      while (cursor < input.length && input.codeUnitAt(cursor) == 0x20) {
        cursor++;
      }
      if (cursor < input.length && input.codeUnitAt(cursor) == 0x3A) {
        i = _readKeyAndValue(input, i, tokens);
        continue;
      }
      tokens.add(_Value(input.substring(i, after)));
      i = after;
      continue;
    }
    if (isKeyChar(code)) {
      i = _readKeyAndValue(input, i, tokens);
      continue;
    }
    throw SconFormatException('unexpected character "$code" in minified form', 1, 1);
  }
  return tokens;
}

int _readKeyAndValue(String input, int start, List<_Token> tokens) {
  var i = start;
  String key;
  if (input.codeUnitAt(i) == 0x22) {
    final quoted = _readQuoted(input, i);
    key = input.substring(i, quoted.end);
    i = quoted.end;
  } else {
    final keyStart = i;
    while (i < input.length && isKeyChar(input.codeUnitAt(i))) {
      i++;
    }
    key = input.substring(keyStart, i);
  }
  if (i < input.length && input.codeUnitAt(i) == 0x5B) {
    // `key[0]:` — the empty array, which indentation alone cannot express.
    final close = input.indexOf(']', i);
    if (close < 0) {
      throw const SconFormatException(
          'unterminated "[count]" in minified form', 1, 1);
    }
    final count = int.tryParse(input.substring(i + 1, close).trim());
    if (count == null) {
      throw const SconFormatException(
          'invalid array count in minified form', 1, 1);
    }
    if (close + 1 >= input.length || input.codeUnitAt(close + 1) != 0x3A) {
      throw const SconFormatException(
          'expected ":" after an array count in minified form', 1, 1);
    }
    if (count != 0) {
      throw const SconUnsupportedException(
        'the minified form only carries empty arrays as "[0]:"; write the '
        'array in standard form',
      );
    }
    tokens.add(_EmptyArray(key));
    return close + 2;
  }
  if (i >= input.length || input.codeUnitAt(i) != 0x3A) {
    // A bare scalar (no colon): the root value of a minified document.
    final value = _readValue(input, () => start, (next) => i = next);
    tokens.add(_Value(value));
    return i;
  }
  i++;
  if (i < input.length && input.codeUnitAt(i) == 0x20) {
    while (i < input.length && input.codeUnitAt(i) == 0x20) {
      i++;
    }
    final value = _readValue(input, () => i, (next) => i = next);
    tokens.add(_Entry(key, value));
    return i;
  }
  tokens.add(_Open(key));
  return i;
}

String _readValue(String input, int Function() readIndex, void Function(int) writeIndex) {
  var i = readIndex();
  final out = StringBuffer();
  while (i < input.length) {
    final code = input.codeUnitAt(i);
    if (code == 0x3B) break;
    if (code == 0x22) {
      final quoted = _readQuoted(input, i);
      out.write(input.substring(i, quoted.end));
      i = quoted.end;
      continue;
    }
    out.writeCharCode(code);
    i++;
  }
  writeIndex(i);
  return out.toString().trim();
}

({String text, int end}) _readQuoted(String input, int start) {
  var i = start + 1;
  var escaped = false;
  while (i < input.length) {
    final code = input.codeUnitAt(i);
    if (escaped) {
      escaped = false;
    } else if (code == 0x5C) {
      escaped = true;
    } else if (code == 0x22) {
      return (text: input.substring(start, i + 1), end: i + 1);
    }
    i++;
  }
  throw const SconFormatException(
      'unterminated quoted string in minified form', 1, 1);
}
