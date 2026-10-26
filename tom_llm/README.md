# tom_llm

> **Attribution.** The Tom Framework is developed by Peter Nicolai Alexis Kyaw.
> These packages are BSD-3-Clause licensed and internal (`publish_to: none`).

The one LLM provider contract for Tom applications — a request, a provider
that runs it as a stream of typed events, capabilities and availability, and
the call report every completed run is attributed by — with the run trail
those events make: sessions, the fold a trail view shows, the live-trail and
summary-trail files in the VS Code extension's format, and the search for the
Node runtime an agent server runs on. Platform-neutral in its default entry
point, and dependent on no other Tom package, so any graph can take it.

## Overview

Three applications in this workspace talk to models, and each had written its
own provider contract: the brain's (a wire prompt in, a stream of chunks and a
report out), the Agent SDK provider's in `tom_core_agentic` (the same shape,
moved there), and Webwork's (a task, an instruction and a context in, a trail
of events out, with sessions and a live trail file). This package is the one
contract that replaces all three. It is a **union**, not an intersection: a
member exists when any one of the three needed it, so no caller lost a
capability by moving.

- **A request is a wire prompt with options around it.** `LlmRequest` carries
  the `WirePrompt` — the system channel, the user channel, the hash of the
  anchor the producer wrapped it in, and the role, which is the request's
  *purpose* — the `LlmOptions` (model, sampling, tools on offer, response
  format, the session the caller keys continuity on), an `LlmContextSummary`
  for the trail (which context it drew on, by id and count, never its text),
  an `LlmToolBinding` when the model may call tools, and whether its trail
  stays in memory.
- **A provider runs it.** `LlmProvider.run` answers a `Stream<LlmEvent>`: one
  `LlmRunStarted`, the deltas and tool calls, and exactly one `LlmRunEnded` —
  `LlmRunCompleted` with its `LlmCallReport`, or `LlmRunFailed` with its
  `LlmFailure` and, when the provider got that far, a report too. `complete`
  is that stream buffered into the report and throws `LlmTransportException`
  when the run did not complete; a provider may override it with a cheaper
  path. `capabilities`, `isAvailable` and `unavailableReason` let a surface
  offer only what works and say why the rest does not; `embed` refuses unless
  a provider overrides it.
- **A run accounts for itself.** `LlmRunAccount` keeps what a run reports
  about itself — the model, the tokens and cost, each retry and tool call, the
  first error — and ends the run with a report or a reason. A provider whose
  accounting arrives as events ends through it; one that reads its accounting
  off a single terminal message builds the report directly.
- **A trail outlives the run.** Every event converts to and from a map of
  primitives, so it crosses an isolate. `LlmTrails` keeps every session's
  records on the main isolate, a session runs one request at a time and
  refuses a second (`LlmSessionBusyException`), `llmTrailEntries` folds the
  records into what a trail view shows, and `LlmTrailFileWriter` keeps each
  session's `live-trail.<session>.md` — the VS Code extension's live-trail
  format, byte for byte — plus, for a session pointed at a quest folder, its
  prompt and answer history files.

Why one contract matters: a router, a trail, a session registry and a test
fake are each written once, and a provider written for one application runs in
the others. See [`doc/contract.md`](doc/contract.md) for the invariants a
provider keeps and the run model in detail.

## Installation

The package is consumed by path inside this workspace:

```yaml
dependencies:
  tom_llm:
    path: ../../tom_ai/basics/tom_llm
```

Dart SDK `^3.10.0`. No Flutter dependency. The default entry point,
`package:tom_llm/tom_llm.dart`, imports no `dart:io` and compiles
under dart2js; `package:tom_llm/io.dart` adds the machine half of the
Node search, and `package:tom_llm/testing.dart` the test support: a
fake provider's run, which only a test imports.

## Features

| Type | What it does |
| ---- | ------------ |
| `LlmProvider`, `LlmCapabilities`, `LlmUnavailableProvider`, `llmNotConfiguredReason` | The provider contract; what a provider can do; the provider of a build with no AI and the sentence it gives. |
| `LlmRequest`, `WirePrompt`, `LlmOptions`, `LlmContextSummary` | A request: the two-channel prompt and its purpose, the per-call options, what context it drew on. |
| `LlmToolBinding`, `LlmToolAnswer`, `ToolCatalogue`, `ToolDescriptor` | Tools a run may call, and what a call answers the model. |
| `LlmEvent` and its variants (`LlmRunStarted`, `LlmUserPrompt`, `LlmSystemInit`, `LlmThinkingDelta`, `LlmTextDelta`, `LlmToolCall`, `LlmToolResult`, `LlmRetry`, `LlmUsage`, `LlmStall`, `LlmNotice`, `LlmRunError`, `LlmRunEnded`, `LlmSessionOpened`, `LlmSessionClosed`) | The closed run-event union. |
| `LlmRunCompleted`, `LlmRunFailed`, `LlmRunOutcome`, `LlmCallReport`, `LlmFailure`, `CapturedWirePrompt` | How a run ends, and the report and failure it ends with. |
| `LlmRunAccount`, `llmRunPrelude`, `llmAnswerText`, `llmReportOf`, `llmErrorKindOf` | A run's own account; the two events every run opens with; a run as its answer text; a run as its report. |
| `LlmTransportException`, `LlmErrorKind` | The one failure type a run surfaces, classified. |
| `LlmTrails`, `LlmTrailRecord`, `LlmSessionRegistry`, `LlmSessionInfo`, `llmSessionFor` | Sessions and the records they keep; which session a purpose runs in. |
| `llmTrailEntries`, `LlmTrailEntry` and its kinds | The fold a trail view shows. |
| `LlmTrailFileWriter`, `LlmTrailMedium`, `LlmTrailLog`, `LlmQuestTarget`, `LlmLiveTrailText`, `LlmLiveTrailSession`, `llmSummaryTrailPrepend` | The trail files in the VS Code extension's formats. |
| `llmDiscoverNode`, `LlmNodeResolution`, `LlmNodeHost`, `llmNodeAt`; `LlmProcessNodeHost`, `llmNodeResolverFor` (`io.dart`) | The Node search: `PATH`, nvm, Homebrew and `/usr/local`, the newest at or above the floor. |
| `llmFakeRun` (`testing.dart`) | A fake provider's run built from the text it answers: the prelude, the text deltas, a failure as the contract reports one, the end — so every fake gives the shape a real run has. |

## The union, member by member

What each of the three former contracts called a thing, and what it is now.

| Was (brain / `tom_core_agentic`) | Was (Webwork) | Now |
| -------------------------------- | ------------- | --- |
| `LlmProvider.completeStream(WirePrompt, LlmOptions)` | `WebworkAiProvider.run(WebworkAiRequest)` | `LlmProvider.run(LlmRequest)` |
| `LlmProvider.complete(WirePrompt, LlmOptions)` → report | `WebworkAiProvider.complete` → answer text | `LlmProvider.complete(LlmRequest)` → report; `llmAnswerText(run)` → text |
| `LlmProvider.id` | the transport's id | `LlmProvider.id`; a run's report names who served it |
| — | `capabilities`, `isAvailable`, `unavailableReason`, `trails`, `embed` | the same members, with defaults |
| `WirePrompt` (system, user, anchor hash, role, template) | `prompt` + `context` + `task` | `WirePrompt`: the context is the system channel, the instruction the user channel, the task the role (`LlmRequest.purpose`) |
| `LlmOptions` (model, sampling, tools, format, `brainSessionId`) | `parameters`, `sessionId` | `LlmOptions`, its session field named `sessionId` |
| — | `contextMetadata`, `drawsOnEncryptedDocument`, `toolBinding` | `LlmContextSummary`, `keepTrailInMemory`, `LlmToolBinding` |
| `LlmStreamStarted` | `WebworkAiRunStarted(task, transportId)` | `LlmRunStarted(purpose, providerId, modelId, callId)` |
| `LlmStreamChunk` | `WebworkAiTextDelta` | `LlmTextDelta` |
| `LlmStreamToolCallProposed` | `WebworkAiToolCall` | `LlmToolCall` |
| `LlmStreamCompleted(report)` | `WebworkAiRunEnded(completed)` | `LlmRunCompleted(report)` — the report is never absent |
| `LlmStreamFailed(failure, report)` | `WebworkAiRunError` + `WebworkAiRunEnded(failed)` | `LlmRunError` + `LlmRunFailed(failure, report?)` |
| `LlmCallReport`, `LlmFailure`, `CapturedWirePrompt` | — | unchanged |
| — | `WebworkAiTransportException`, its kinds | `LlmTransportException`, `LlmErrorKind` |
| — | `WebworkAiTrails`, the session registry, the trail fold, the trail files, the Node search | the `Llm`-prefixed same, with the file writer over an `LlmTrailMedium` and an `LlmTrailLog` rather than a storage medium and a diagnostics port |

## Quick start

```dart
import 'package:tom_llm/tom_llm.dart';

/// A provider that answers with what it was asked.
class Echo extends LlmProvider {
  @override
  String get id => 'echo';

  @override
  Stream<LlmEvent> run(LlmRequest request) async* {
    final account = LlmRunAccount.of(request.prompt, providerId: id);
    for (final event in llmRunPrelude(request, providerId: id)) {
      account.observe(event);
      yield event;
    }
    yield LlmTextDelta(request.prompt.user);
    yield account.end(LlmRunOutcome.completed, duration: Duration.zero);
  }
}

Future<void> main() async {
  const request = LlmRequest(
    prompt: WirePrompt(
      system: 'You answer briefly.',
      user: 'Say hello.',
      anchorHash: '',
      roleId: 'demo',
    ),
  );
  print(await llmAnswerText(Echo().run(request)).join()); // Say hello.
  print((await Echo().complete(request)).providerId); // echo
}
```

## Limits

- **No transport.** A provider brings its own: an HTTP client, a VS Code
  bridge, a child process. The contract says what goes in and comes out.
- **Embedding is a provider's option, not a requirement.** `embed` refuses
  unless overridden; batching and health checks belong to the application.
- **No anchor of its own.** `WirePrompt.anchorHash` carries whatever anchor
  the producer wrapped the prompt in; an application without one passes an
  empty hash.

## Dependencies

| Dependency | Kind | For |
| ---------- | ---- | --- |
| `meta` | runtime | `@visibleForTesting` |
| `path` | runtime | joining a trail directory and a session's file name |
| `test`, `lints` | dev | the suite |

## Status

Version **0.1.0**. `dart test` runs the unit suite — the value types, the run
events and their round trip through a map, the account, sessions and the
trail fold, the live-trail file held to fixtures the VS Code extension's own
writer produced (`tool/live_trail_fixture/generate.js` regenerates them), the
file writer and the Node search over a fake host — and a walk of the import
closure plus a dart2js compile, which keep the default entry point
platform-neutral.
