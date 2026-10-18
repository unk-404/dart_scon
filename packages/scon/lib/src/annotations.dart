/// Marks a class for SCON encode/decode generation by `scon_codegen`.
///
/// The generator writes `toScon()` and a `fromScon()` helper for the class; it
/// needs a constructor whose named parameters cover the fields.
class SconModel {
  const SconModel();
}

/// Overrides the SCON key of a field.
class SconField {
  const SconField(this.name);

  /// The key used in the document instead of the Dart field name.
  final String name;
}
