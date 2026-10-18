import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/generator.dart';

/// Entry point used by `build.yaml`.
Builder sconBuilder(BuilderOptions options) =>
    LibraryBuilder(SconGenerator(), generatedExtension: '.scon.dart');
