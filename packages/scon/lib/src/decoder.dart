import 'exception.dart';
import 'options.dart';
import 'text.dart';

/// Decodes a SCON 1.0 document into plain Dart values.
///
/// Objects become insertion-ordered `Map<String, Object?>`, arrays become
/// `List<Object?>`, numbers become `int`/`double`, and `null`/`true`/`false`
/// become the matching Dart values.
Object? decodeScon(
  String source, {
  SconDecodeOptions options = const SconDecodeOptions(),
}) =>
    _Decoder(source, options).decode();

class _Line {
  _Line(this.indent, this.text, this.number);

  final int indent;
  final String text;
  final int number;
}

enum _KeyKind { value, inlineArray, tabular }

class _KeyLine {
  _KeyLine({
    required this.key,
    required this.kind,
    required this.rest,
    this.count,
    this.fields,
  });

  final String key;
  final _KeyKind kind;
  final String rest;
  final int? count;
  final List<String>? fields;
}

class _Decoder {
  _Decoder(this.source, this.options);

  final String source;
  final SconDecodeOptions options;
  final List<_Line> _lines = [];
  int _index = 0;
  int _depth = 0;
  bool _headerSeen = false;

  Never _fail(String message, int line) =>
      throw SconFormatException(message, line, 1);

  Never _unsupported(String message, int line) =>
      throw SconUnsupportedException(message, line: line);

  void _warn(SconWarningKind kind, String message, int line) {
    options.onWarning?.call(SconWarning(kind, message, line));
  }

  Object? decode() {
    if (source.startsWith('\uFEFF')) {
      _fail('a UTF-8 BOM is not allowed', 1);
    }
    if (source.length > options.maxDocumentSize) {
      _fail('document exceeds ${options.maxDocumentSize} characters', 1);
    }
    _tokenize();
    if (_lines.isEmpty) return null;
    if (_lines.first.indent != 0) {
      _fail('the document must start at depth 0', _lines.first.number);
    }
    final value = _parseValue(0);
    if (_index < _lines.length) {
      _fail('unexpected content after the document value',
          _lines[_index].number);
    }
    return value;
  }

  void _tokenize() {
    final raw = source.split('\n');
    for (var number = 1; number <= raw.length; number++) {
      var line = raw[number - 1];
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      var indent = 0;
      while (indent < line.length && line.codeUnitAt(indent) == 0x20) {
        indent++;
      }
      if (indent < line.length && line.codeUnitAt(indent) == 0x09) {
        _fail('tabs are not allowed for indentation', number);
      }
      var body = line.substring(indent);
      if (body.isEmpty) continue;
      if (!_headerSeen && body.startsWith('#!scon/')) {
        final version = body.substring(7).trim();
        if (version != '1.0') {
          _unsupported('unsupported SCON version "$version"', number);
        }
        _headerSeen = true;
        continue;
      }
      body = _stripComment(body).trimRight();
      if (body.isEmpty) continue;
      if (body.startsWith('@@')) {
        _warn(SconWarningKind.unknownDirective, 'directive ignored: $body',
            number);
        continue;
      }
      if (body == '@use' || body.startsWith('@use ')) {
        _unsupported('imports (@use) require SCON Level 3', number);
      }
      if (body.startsWith('s:') || body.startsWith('r:') ||
          body.startsWith('sec:')) {
        _unsupported('schema blocks require SCON Level 3', number);
      }
      _lines.add(_Line(indent, body, number));
    }
  }

  String _stripComment(String body) {
    var inQuotes = false;
    var escaped = false;
    for (var i = 0; i < body.length; i++) {
      final code = body.codeUnitAt(i);
      if (inQuotes) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5C) {
          escaped = true;
        } else if (code == 0x22) {
          inQuotes = false;
        }
        continue;
      }
      if (code == 0x22) {
        inQuotes = true;
      } else if (code == 0x23) {
        return body.substring(0, i);
      }
    }
    return body;
  }

  Object? _parseValue(int indent) {
    if (_depth >= options.maxDepth) {
      _fail('nesting exceeds ${options.maxDepth} levels', _lines[_index].number);
    }
    _depth++;
    try {
      final line = _lines[_index];
      if (line.text == '-' || line.text.startsWith('- ')) {
        return _parseList(indent);
      }
      if (_tryKeyLine(line.text, line.number) != null) {
        return _parseObject(indent);
      }
      _index++;
      return _parseInlineValue(line.text, line.number);
    } finally {
      _depth--;
    }
  }

  Map<String, Object?> _parseObject(int indent) {
    final map = <String, Object?>{};
    while (_index < _lines.length) {
      final line = _lines[_index];
      if (line.indent < indent) break;
      if (line.indent > indent) {
        _fail('unexpected indentation', line.number);
      }
      if (line.text == '-' || line.text.startsWith('- ')) break;
      final keyLine = _tryKeyLine(line.text, line.number);
      if (keyLine == null) _fail('expected "key: value"', line.number);
      _index++;
      if (map.containsKey(keyLine.key)) {
        if (options.strict) _fail('duplicate key "${keyLine.key}"', line.number);
        _warn(SconWarningKind.duplicateKey,
            'duplicate key "${keyLine.key}"; the last value wins', line.number);
      }
      map[keyLine.key] = _readKeyValue(keyLine, line, indent);
    }
    return map;
  }

  Object? _readKeyValue(_KeyLine keyLine, _Line line, int indent) {
    switch (keyLine.kind) {
      case _KeyKind.tabular:
        final rows = <Map<String, Object?>>[];
        int? rowIndent;
        while (_index < _lines.length) {
          final row = _lines[_index];
          if (row.indent <= indent) break;
          rowIndent ??= row.indent;
          if (row.indent != rowIndent) break;
          rows.add(_parseTabularRow(row, keyLine.fields!, line.number));
          _index++;
        }
        if (rows.length != keyLine.count) {
          _fail(
            'tabular array declares ${keyLine.count} rows but ${rows.length} were found',
            line.number,
          );
        }
        return rows;
      case _KeyKind.inlineArray:
        if (keyLine.count == 0 && keyLine.rest.isEmpty) return <Object?>[];
        final parts = _splitValues(keyLine.rest, line.number);
        if (parts.length != keyLine.count) {
          _fail(
            'inline array declares ${keyLine.count} items but ${parts.length} were found',
            line.number,
          );
        }
        return [for (final part in parts) _parseInlineValue(part, line.number)];
      case _KeyKind.value:
        if (keyLine.rest.isNotEmpty) {
          return _parseInlineValue(keyLine.rest, line.number);
        }
        if (_index < _lines.length && _lines[_index].indent > indent) {
          return _parseValue(_lines[_index].indent);
        }
        return null;
    }
  }

  Map<String, Object?> _parseTabularRow(
    _Line row,
    List<String> fields,
    int headerLine,
  ) {
    final values = _splitValues(row.text, row.number);
    if (values.length != fields.length) {
      _fail(
        'row has ${values.length} values but the header declares ${fields.length} fields',
        row.number,
      );
    }
    return {
      for (var i = 0; i < fields.length; i++)
        fields[i]: _parseInlineValue(values[i], row.number),
    };
  }

  List<Object?> _parseList(int indent) {
    final list = <Object?>[];
    while (_index < _lines.length) {
      final line = _lines[_index];
      if (line.indent < indent) break;
      if (line.indent > indent) {
        _fail('unexpected indentation', line.number);
      }
      if (line.text != '-' && !line.text.startsWith('- ')) break;
      final rest = line.text == '-' ? '' : line.text.substring(2);
      if (rest.isEmpty) {
        _index++;
        if (_index < _lines.length && _lines[_index].indent > indent) {
          list.add(_parseValue(_lines[_index].indent));
        } else {
          list.add(null);
        }
        continue;
      }
      if (_tryKeyLine(rest, line.number) != null) {
        final nextIndent =
            _index + 1 < _lines.length ? _lines[_index + 1].indent : indent;
        final childIndent = nextIndent > indent ? nextIndent : indent + 1;
        _lines[_index] = _Line(childIndent, rest, line.number);
        list.add(_parseObject(childIndent));
        continue;
      }
      list.add(_parseInlineValue(rest, line.number));
      _index++;
    }
    return list;
  }

  _KeyLine? _tryKeyLine(String text, int line) {
    var i = 0;
    String key;
    if (text.isNotEmpty && text.codeUnitAt(0) == 0x22) {
      final quoted = parseQuoted(text, 0, line);
      key = quoted.value;
      i = quoted.end;
    } else {
      while (i < text.length && isKeyChar(text.codeUnitAt(i))) {
        i++;
      }
      if (i == 0) return null;
      key = text.substring(0, i);
    }
    if (i < text.length && text.codeUnitAt(i) == 0x21) {
      _unsupported('mandatory fields (!) belong to schema blocks (Level 3)',
          line);
    }
    int? count;
    List<String>? fields;
    var kind = _KeyKind.value;
    if (i < text.length && text.codeUnitAt(i) == 0x5B) {
      final close = text.indexOf(']', i);
      if (close < 0) _fail('unterminated "[count]"', line);
      final digits = text.substring(i + 1, close).trim();
      final parsed = int.tryParse(digits);
      if (parsed == null || parsed < 0) {
        _fail('invalid array count "$digits"', line);
      }
      count = parsed;
      i = close + 1;
      kind = _KeyKind.inlineArray;
      if (i < text.length && text.codeUnitAt(i) == 0x7B) {
        final closeBrace = text.indexOf('}', i);
        if (closeBrace < 0) _fail('unterminated "{fields}"', line);
        fields = _splitFields(text.substring(i + 1, closeBrace), line);
        if (fields.isEmpty) _fail('a tabular header needs at least one field', line);
        i = closeBrace + 1;
        kind = _KeyKind.tabular;
      }
    }
    if (i >= text.length || text.codeUnitAt(i) != 0x3A) return null;
    i++;
    if (kind == _KeyKind.value &&
        i < text.length &&
        text.codeUnitAt(i) != 0x20) {
      _fail('a value must be separated from ":" by one space', line);
    }
    final rest = i < text.length ? text.substring(i).trim() : '';
    if (kind == _KeyKind.tabular && rest.isNotEmpty) {
      _fail('a tabular header takes no inline value', line);
    }
    return _KeyLine(
      key: key,
      kind: kind,
      rest: rest,
      count: count,
      fields: fields,
    );
  }

  List<String> _splitFields(String text, int line) {
    final parts = _splitOn(text, 0x2C, line);
    final fields = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) _fail('empty field name in the tabular header', line);
      if (trimmed.codeUnitAt(0) == 0x22) {
        final quoted = parseQuoted(trimmed, 0, line);
        fields.add(quoted.value);
      } else {
        fields.add(trimmed);
      }
    }
    return fields;
  }

  List<String> _splitValues(String text, int line) {
    if (text.isEmpty) return const [''];
    if (text.codeUnitAt(0) == 0x22) {
      final quoted = parseQuoted(text, 0, line);
      if (text.substring(quoted.end).trim().isEmpty) return [text];
    }
    final hasComma = _containsOutsideQuotes(text, 0x2C);
    if (hasComma) return _splitOn(text, 0x2C, line);
    if (_containsOutsideQuotes(text, 0x7C)) return _splitOn(text, 0x7C, line);
    if (_containsOutsideQuotes(text, 0x09)) return _splitOn(text, 0x09, line);
    return [text];
  }

  bool _containsOutsideQuotes(String text, int separator) {
    var inQuotes = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (inQuotes) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5C) {
          escaped = true;
        } else if (code == 0x22) {
          inQuotes = false;
        }
        continue;
      }
      if (code == 0x22) {
        inQuotes = true;
      } else if (code == separator) {
        return true;
      }
    }
    return false;
  }

  List<String> _splitOn(String text, int separator, int line) {
    final parts = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (inQuotes) {
        current.writeCharCode(code);
        if (escaped) {
          escaped = false;
        } else if (code == 0x5C) {
          escaped = true;
        } else if (code == 0x22) {
          inQuotes = false;
        }
        continue;
      }
      if (code == 0x22) {
        inQuotes = true;
        current.writeCharCode(code);
      } else if (code == separator) {
        parts.add(current.toString());
        current.clear();
      } else {
        current.writeCharCode(code);
      }
    }
    parts.add(current.toString());
    return parts;
  }

  Object? _parseInlineValue(String text, int line) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('@s:')) {
      _unsupported('schema references (@s:) require SCON Level 3', line);
    }
    if (trimmed.codeUnitAt(0) == 0x22) {
      final quoted = parseQuoted(trimmed, 0, line);
      if (trimmed.substring(quoted.end).trim().isNotEmpty) {
        _fail('unexpected characters after a quoted string', line);
      }
      return quoted.value;
    }
    if (trimmed == 'null') return null;
    if (trimmed == 'true') return true;
    if (trimmed == 'false') return false;
    final integer = RegExp(r'^-?(0|[1-9][0-9]*)$');
    if (integer.hasMatch(trimmed)) return int.parse(trimmed);
    final float = RegExp(r'^-?(0|[1-9][0-9]*)\.[0-9]+([eE][+-]?[0-9]+)?$');
    if (float.hasMatch(trimmed)) {
      final value = double.parse(trimmed);
      if (!value.isFinite) _fail('non-finite numbers are not valid', line);
      return value;
    }
    return trimmed;
  }
}
