import 'package:scon/scon.dart';
import 'package:test/test.dart';

Map<String, Object?> obj(Object? value) => value as Map<String, Object?>;
List<Object?> arr(Object? value) => value as List<Object?>;

void main() {
  group('document structure', () {
    test('decodes the nested example', () {
      const source = '''
server:
 host: localhost
 port: 8080
 tls:
  enabled: true
  cert: /etc/ssl/cert.pem
''';
      final root = obj(decodeScon(source));
      final server = obj(root['server']);
      expect(server['host'], 'localhost');
      expect(server['port'], 8080);
      expect(obj(server['tls'])['enabled'], true);
      expect(obj(server['tls'])['cert'], '/etc/ssl/cert.pem');
    });

    test('accepts the header line', () {
      expect(decodeScon('#!scon/1.0\na: 1\n'), {'a': 1});
    });

    test('rejects another version', () {
      expect(
        () => decodeScon('#!scon/2.0\na: 1\n'),
        throwsA(isA<SconUnsupportedException>()),
      );
    });

    test('keeps hashes inside quotes, strips comments outside them', () {
      const source = '''
a: "x # y" # trailing comment
b: 1
''';
      expect(decodeScon(source), {'a': 'x # y', 'b': 1});
    });

    test('decodes a document that is a single scalar', () {
      expect(decodeScon('42\n'), 42);
      expect(decodeScon('hello\n'), 'hello');
    });

    test('empty document decodes to null', () {
      expect(decodeScon(''), isNull);
      expect(decodeScon('\n\n'), isNull);
    });

    test('quoted keys and quoted values', () {
      expect(decodeScon('"a b": "c d"\n'), {'a b': 'c d'});
    });
  });

  group('values', () {
    test('numbers', () {
      final root = obj(decodeScon('a: 0\nb: -12\nc: 1.5\nd: -2.5e3\n'));
      expect(root['a'], 0);
      expect(root['b'], -12);
      expect(root['c'], 1.5);
      expect(root['d'], -2500.0);
    });

    test('leading zeros are not integers', () {
      expect(decodeScon('a: 007\n'), {'a': '007'});
      expect(decodeScon('a: 0\n'), {'a': 0});
    });

    test('reserved literals and null', () {
      expect(decodeScon('a: null\nb: true\nc: false\n'),
          {'a': null, 'b': true, 'c': false});
    });

    test('escapes decode to the escaped characters', () {
      const source = 'a: "q\\"b\\\\s\\tt\\nn\\rr\\/f\\;x"\n';
      final value = obj(decodeScon(source))['a'] as String;
      expect(value, 'q"b\\s\tt\nn\rr/f;x');
    });

    test('unicode escapes and surrogate pairs', () {
      expect(obj(decodeScon(r'a: "\u00e9"'))['a'], '\u00e9');
      expect(obj(decodeScon(r'a: "\ud83d\ude00"'))['a'], '\u{1F600}');
    });

    test('a lone low surrogate is rejected', () {
      expect(
        () => decodeScon(r'a: "\udc00"'),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('non-finite doubles are not valid input', () {
      expect(decodeScon('a: NaN\n'), {'a': 'NaN'});
      expect(decodeScon('a: Infinity\n'), {'a': 'Infinity'});
    });
  });

  group('arrays', () {
    test('expanded primitive array', () {
      const source = '''
tags:
 - web
 - api
 - 3
''';
      expect(decodeScon(source), {
        'tags': ['web', 'api', 3],
      });
    });

    test('expanded array of uniform objects', () {
      const source = '''
users:
 - id: 1
   name: Alice
 - id: 2
   name: Bob
''';
      expect(decodeScon(source), {
        'users': [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ],
      });
    });

    test('inline array with a declared count', () {
      expect(decodeScon('tags[3]: web, api, rest\n'), {
        'tags': ['web', 'api', 'rest'],
      });
      expect(decodeScon('ports[2]: 80, 443\n'), {
        'ports': [80, 443],
      });
    });

    test('inline array count mismatch is an error', () {
      expect(
        () => decodeScon('tags[3]: web, api\n'),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('empty inline array', () {
      expect(decodeScon('tags[0]:\n'), {'tags': <Object?>[]});
    });

    test('tabular array', () {
      const source = '''
users[3]{id, name, role}:
 1, Alice, admin
 2, Bob, editor
 3, Carol, viewer
''';
      expect(decodeScon(source), {
        'users': [
          {'id': 1, 'name': 'Alice', 'role': 'admin'},
          {'id': 2, 'name': 'Bob', 'role': 'editor'},
          {'id': 3, 'name': 'Carol', 'role': 'viewer'},
        ],
      });
    });

    test('tabular row count mismatch is an error', () {
      const source = '''
users[3]{id, name}:
 1, Alice
 2, Bob
''';
      expect(
        () => decodeScon(source),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('tabular field count mismatch is an error', () {
      const source = '''
users[1]{id, name}:
 1, Alice, extra
''';
      expect(
        () => decodeScon(source),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('quoted values keep commas', () {
      expect(decodeScon('tags[2]: "a, b", c\n'), {
        'tags': ['a, b', 'c'],
      });
    });
  });

  group('encoding', () {
    test('objects and nested objects', () {
      expect(
        encodeScon({
          'server': {'host': 'localhost', 'port': 8080},
          'enabled': true,
        }),
        'server:\n'
        ' host: localhost\n'
        ' port: 8080\n'
        'enabled: true\n',
      );
    });

    test('short primitive arrays become inline arrays', () {
      expect(encodeScon({'tags': ['web', 'api', 'rest']}),
          'tags[3]: web, api, rest\n');
    });

    test('uniform flat objects become a tabular array', () {
      expect(
        encodeScon({
          'users': [
            {'id': 1, 'name': 'Alice'},
            {'id': 2, 'name': 'Bob'},
          ],
        }),
        'users[2]{id, name}:\n'
        ' 1, Alice\n'
        ' 2, Bob\n',
      );
    });

    test('non-uniform objects expand', () {
      expect(
        encodeScon({
          'items': [
            {'a': 1},
            {'b': 2},
          ],
        }),
        'items:\n'
        ' - a: 1\n'
        ' - b: 2\n',
      );
    });

    test('quotes only what the format requires', () {
      expect(
        encodeScon({
          'a': 'true',
          'b': '007',
          'c': 'x,y',
          'd': 'plain',
          'e': '',
          'f': ' padded ',
        }),
        'a: "true"\n'
        'b: "007"\n'
        'c: "x,y"\n'
        'd: plain\n'
        'e: ""\n'
        'f: " padded "\n',
      );
    });

    test('header is opt-in', () {
      expect(encodeScon({'a': 1}, options: const SconEncodeOptions(includeHeader: true)),
          '#!scon/1.0\na: 1\n');
    });

    test('empty objects cannot be represented', () {
      expect(() => encodeScon({'a': <String, Object?>{}}), throwsArgumentError);
    });

    test('empty arrays are representable', () {
      expect(encodeScon({'a': <Object?>[]}), 'a[0]:\n');
      expect(decodeScon(encodeScon({'a': <Object?>[]})), {'a': <Object?>[]});
    });
  });

  group('round trip', () {
    test('a nested document survives encode and decode', () {
      final document = <String, Object?>{
        'schema': 'v1',
        'server': {
          'host': 'localhost',
          'port': 8080,
          'tls': {'enabled': true, 'cert': '/etc/ssl/cert.pem'},
        },
        'tags': ['web', 'api'],
        'rows': [
          {'id': 1, 'name': 'Alice', 'score': 1.5},
          {'id': 2, 'name': 'Bob', 'score': -2.5},
        ],
        'odd': [
          {'id': 1},
          {'id': 2, 'extra': 'x'},
        ],
        'empty': <Object?>[],
        'nul': null,
        'nested': [
          {'list': ['a', 'b']},
          {'list': <Object?>[]},
        ],
      };
      final text = encodeScon(document);
      expect(decodeScon(text), document);
    });

    test('strings that need quoting survive', () {
      final document = {
        'a': 'true',
        'b': '007',
        'c': 'x,y',
        'd': ';semi',
        'e': '#hash',
        'f': 'quote"back\\slash',
        'g': 'line\nbreak',
        'h': 'é',
      };
      expect(decodeScon(encodeScon(document)), document);
    });
  });

  group('limits and rejections', () {
    test('tabs used as indentation are rejected', () {
      expect(
        () => decodeScon('a:\n\tb: 1\n'),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('a BOM is rejected', () {
      expect(
        () => decodeScon('\uFEFFa: 1\n'),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('nesting beyond maxDepth is rejected', () {
      const source = 'a:\n b:\n  c:\n   d: 1\n';
      expect(
        () => decodeScon(source, options: const SconDecodeOptions(maxDepth: 2)),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('duplicate keys: last wins, with a warning', () {
      final warnings = <SconWarning>[];
      final value = obj(decodeScon(
        'a: 1\na: 2\n',
        options: SconDecodeOptions(onWarning: warnings.add),
      ));
      expect(value['a'], 2);
      expect(warnings.single.kind, SconWarningKind.duplicateKey);
    });

    test('duplicate keys are an error in strict mode', () {
      expect(
        () => decodeScon('a: 1\na: 2\n',
            options: const SconDecodeOptions(strict: true)),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('imports are unsupported', () {
      expect(
        () => decodeScon('@use shared.sltt\na: 1\n'),
        throwsA(isA<SconUnsupportedException>()),
      );
    });

    test('schema blocks and references are unsupported', () {
      expect(
        () => decodeScon('s:UserBase:\n id: 0\n'),
        throwsA(isA<SconUnsupportedException>()),
      );
      expect(
        () => decodeScon('user: @s:UserBase\n'),
        throwsA(isA<SconUnsupportedException>()),
      );
    });

    test('directives are ignored with a warning', () {
      final warnings = <SconWarning>[];
      final value = obj(decodeScon(
        '@@strict\na: 1\n',
        options: SconDecodeOptions(onWarning: warnings.add),
      ));
      expect(value['a'], 1);
      expect(warnings.single.kind, SconWarningKind.unknownDirective);
    });

    test('a value must be separated from the colon by a space', () {
      expect(
        () => decodeScon('a:1\n'),
        throwsA(isA<SconFormatException>()),
      );
    });
  });

  group('minified representation', () {
    const standard = '''
server:
 host: localhost
 port: 8080
 tls:
  enabled: true
  cert: /etc/ssl/cert.pem
database:
 host: db.local
''';

    test('minifies the example from the specification', () {
      expect(
        minifyScon(standard),
        'server:host: localhost;port: 8080;tls:enabled: true;'
        'cert: /etc/ssl/cert.pem;;;database:host: db.local',
      );
    });

    test('expand restores the same data', () {
      final expanded = expandScon(minifyScon(standard));
      expect(decodeScon(expanded), decodeScon(standard));
    });

    test('decodeMinified and encodeMinified are symmetric', () {
      final document = {
        'list': [1, 2, 3],
        'items': [
          {'a': 1},
          {'b': 2},
        ],
      };
      final minified = encodeMinified(document);
      expect(decodeMinified(minified), document);
      expect(minified, minifyScon(encodeScon(document)));
    });

    test('semicolons inside quoted values survive', () {
      final document = {'a': 'x;y', 'b': 'p;;q'};
      expect(decodeMinified(encodeMinified(document)), document);
    });

    test('a leading dedent is an error', () {
      expect(
        () => expandScon(';a: 1'),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('a dedent above the root is an error', () {
      expect(
        () => expandScon('a: 1;;'),
        throwsA(isA<SconFormatException>()),
      );
    });

    test('an open block with nothing after it is an error', () {
      expect(
        () => expandScon('a:'),
        throwsA(isA<SconFormatException>()),
      );
    });
    test('canonical output sorts keys and is stable', () {
      final first = encodeScon(
        {'b': 2, 'a': 1, 'nested': {'z': 1, 'y': 2}},
        options: const SconEncodeOptions(canonical: true),
      );
      final second = encodeScon(
        {'nested': {'y': 2, 'z': 1}, 'a': 1, 'b': 2},
        options: const SconEncodeOptions(canonical: true),
      );
      expect(first, second);
      expect(first.indexOf('a:'), lessThan(first.indexOf('b:')));
      expect(first.indexOf('y:'), lessThan(first.indexOf('z:')));
    });

    test('canonical tabular headers sort their fields', () {
      final text = encodeScon({
        'rows': [
          {'b': 1, 'a': 2},
          {'a': 3, 'b': 4},
        ],
      }, options: const SconEncodeOptions(canonical: true));
      expect(text, 'rows[2]{a, b}:\n 2, 1\n 3, 4\n');
    });

    test('empty arrays survive the minified form', () {
      final document = {
        'a': <Object?>[],
        'b': 1,
      };
      final minified = minifyScon(encodeScon(document));
      expect(minified, contains('a[0]:'));
      expect(decodeMinified(minified), document);
    });
  });
}
