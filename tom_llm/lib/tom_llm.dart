/// The one LLM provider contract for Tom applications, and the run trail it
/// streams.
///
/// The contract: [LlmProvider] runs an [LlmRequest] as a stream of
/// [LlmEvent]s, states its [LlmCapabilities] and whether it is available, and
/// reduces a run to its [LlmCallReport] or its text. The trail: the sealed
/// event model, the consolidated trails of a provider's sessions and their
/// registry, the fold into displayable entries, the live-trail and
/// summary-trail file formats and their writer. Node runtime discovery for an
/// agent server: the search, its version floor and its verdict.
///
/// Platform-neutral and dependent on no other Tom package, so a graph that
/// takes the Tom packages by path and one that takes them from pub.dev can
/// both take this one. The `dart:io` half of Node discovery is
/// `package:tom_llm/io.dart`.
library;

export 'src/contract/provider.dart';
export 'src/contract/request.dart';
export 'src/contract/wire.dart';
export 'src/node/node_discovery.dart';
export 'src/trail/account.dart';
export 'src/trail/entries.dart';
export 'src/trail/error.dart';
export 'src/trail/event.dart';
export 'src/trail/live_trail.dart';
export 'src/trail/sessions.dart';
export 'src/trail/summary_trail.dart';
export 'src/trail/trail_file_writer.dart';
