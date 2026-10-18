# scon (Dart)

An **independent Dart implementation** of [SCON 1.0][spec] — Structured Compact
Object Notation. This package is not the specification, does not define it, and
is not affiliated with its author; it only implements the published format.

- Format: SCON 1.0, by **Gustavo Moura** — *SCON: A Textual Serialization Format
  with Structural Deduplication, Tabular Encoding, and Token-Efficient
  Representation* (2026).
- Reference implementations named by the paper: Rust, PHP, JavaScript.
- This package: Dart, hand-written, no runtime dependency beyond the SDK.

## Conformance

| Level | Contents | Status |
|---|---|---|
| 1 — Core | primitives, objects, expanded arrays, inline arrays, minification/expansion | **yes** (`minifyScon`, `expandScon`, `encodeMinified`, `decodeMinified`) |
| 2 — Tabular | Level 1 + tabular encoding (encoder detection and decoder parsing) | **yes** |
| 3 — Full | schema blocks, `@s:` references, overrides, polymorphic composition, directives, imports, autoExtract | **no** (rejected with `SconUnsupportedException`; typed models come from `scon_codegen` instead of in-document schemas) |

Declared conformance: **Level 2**, including the minified representation.

## Usage

```dart
import 'package:scon/scon.dart';

final document = decodeScon('''
server:
 host: localhost
 port: 8080
''');
// {server: {host: localhost, port: 8080}}

final text = encodeScon(document, options: const SconEncodeOptions(includeHeader: true));
// #!scon/1.0
// server:
//  host: localhost
//  port: 8080

final compact = minifyScon(text);
// server:host: localhost;port: 8080
final back = expandScon(compact);   // standard form again
```

Values are plain Dart objects, so a typed layer maps them without a second
model:

| SCON | Dart |
|---|---|
| `null` / `true` / `false` | `null` / `bool` |
| integer / float | `int` / `double` |
| string (quoted or not) | `String` |
| object | `Map<String, Object?>` (insertion ordered) |
| array | `List<Object?>` |

### Options

```dart
decodeScon(source, options: SconDecodeOptions(
  strict: false,          // duplicate keys: last wins (true = error)
  maxDepth: 512,          // the spec requires >= 64
  maxDocumentSize: 64 << 20,
  onWarning: (warning) {}, // duplicate keys, ignored directives
));

encodeScon(value, options: SconEncodeOptions(
  includeHeader: false,
  indent: ' ',
  tabular: true,          // tabular arrays for uniform, flat objects (>= 2)
  inlineArrayLimit: 8,
));
```

## Typed models (`scon_codegen`, build_runner only)

The companion package `scon_codegen` generates `toScon()` and a
`<name>FromScon(Object?)` helper for classes annotated with `@SconModel`. It
depends on **build_runner** (`build` + `source_gen`) and **not** on freezed:

```dart
import 'package:scon/scon.dart';

@SconModel()
class User {
  User({required this.name, this.role});

  final String name;

  @SconField('role')
  final String? role;
}
```

Generated (`user.scon.dart`):

```dart
extension UserSconCodec on User {
  Map<String, Object?> toScon() => <String, Object?>{'name': name, 'role': role};
}

User userFromScon(Object? value) { /* required checks + typed decoding */ }
```

Supported field types: `String`, `int`, `double`, `num`, `bool`, `DateTime`,
enums, `Object?`/`dynamic`, `List<T>` of those, and other `@SconModel` classes
declared in the same library. Nullable types are supported; unsupported types
fail generation with a readable error.

**freezed users** use the sibling package `freezed_scon` instead: it annotates
the freezed class with `@SconFreezed()` and generates the same bridge on top of
freezed's own `toJson`/`fromJson`, so `@JsonKey` and converters keep working.

## Behaviour notes

- **Numbers**: leading zeros are not integers (`007` reads as the string), NaN
  and infinities are not representable and encode as `null` (SCON §24.2). The
  encoder quotes numeric-looking strings such as `0007` so other
  implementations cannot silently turn them into numbers.
- **Strings**: quoted only when required — empty, reserved literals,
  leading/trailing spaces, numeric-looking, or containing `,` `;` `"` `\` `#`
  or control characters. Escapes: `\" \\ \/ \n \r \t \; \b \f \uXXXX`;
  isolated surrogates are rejected.
- **Tabular arrays**: the declared row count is validated against the rows that
  follow (never trusted for allocation, SCON §25.2).
- **Duplicate keys**: last wins plus a warning; `strict: true` errors.
- **Minified form**: one `;` is a sibling, N semicolons close N-1 levels; a
  token that follows a `key:` line with no `;` is its child. Comments and
  directives are not data and are dropped by `minifyScon`.
- **Indentation**: spaces only (tabs are errors); documents start at depth 0;
  BOM is rejected.

## Known gaps

1. **Level 3** is not implemented: in-document schema blocks (`s:`), `@s:`
   references with overrides, polymorphic composition, imports and autoExtract.
   Typed models are handled by `scon_codegen` / `freezed_scon` instead.
2. **Empty objects cannot be represented** by the format; the encoder throws
   `ArgumentError`. Empty arrays are representable (`key[0]:`), including in the
   minified form.
3. `key:` with no block decodes as `null`; other implementations may reject that
   line, so the encoder never emits it.
4. **Canonical form** is this implementation's profile (sorted keys via
   `SconEncodeOptions(canonical: true)`); the paper does not pin one.

## Tests

`dart test` runs 49 cases derived from the specification: document structure,
primitives, quoting and escapes, expanded/inline/tabular arrays, encoder
heuristics, minification/expansion, round trips, limits and the Level 3
rejections.

[spec]: https://zenodo.org/records/18846661
