/// An independent Dart implementation of **SCON 1.0**.
///
/// The format is specified by Gustavo Moura ("SCON: A Textual Serialization
/// Format with Structural Deduplication, Tabular Encoding, and Token-Efficient
/// Representation", 2026) and this package only implements part of that
/// specification — it neither defines nor owns the format.
///
/// Conformance: **Level 2** (core + tabular) minus the minified representation.
/// Level 3 features (schema blocks, `@s:` references, overrides, imports,
/// autoExtract) are rejected with [SconUnsupportedException] rather than
/// misparsed.
///
/// Values map to plain Dart objects so any typed layer (freezed,
/// json_serializable, hand-written) can consume them without another model:
///
/// | SCON | Dart |
/// |---|---|
/// | `null` / `true` / `false` | `null` / `bool` |
/// | integer / float | `int` / `double` |
/// | string | `String` |
/// | object | `Map<String, Object?>` (insertion ordered) |
/// | array | `List<Object?>` |
library;

export 'src/annotations.dart' show SconField, SconModel;
export 'src/decoder.dart' show decodeScon;
export 'src/encoder.dart' show encodeScon;
export 'src/exception.dart' show SconFormatException, SconUnsupportedException;
export 'src/minified.dart'
    show decodeMinified, encodeMinified, expandScon, minifyScon;
export 'src/options.dart'
    show SconDecodeOptions, SconEncodeOptions, SconWarning, SconWarningKind;
