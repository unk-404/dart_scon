import 'exception.dart';

/// Characters allowed in an unquoted key (SCON §9).
bool isKeyChar(int rune) {
  if (rune >= 0x30 && rune <= 0x39) return true; // 0-9
  if (rune >= 0x41 && rune <= 0x5A) return true; // A-Z
  if (rune >= 0x61 && rune <= 0x7A) return true; // a-z
  const extra = '_-.\$/~@';
  return extra.codeUnits.contains(rune);
}

/// Result of decoding a quoted string in place.
class Quoted {
  const Quoted(this.value, this.end);

  final String value;

  /// Index just past the closing quote.
  final int end;
}

Never _fail(String message, int line, int column) =>
    throw SconFormatException(message, line, column);

/// Decodes a quoted string that starts at [start] in [text].
///
/// `\uXXXX` escapes produce one code point; an isolated surrogate is rejected
/// because the spec forbids it as an escape target (SCON §24.3).
Quoted parseQuoted(String text, int start, int line) {
  if (start >= text.length || text[start] != '"') {
    _fail('expected a quoted string', line, start + 1);
  }
  final out = StringBuffer();
  var i = start + 1;
  while (i < text.length) {
    final code = text.codeUnitAt(i);
    if (code == 0x22) return Quoted(out.toString(), i + 1);
    if (code != 0x5C) {
      out.writeCharCode(code);
      i++;
      continue;
    }
    if (i + 1 >= text.length) _fail('unterminated escape sequence', line, i + 1);
    final escape = text[i + 1];
    if (escape == '"') {
      out.write('"');
    } else if (escape == r'\') {
      out.write(r'\');
    } else if (escape == '/') {
      out.write('/');
    } else if (escape == 'n') {
      out.write('\n');
    } else if (escape == 'r') {
      out.write('\r');
    } else if (escape == 't') {
      out.write('\t');
    } else if (escape == 'b') {
      out.write('\b');
    } else if (escape == 'f') {
      out.write('\f');
    } else if (escape == ';') {
      out.write(';');
    } else if (escape == 'u') {
      final next = _parseUnicodeEscape(text, i, line);
      out.writeCharCode(next.rune);
      i = next.end;
      continue;
    } else {
      _fail('unknown escape sequence "\\$escape"', line, i + 1);
    }
    i += 2;
  }
  _fail('unterminated quoted string', line, start + 1);
}

class _Rune {
  const _Rune(this.rune, this.end);

  final int rune;
  final int end;
}

_Rune _parseUnicodeEscape(String text, int backslash, int line) {
  final hexStart = backslash + 2;
  if (hexStart + 4 > text.length) _fail('truncated \\u escape', line, backslash + 1);
  final value = int.tryParse(text.substring(hexStart, hexStart + 4), radix: 16);
  if (value == null) _fail('invalid \\u escape', line, backslash + 1);
  var end = hexStart + 4;
  if (value >= 0xD800 && value <= 0xDBFF) {
    if (end + 6 > text.length ||
        text[end] != r'\' ||
        text[end + 1] != 'u') {
      _fail('a high surrogate must be followed by a low surrogate escape', line, backslash + 1);
    }
    final low = int.tryParse(text.substring(end + 2, end + 6), radix: 16);
    if (low == null || low < 0xDC00 || low > 0xDFFF) {
      _fail('invalid low surrogate escape', line, backslash + 1);
    }
    return _Rune(0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00), end + 6);
  }
  if (value >= 0xDC00 && value <= 0xDFFF) {
    _fail('an isolated low surrogate escape is not allowed', line, backslash + 1);
  }
  return _Rune(value, end);
}

final RegExp _floatString =
    RegExp(r'^-?(0|[1-9][0-9]*)\.[0-9]+([eE][+-]?[0-9]+)?$');

/// Whether [text] would be read as a number by SCON (or by a more permissive
/// implementation), i.e. a string with this shape must be quoted.
///
/// Leading zeros are included on purpose: the normative rules make `007` a
/// string, but other implementations read it as `7`, so the encoder quotes it
/// for portability (SCON §8.1 lists exactly that example).
bool looksNumeric(String text) =>
    RegExp(r'^-?[0-9]+$').hasMatch(text) || _floatString.hasMatch(text);

/// Whether [text] must be quoted to be read back as this same string.
bool needsQuotesForValue(String text) {
  if (text.isEmpty) return true;
  if (text == 'null' || text == 'true' || text == 'false') return true;
  if (text.trim() != text) return true;
  if (looksNumeric(text)) return true;
  for (final rune in text.runes) {
    if (rune < 0x20) return true;
    if (rune == 0x2C || rune == 0x3B || rune == 0x22 || rune == 0x5C) {
      // , ; " \
      return true;
    }
    if (rune == 0x23) return true; // # starts a comment
  }
  return false;
}

/// Whether [key] must be quoted (SCON §9).
bool needsQuotesForKey(String key) {
  if (key.isEmpty) return true;
  if (key == 'null' || key == 'true' || key == 'false') return true;
  if (key.startsWith('-')) return true;
  for (final rune in key.runes) {
    if (!isKeyChar(rune)) return true;
  }
  return false;
}

String _escape(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    switch (rune) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x3B:
        out.write(r'\;');
      default:
        if (rune < 0x20) {
          out.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(rune);
        }
    }
  }
  return out.toString();
}

/// Encodes a string as a SCON scalar (quoted only when required).
String encodeString(String text) =>
    needsQuotesForValue(text) ? '"${_escape(text)}"' : text;

/// Encodes an object key (quoted only when required).
String encodeKey(String key) =>
    needsQuotesForKey(key) ? '"${_escape(key)}"' : key;

/// Encodes a scalar value (§24.2: non-finite numbers become `null`).
String encodeScalarValue(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is double) {
    if (!value.isFinite) return 'null';
    final text = value.toString();
    if (text.contains('.')) return text;
    final exponent = text.indexOf('e');
    return exponent < 0
        ? '$text.0'
        : '${text.substring(0, exponent)}.0${text.substring(exponent)}';
  }
  if (value is String) return encodeString(value);
  return encodeString(value.toString());
}
