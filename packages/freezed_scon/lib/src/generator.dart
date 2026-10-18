import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:freezed_scon/src/annotation.dart' show SconFreezed;
import 'package:source_gen/source_gen.dart';

/// Generates, inside the model's own library (a part file), the SCON bridge for
/// `@SconFreezed()` classes. It delegates to the `toJson`/`fromJson` members
/// that freezed + json_serializable generate, so the JSON mapping stays the
/// single source of truth.
class FreezedSconGenerator extends GeneratorForAnnotation<SconFreezed> {
  @override
  FutureOr<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@SconFreezed can only be applied to classes.',
        element: element,
      );
    }
    final className = element.name;
    if (className == null || className.isEmpty) {
      throw InvalidGenerationSourceError(
        '@SconFreezed must be applied to a named class.',
        element: element,
      );
    }
    final hasFromJson = element.constructors
        .any((constructor) => constructor.name == 'fromJson');
    final hasToJson = element.methods
        .any((method) => method.name == 'toJson' && !method.isStatic);
    if (!hasFromJson || !hasToJson) {
      throw InvalidGenerationSourceError(
        '$className must expose fromJson and toJson; enable '
        'json_serializable on the freezed class (fromJson: true).',
        element: element,
      );
    }
    final lower = className[0].toLowerCase() + className.substring(1);
    return '''
extension ${className}Scon on $className {
  /// Encodes this value as SCON text (through its JSON mapping).
  String toScon() => encodeFreezed(this, (value) => value.toJson());
}

/// Decodes SCON text into $className (through its JSON mapping).
$className ${lower}FromScon(String source) =>
    decodeFreezed(source, (json) => $className.fromJson(json));
''';
  }
}
