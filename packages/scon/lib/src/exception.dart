/// A SCON document is malformed, or violates a normative rule of the spec.
class SconFormatException implements Exception {
  const SconFormatException(this.message, this.line, this.column);

  final String message;

  /// 1-based line number.
  final int line;

  /// 1-based column number.
  final int column;

  @override
  String toString() => 'SconFormatException: $message (line $line, column $column)';
}

/// The document uses a feature this implementation does not provide.
///
/// Conformance here is Level 2 minus the minified representation; Level 3
/// features (schema blocks, `@s:` references, overrides, imports, autoExtract)
/// are rejected instead of being silently misread.
class SconUnsupportedException implements Exception {
  const SconUnsupportedException(this.message, {this.line});

  final String message;
  final int? line;

  @override
  String toString() =>
      'SconUnsupportedException: $message${line == null ? '' : ' (line $line)'}';
}
