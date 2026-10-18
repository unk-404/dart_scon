/// Marks a freezed class whose SCON codec should be generated.
///
/// Deliberately import-free: the annotation must be resolvable without the
/// helper library's dependencies.
class SconFreezed {
  const SconFreezed();
}
