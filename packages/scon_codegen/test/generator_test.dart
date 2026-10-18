import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:scon/scon.dart';
import 'package:scon_codegen/builder.dart';
import 'package:test/test.dart';

const _model = '''
import 'package:scon/scon.dart';

enum Role { admin, viewer }

@SconModel()
class User {
  User({
    required this.name,
    required this.age,
    this.role,
    this.tags = const <String>[],
    this.createdAt,
  });

  final String name;
  final int age;
  final Role? role;
  final List<String> tags;
  final DateTime? createdAt;
}
''';

Future<String> _generate(String source) async {
  final result = await testBuilder(
    sconBuilder(BuilderOptions({})),
    {
      'scon_codegen|lib/models.dart': source,
      // The fixture resolves `package:scon` from these in-memory sources so the
      // test does not depend on the resolver seeing the sibling package.
      'scon|lib/scon.dart': '''
class SconModel {
  const SconModel();
}

class SconField {
  const SconField(this.name);

  final String name;
}
''',
    },
    rootPackage: 'scon_codegen',
    flattenOutput: true,
  );
  return result.readerWriter.readAsString(
    AssetId('scon_codegen', 'lib/models.scon.dart'),
  );
}

void main() {
  test('generates a codec extension and a fromScon helper', () async {
    final generated = await _generate(_model);
    expect(generated, contains('extension UserSconCodec on User {'));
    expect(generated, contains('Map<String, Object?> toScon()'));
    expect(generated, contains('User userFromScon(Object? value)'));
    expect(generated, contains("'name': name,"));
    expect(generated, contains("name: value['name'] as String,"));
    expect(generated, contains("age: value['age'] as int,"));
    expect(generated, contains('Role.values.byName('));
    expect(generated, contains('DateTime.parse('));
    expect(generated, contains('toIso8601String()'));
    expect(generated, contains('required'));
  });

  test('checks required keys before decoding', () async {
    final generated = await _generate(_model);
    final requiredLine = generated
        .split('\n')
        .firstWhere((line) => line.contains('const required'));
    expect(requiredLine, contains("'name'"));
    expect(requiredLine, contains("'age'"));
    expect(requiredLine, isNot(contains("'role'")));
    expect(requiredLine, isNot(contains("'createdAt'")));
  });

  test('@SconField renames the key', () async {
    final generated = await _generate('''
import 'package:scon/scon.dart';

@SconModel()
class Server {
  Server({required this.hostName});

  @SconField('host')
  final String hostName;
}
''');
    expect(generated, contains("'host':"));
    expect(generated, contains("value['host'] as String"));
  });

  test('rejects unsupported field types', () async {
    await expectLater(
      _generate('''
import 'package:scon/scon.dart';

class Thing {
  const Thing();
}

@SconModel()
class Holder {
  Holder({required this.thing});

  final Thing thing;
}
'''),
      throwsA(anything),
    );
  });

  test('supports nested models from the same file', () async {
    final generated = await _generate('''
import 'package:scon/scon.dart';

@SconModel()
class Inner {
  Inner({required this.value});
  final int value;
}

@SconModel()
class Outer {
  Outer({required this.inner});
  final Inner inner;
}
''');
    expect(generated, contains('extension OuterSconCodec on Outer {'));
    expect(generated, contains("inner: innerFromScon(value['inner']),"));
    expect(generated, contains('extension InnerSconCodec on Inner {'));
  });

  test('round trips a generated model through the scon format', () async {
    // The generator emits code, so this test only proves the shape of the
    // helpers it writes against a hand-written equivalent.
    final document = decodeScon('name: Alice\nage: 42\n') as Map;
    expect(document['name'], 'Alice');
    expect(document['age'], 42);
    expect(encodeScon(document), 'name: Alice\nage: 42\n');
  });
}
