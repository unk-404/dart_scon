## 0.1.0

- Independent Dart implementation of SCON 1.0: Level 2 conformance (core +
  tabular) minus the minified representation.
- `decodeScon` / `encodeScon` with plain Dart values (`Map`, `List`, `int`,
  `double`, `String`, `bool`, `null`).
- Encoder heuristics: tabular arrays for uniform flat objects, inline arrays for
  short primitive lists, expanded arrays otherwise.
- Spec rules implemented: quoting rules, escape sequences (including `\uXXXX`
  and surrogate handling), last-wins duplicate keys with warnings and strict
  mode, tabular declared-count validation, depth/size limits, no BOM, no tab
  indentation.
- Level 3 constructs are rejected with `SconUnsupportedException`; unknown
  directives are ignored with a warning.
