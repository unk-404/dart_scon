/// Which normative situation a [SconWarning] reports.
enum SconWarningKind {
  /// The same key appeared twice in one object; the last occurrence won.
  duplicateKey,

  /// The document carried a directive this implementation does not interpret.
  unknownDirective,
}

/// A non-fatal observation made while decoding.
class SconWarning {
  const SconWarning(this.kind, this.message, this.line);

  final SconWarningKind kind;
  final String message;
  final int line;

  @override
  String toString() => 'SconWarning(${kind.name}, line $line): $message';
}

/// Decoder limits and behaviour.
class SconDecodeOptions {
  const SconDecodeOptions({
    this.strict = false,
    this.maxDepth = 512,
    this.maxDocumentSize = 64 * 1024 * 1024,
    this.onWarning,
  });

  /// In strict mode duplicate keys become errors (`@@strict` semantics).
  final bool strict;

  /// Nesting limit; the spec requires at least 64 and suggests 512.
  final int maxDepth;

  /// Documents larger than this are rejected before parsing.
  final int maxDocumentSize;

  /// Receives non-fatal observations (duplicate keys, unknown directives).
  final void Function(SconWarning warning)? onWarning;
}

/// Encoder behaviour.
class SconEncodeOptions {
  const SconEncodeOptions({
    this.includeHeader = false,
    this.indent = ' ',
    this.tabular = true,
    this.inlineArrayLimit = 8,
    this.canonical = false,
  });

  /// Emits the `#!scon/1.0` header line.
  final bool includeHeader;

  /// One indentation unit (the spec convention is a single space).
  final String indent;

  /// Uses tabular encoding for arrays of uniform, flat objects (>= 2 items).
  final bool tabular;

  /// Arrays of primitives up to this length are written on one line.
  final int inlineArrayLimit;

  /// Emits this implementation's canonical profile: object keys are sorted
  /// (code point order) instead of using insertion order, which makes the bytes
  /// stable for equal data regardless of how the map was built.
  final bool canonical;
}
