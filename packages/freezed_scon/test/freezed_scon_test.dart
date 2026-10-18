import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:freezed_scon/freezed_scon.dart';
import 'package:freezed_scon/builder.dart';
import 'package:test/test.dart';

class _User {
  const _User(this.name);

  factory _User.fromJson(Map<String, Object?> json) =>
      _User(json['name']! as String);

  final String name;

  Map<String, Object?> toJson() => {'name': name};
}

const _freezedLikeModel = '''
import 'package:freezed_scon/freezed_scon.dart';

part 'models.scon.dart';

@SconFreezed()
class Person {
  const Person._({required this.name});

  factory Person.fromJson(Map<String, dynamic> json) =>
      Person._(name: json['name'] as String);

  final String name;

  Map<String, dynamic> toJson() => <String, dynamic>{'name': name};
}
''';

Future<String> _generate(String source) async {
  final result = await testBuilder(
    freezedSconBuilder(BuilderOptions({})),
    {
      'freezed_scon|lib/models.dart': source,
      // build_test only resolves the assets it is given, so the annotation
      // library and the scon helpers it re-exports are supplied in memory.
      'freezed_scon|lib/src/annotation.dart': '''
class SconFreezed {
  const SconFreezed();
}
''',
      'freezed_scon|lib/freezed_scon.dart': '''
export 'src/annotation.dart';

String encodeFreezed<T>(T value, Map<String, Object?> Function(T) toJson) =>
    '';

T decodeFreezed<T>(String source, T Function(Map<String, Object?>) fromJson) =>
    throw UnimplementedError();
''',
    },
    rootPackage: 'freezed_scon',
    flattenOutput: true,
  );
  return result.readerWriter.readAsString(
    AssetId('freezed_scon', 'lib/models.scon.dart'),
  );
}

void main() {
  test('generates a part-file bridge that delegates to toJson/fromJson',
      () async {
    final generated = await _generate(_freezedLikeModel);
    expect(generated, contains("part of 'models.dart';"));
    expect(generated, contains('extension PersonScon on Person {'));
    expect(generated, contains('String toScon()'));
    expect(generated, contains('Person personFromScon(String source)'));
    expect(generated, contains('Person.fromJson(json)'));
  });

  test('rejects a class without toJson/fromJson', () async {
    await expectLater(
      _generate('''
import 'package:freezed_scon/freezed_scon.dart';

part 'models.scon.dart';

@SconFreezed()
class Plain {
  const Plain();
}
'''),
      throwsA(anything),
    );
  });

  test('helpers round trip a model through its JSON mapping', () {
    const user = _User('Alice');
    final text = encodeFreezed(user, (value) => value.toJson());
    expect(text, 'name: Alice\n');
    final back = decodeFreezed(text, (json) => _User.fromJson(json));
    expect(back.name, 'Alice');
  });

  test('helpers reject a non-object document', () {
    expect(
      () => decodeFreezed('42\n', (json) => _User(json['name']! as String)),
      throwsA(isA<FormatException>()),
    );
  });
}
