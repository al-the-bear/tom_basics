/// The unreferenced-export audit as a library: the engine
/// ([auditUnreferencedExports]) and the `unreferenced:` section of a
/// project's `buildkit.yaml` it is configured by
/// ([UnreferencedExportsConfig]). `buildkit :unreferenced` runs it.
library;

export 'src/unreferenced/unreferenced_config.dart';
export 'src/unreferenced/unreferenced_exports.dart';
