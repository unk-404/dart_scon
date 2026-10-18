import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/generator.dart';

/// Entry point used by `build.yaml`.
///
/// Emits a **part** file (`<name>.scon.dart`) next to the source, exactly like
/// freezed's own `<name>.freezed.dart`: the model file declares
/// `part '<name>.scon.dart';` and gets `toScon()` / `<name>FromScon(text)`
/// without importing another library.
Builder freezedSconBuilder(BuilderOptions options) => PartBuilder(
      [FreezedSconGenerator()],
      '.scon.dart',
    );
