# scon_codegen

A `build_runner` generator for [scon](../) that writes typed SCON encode/decode
code. It depends on `build` + `source_gen` and **not** on freezed.

```yaml
# pubspec.yaml of the consuming package
dev_dependencies:
  build_runner: ^2.16.2
  scon_codegen: ^0.1.0
dependencies:
  scon: ^0.1.0
```

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated files are written next to their sources as `<file>.scon.dart`
(`build_to: source`), so they can be committed; the builder never modifies the
source file.

## What it writes

For every `@SconModel()` class:

- `extension <Name>SconCodec on <Name>` with `Map<String, Object?> toScon()`;
- `<name>FromScon(Object? value)` which checks required keys, then decodes.

```dart
import 'package:scon/scon.dart';

@SconModel()
class Server {
  Server({required this.host, required this.port, this.tls});

  final String host;
  final int port;

  @SconField('tls')
  final bool? tls;
}
```

```dart
final server = serverFromScon(decodeScon(text));
final text = encodeScon(server.toScon());
```

## Supported field types

`String`, `int`, `double`, `num`, `bool`, `DateTime` (ISO 8601 string), enums
(by `name`), `Object?`/`dynamic`, `List<T>` of those, and other `@SconModel`
classes from the **same file**. Nullable variants of all of the above are
supported. Anything else fails generation with an
`InvalidGenerationSourceError` that names the field.

## Behaviour

- Required keys are the non-nullable fields; decoding a document that misses one
  throws `FormatException('Missing "key" for Type')`.
- `@SconField('name')` overrides the document key.
- Static and private fields are skipped; the generated code depends on nothing
  beyond `scon` itself.

## Not supported (yet)

- Nested models from other files (same-library only);
- getters without backing fields;
- custom converters for `Object?` fields — they pass through unchanged.
