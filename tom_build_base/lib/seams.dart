/// A source-level engine for package-boundary audits ("seams").
///
/// A repository states its boundaries as **rules** — which entry point may
/// reach which package, which package may depend on which, where a name may
/// be declared — and checks them against the source on every run, so a
/// boundary is a check with an exit code rather than a sentence in a design
/// document. This library is the engine those rules are written in; the rules
/// themselves are the repository's.
///
/// - Reading source: [directiveUris], [stripDartComments],
///   [dartCodeWithoutComments], [topLevelDeclarations], [callArgumentsFrom].
/// - The import graph: [importClosureOf], [siblingImportClosureOf],
///   [externalImportsOf], [reachableNamesOf], [packageImportsUnder],
///   [exportedDeclarationsOf].
/// - The package graph: [Pubspec], [packagesIn], [prefixedPackagesIn],
///   [resolvedPackagesOf], [dependencyReach], [declaredTypeNamesUnder].
/// - Rules: [EntryPointRule] with [auditEntryPointRules]; [upwardPathDerivations]
///   for tests that count their way to a root.
/// - Running: [SeamViolation], [SeamAudit], [runSeamAudits],
///   [resolveRepositoryRoot], [resolveWorkspaceRoot].
///
/// Every check reads files; nothing here parses with the analyzer or runs a
/// process, so an audit over a large repository runs in seconds.
library;

export 'src/seams/dart_source.dart';
export 'src/seams/entry_points.dart';
export 'src/seams/import_graph.dart';
export 'src/seams/pubspec_graph.dart';
export 'src/seams/seam_audit.dart';
export 'src/seams/upward_paths.dart';
