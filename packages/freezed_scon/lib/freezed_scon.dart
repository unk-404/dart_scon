import 'package:scon/scon.dart';

export 'src/annotation.dart';

/// Encodes a freezed model by borrowing its generated JSON mapping.
String encodeFreezed<T>(
  T value,
  Map<String, Object?> Function(T value) toJson, {
  SconEncodeOptions options = const SconEncodeOptions(),
}) =>
    encodeScon(toJson(value), options: options);

/// Decodes SCON text into a freezed model through its generated `fromJson`.
T decodeFreezed<T>(
  String source,
  T Function(Map<String, Object?> json) fromJson, {
  SconDecodeOptions options = const SconDecodeOptions(),
}) {
  final decoded = decodeScon(source, options: options);
  if (decoded is! Map) {
    throw FormatException(
      'Expected a SCON object, got ${decoded.runtimeType}',
    );
  }
  return fromJson(decoded.cast<String, Object?>());
}
