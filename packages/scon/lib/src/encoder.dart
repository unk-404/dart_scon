import 'options.dart';
import 'text.dart';

/// Encodes plain Dart values as a SCON 1.0 document (standard form).
///
/// `Map<String, Object?>` becomes an object, `List<Object?>` an array,
/// `int`/`double` a number, `String` a string, and `null`/`bool` the matching
/// literal. Maps must have string keys; an empty map cannot be represented by
/// the format and is rejected.
String encodeScon(
  Object? value, {
  SconEncodeOptions options = const SconEncodeOptions(),
}) {
  final encoder = _Encoder(options);
  if (options.includeHeader) encoder.out.writeln('#!scon/1.0');
  encoder.writeRoot(value);
  return encoder.out.toString();
}

class _Encoder {
  _Encoder(this.options);

  final SconEncodeOptions options;
  final StringBuffer out = StringBuffer();

  String _pad(int depth) => options.indent * depth;

  void writeRoot(Object? value) {
    if (value is Map) {
      _writeObject(value, 0);
    } else if (value is List) {
      _writeListItems(value, 0);
    } else {
      out.writeln(encodeScalarValue(value));
    }
  }

  Iterable<MapEntry<dynamic, dynamic>> _entries(Map<dynamic, dynamic> map) {
    final entries = map.entries.toList();
    if (options.canonical) {
      entries.sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    }
    return entries;
  }

  void _writeObject(Map<dynamic, dynamic> map, int depth) {
    if (map.isEmpty) {
      throw ArgumentError(
        'SCON cannot represent an empty object: it has no marker distinct '
        'from a null value',
      );
    }
    for (final entry in _entries(map)) {
      _writeEntry(_pad(depth), entry.key, entry.value, depth);
    }
  }

  void _writeEntry(String pad, Object? rawKey, Object? value, int depth) {
    final key = _key(rawKey);
    if (value is Map) {
      out.writeln('$pad$key:');
      _writeObject(value, depth + 1);
    } else if (value is List) {
      _writeArrayForKey(pad, key, value, depth);
    } else {
      out.writeln('$pad$key: ${encodeScalarValue(value)}');
    }
  }

  void _writeArrayForKey(String pad, String key, List<dynamic> list, int depth) {
    if (list.isEmpty) {
      out.writeln('$pad$key[0]:');
      return;
    }
    if (options.tabular && _isTabular(list)) {
      final fields = list.first as Map;
      final names = [for (final entry in _entries(fields)) _key(entry.key)];
      out.writeln('$pad$key[${list.length}]{${names.join(', ')}}:');
      final rowPad = _pad(depth + 1);
      for (final row in list) {
        final map = row as Map;
        final values = [
          for (final entry in _entries(fields))
            encodeScalarValue(map[entry.key]),
        ];
        out.writeln('$rowPad${values.join(', ')}');
      }
      return;
    }
    if (_isInline(list)) {
      final values = [for (final item in list) encodeScalarValue(item)];
      out.writeln('$pad$key[${list.length}]: ${values.join(', ')}');
      return;
    }
    out.writeln('$pad$key:');
    _writeListItems(list, depth + 1);
  }

  void _writeListItems(List<dynamic> list, int depth) {
    final pad = _pad(depth);
    for (final item in list) {
      if (item is Map) {
        if (item.isEmpty) {
          throw ArgumentError(
            'SCON cannot represent an empty object inside an array',
          );
        }
        var first = true;
        for (final entry in _entries(item)) {
          final prefix = first ? '$pad- ' : _pad(depth + 1);
          first = false;
          _writeEntry(prefix, entry.key, entry.value, depth + 1);
        }
      } else if (item is List) {
        out.writeln('$pad-');
        _writeListItems(item, depth + 1);
      } else {
        out.writeln('$pad- ${encodeScalarValue(item)}');
      }
    }
  }

  bool _isTabular(List<dynamic> list) {
    if (list.length < 2) return false;
    if (list.any((item) => item is! Map)) return false;
    final first = list.first as Map;
    if (first.isEmpty) return false;
    for (final item in list) {
      final map = item as Map;
      if (map.length != first.length) return false;
      for (final name in first.keys) {
        if (!map.containsKey(name)) return false;
      }
      for (final value in map.values) {
        if (value is Map || value is List) return false;
      }
    }
    return true;
  }

  bool _isInline(List<dynamic> list) {
    if (list.length > options.inlineArrayLimit) return false;
    return list.every((item) => item is! Map && item is! List);
  }

  String _key(Object? key) {
    if (key is! String) {
      throw ArgumentError.value(key, 'key', 'SCON object keys must be strings');
    }
    return encodeKey(key);
  }
}
