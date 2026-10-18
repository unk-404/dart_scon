## 0.1.0

- `@SconFreezed()` + build_runner generator that writes a **part file**
  (`<name>.scon.dart`) into the model's library: `String toScon()` and
  `<name>FromScon(String)` on top of freezed's `toJson`/`fromJson`.
- `encodeFreezed` / `decodeFreezed` helpers for hand-written codecs.
- Fails generation with a readable error when the class lacks `fromJson` or
  `toJson` (or when the matching `part` directive is missing).
- No dependency on freezed at build time: the generator only inspects members.
