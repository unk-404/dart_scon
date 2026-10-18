import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:scon/scon.dart' show SconField, SconModel;
import 'package:source_gen/source_gen.dart';

/// Generates `toScon()` and `<name>FromScon(Object?)` for `@SconModel` classes.
///
/// Supported field types: `String`, `int`, `double`, `num`, `bool`,
/// `DateTime`, enums, `Object?`/`dynamic`, `List<T>` of those, and other
/// `@SconModel` classes declared in the same library.
class SconGenerator extends GeneratorForAnnotation<SconModel> {
  static const _fieldChecker =
      TypeChecker.typeNamed(SconField, inPackage: 'scon');
  static const _modelChecker =
      TypeChecker.typeNamed(SconModel, inPackage: 'scon');

  @override
  FutureOr<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@SconModel can only be applied to classes.',
        element: element,
      );
    }
    final className = element.name;
    if (className == null || className.isEmpty) {
      throw InvalidGenerationSourceError(
        '@SconModel must be applied to a named class.',
        element: element,
      );
    }
    final library = element.library;
    final fields = <_FieldInfo>[];
    for (final field in element.fields) {
      if (field.isStatic || field.isPrivate) continue;
      final name = field.name;
      if (name == null) continue;
      final annotationObject = _fieldChecker.firstAnnotationOf(field);
      final key = annotationObject?.getField('name')?.toStringValue() ?? name;
      fields.add(_FieldInfo.from(name: name, key: key, field: field, library: library));
    }
    if (fields.isEmpty) {
      throw InvalidGenerationSourceError(
        '@SconModel class $className has no instance fields to encode.',
        element: element,
      );
    }
    final sourceUri = library.firstFragment.source.uri;
    final sourceName = sourceUri.pathSegments.last;

    final out = StringBuffer()
      ..writeln('// ignore_for_file: type=lint, unused_element, unnecessary_cast')
      ..writeln("import '$sourceName';")
      ..writeln();

    out
      ..writeln('extension ${className}SconCodec on $className {')
      ..writeln('  Map<String, Object?> toScon() => <String, Object?>{');
    for (final field in fields) {
      final value = _encodeExpression('${field.name}', field.codec);
      out.writeln("        '${_escapeKey(field.key)}': $value,");
    }
    out
      ..writeln('      };')
      ..writeln('}')
      ..writeln();

    final functionName = '${_lowerFirst(className)}FromScon';
    out
      ..writeln('$className $functionName(Object? value) {')
      ..writeln('  if (value is! Map) {')
      ..writeln(
          "    throw FormatException('Expected an object for $className, got \${value.runtimeType}');")
      ..writeln('  }');
    final required = [
      for (final field in fields)
        if (!field.codec.nullable) field,
    ];
    if (required.isNotEmpty) {
      out
        ..writeln("  const required = <String>[")
        ..writeln(required.map((f) => "    '${_escapeKey(f.key)}',").join('\n'))
        ..writeln('  ];')
        ..writeln('  for (final key in required) {')
        ..writeln('    if (!value.containsKey(key)) {')
        ..writeln(
            "      throw FormatException('Missing \"\$key\" for $className');")
        ..writeln('    }')
        ..writeln('  }');
    }
    out.writeln('  return $className(');
    for (final field in fields) {
      final raw = "value['${_escapeKey(field.key)}']";
      final expression = _decodeExpression(raw, field.codec);
      out.writeln('    ${field.name}: $expression,');
    }
    out
      ..writeln('  );')
      ..writeln('}')
      ..writeln();

    return out.toString();
  }

  String _decodeExpression(String raw, _Codec codec) {
    final inner = switch (codec.kind) {
      _Kind.string => '$raw as String',
      _Kind.integer => '$raw as int',
      _Kind.floating => '($raw as num).toDouble()',
      _Kind.number => '$raw as num',
      _Kind.boolean => '$raw as bool',
      _Kind.dateTime => 'DateTime.parse($raw as String)',
      _Kind.enumType => '${codec.enumName}.values.byName($raw as String)',
      _Kind.model => '${_lowerFirst(codec.modelName!) }FromScon($raw)',
      _Kind.list =>
        '[for (final item in ($raw as List)) ${_decodeExpression('item', codec.element!)}]',
      _Kind.dynamic => raw,
    };
    return codec.nullable ? '$raw == null ? null : $inner' : inner;
  }

  String _encodeExpression(String value, _Codec codec) {
    final inner = switch (codec.kind) {
      _Kind.string || _Kind.integer || _Kind.floating || _Kind.number ||
      _Kind.boolean ||
      _Kind.dynamic =>
        value,
      _Kind.dateTime => '$value.toIso8601String()',
      _Kind.enumType => '$value.name',
      _Kind.model => '$value.toScon()',
      _Kind.list =>
        '[for (final item in $value) ${_encodeExpression('item', codec.element!)}]',
    };
    return codec.nullable ? '$value == null ? null : $inner' : inner;
  }

  static String _escapeKey(String key) =>
      key.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  static String _lowerFirst(String name) =>
      name.isEmpty ? name : name[0].toLowerCase() + name.substring(1);
}

enum _Kind {
  string,
  integer,
  floating,
  number,
  boolean,
  dateTime,
  enumType,
  list,
  model,
  dynamic,
}

class _Codec {
  const _Codec(this.kind, {this.nullable = false, this.enumName, this.modelName, this.element});

  final _Kind kind;
  final bool nullable;
  final String? enumName;
  final String? modelName;
  final _Codec? element;

  _Codec asNullable() => _Codec(kind,
      nullable: true,
      enumName: enumName,
      modelName: modelName,
      element: element);
}

class _FieldInfo {
  _FieldInfo(this.name, this.key, this.codec);

  final String name;
  final String key;
  final _Codec codec;

  factory _FieldInfo.from({
    required String name,
    required String key,
    required FieldElement field,
    LibraryElement? library,
  }) =>
      _FieldInfo(name, key, _codecFor(field.type, library));

  static _Codec _codecFor(DartType type, LibraryElement? library) {
    final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
    _Codec codec;
    if (type.isDartCoreString) {
      codec = const _Codec(_Kind.string);
    } else if (type.isDartCoreInt) {
      codec = const _Codec(_Kind.integer);
    } else if (type.isDartCoreDouble) {
      codec = const _Codec(_Kind.floating);
    } else if (type.isDartCoreNum) {
      codec = const _Codec(_Kind.number);
    } else if (type.isDartCoreBool) {
      codec = const _Codec(_Kind.boolean);
    } else if (type is DynamicType ||
        type.isDartCoreObject ||
        type.isDartCoreNull) {
      codec = const _Codec(_Kind.dynamic);
    } else if (_isDateTime(type)) {
      codec = const _Codec(_Kind.dateTime);
    } else if (type.isDartCoreList) {
      final arguments = type is InterfaceType ? type.typeArguments : const <DartType>[];
      final argument = arguments.isEmpty ? null : arguments.first;
      if (argument == null) {
        throw InvalidGenerationSourceError(
            'A List field must declare its element type.');
      }
      codec = _Codec(_Kind.list, element: _codecFor(argument, library));
    } else if (type.element is EnumElement) {
      codec = _Codec(_Kind.enumType, enumName: (type.element as EnumElement).name);
    } else if (type.element is ClassElement &&
        _SconGeneratorAccess.hasModelAnnotation(type.element as ClassElement)) {
      final classElement = type.element as ClassElement;
      if (library != null && classElement.library != library) {
        throw InvalidGenerationSourceError(
          'Only @SconModel classes declared in the same library are supported '
          '(${classElement.name} lives in another file).',
          element: classElement,
        );
      }
      codec = _Codec(_Kind.model, modelName: classElement.name);
    } else {
      throw InvalidGenerationSourceError(
        'Unsupported field type "${type.getDisplayString()}": use a core type, '
        'DateTime, an enum, a List of those, or a @SconModel class from the '
        'same file.',
        element: library?.firstFragment.element,
      );
    }
    return nullable ? codec.asNullable() : codec;
  }

  static bool _isDateTime(DartType type) =>
      type.element is ClassElement &&
      (type.element as ClassElement).name == 'DateTime' &&
      ((type.element!.library?.isDartCore ?? false));
}

/// Keeps the annotation lookup in one place for the field-type check.
class _SconGeneratorAccess {
  static bool hasModelAnnotation(ClassElement element) =>
      SconGenerator._modelChecker.hasAnnotationOfExact(element);
}
