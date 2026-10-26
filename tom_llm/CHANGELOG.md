# Changelog

## 0.1.0

### Package

- Lives in the basics repository (`tom_ai/basics/tom_llm`); it was
  `tom_core_llm` in `tom_ai/core` before its first release.

### Added

- **Test support.** `package:tom_llm/testing.dart`: `llmFakeRun`, the
  run of a fake provider built from the text it answers.
- **The provider contract.** `LlmProvider` with `run(LlmRequest)` as a stream
  of `LlmEvent`s and `complete` derived from it, `capabilities`, availability
  with a reason, `trails` and a refusing `embed`; `LlmUnavailableProvider` for
  a build with no AI.
- **The request.** `WirePrompt` (two channels, anchor hash, role as purpose),
  `LlmOptions`, `LlmContextSummary`, `LlmToolBinding` with `LlmToolAnswer`,
  `ToolCatalogue` and `ToolDescriptor`.
- **The run.** The closed `LlmEvent` union, ended by `LlmRunCompleted` (with
  its `LlmCallReport`) or `LlmRunFailed` (with its `LlmFailure`);
  `LlmRunAccount`, which ends a run from its own events; `llmRunPrelude`,
  `llmAnswerText`, `llmReportOf`; `LlmTransportException` and `LlmErrorKind`.
- **Sessions and trails.** `LlmTrails`, `LlmTrailRecord`,
  `LlmSessionRegistry`, `llmSessionFor`; the trail fold `llmTrailEntries`;
  `LlmTrailFileWriter` with the live-trail and summary-trail formats of the
  VS Code extension, over an `LlmTrailMedium` and an `LlmTrailLog`.
- **The Node search.** `llmDiscoverNode` and its report; the machine half,
  `LlmProcessNodeHost` and `llmNodeResolverFor`, behind `io.dart`.
