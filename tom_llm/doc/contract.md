# The provider contract

How a provider and its caller meet: the invariants a provider keeps, the shape
of a request and of a run, and how a run is accounted for and recorded.
[`README.md`](../README.md) has the overview and the map from the three
contracts this one replaced.

## Two rules every provider keeps

- **The anchor stamp.** Every report carries the prompt's `anchorHash`
  unchanged. A caller that wraps every prompt in an anchor can then prove, from
  reports alone, that every prompt it emitted carried it. A provider that drops
  the hash is a defect, not a variation.
- **No prompt mutation.** A provider must not prepend, append or reorder the
  body it receives. Translating `WirePrompt` into a backend's wire shape is the
  provider's job; changing the text is not.

Provenance follows from the report: its `providerId` names who served the run
(a provider's own `id`, or the transport behind it), `modelId` the resolved
model, `promptHash` the content hash of the prompt body, when the provider
computes one.

## The request

`WirePrompt` is the *result* of assembly, not an input to it. It carries the
body as two channels so a provider can route each natively:

- `system` — the standing framing: an anchor, a persona, the context an
  application assembled.
- `user` — the call's own content, empty for a system-only role.

`combined` joins them with a blank line, dropping an empty part. A backend
with no channel separation sends it; every provider that hashes the prompt
hashes it, so one prompt fingerprints the same across two routes that deliver
its halves differently. `roleId` is the request's **purpose** — what the call
is for — and is what a session registry routes on.

`LlmOptions` holds the per-call knobs: `model` overrides a provider's default
(the resolved id goes on the report either way), `temperature`,
`maxOutputTokens`, `stopSequences`, `toolCatalogue`, `responseFormat`, and
`sessionId`, the key a provider with conversation continuity resumes by.

`LlmContextSummary` records what context the request drew on — the ids
included, how many were elided for a budget or excluded by policy, the
length — so a trail can say what a run read without keeping it.
`keepTrailInMemory` marks a request whose trail must not reach a file.

`LlmToolBinding` is how a run calls tools a caller owns: the declarations to
offer the model, and `call`, which answers with text and whether it is a
refusal. A refusal is an answer, never a throw.

## The run

A run is a stream of `LlmEvent`s:

1. exactly one `LlmRunStarted` — purpose, provider, model, call id;
2. optionally an `LlmUserPrompt` describing the request (by id and count,
   never the context text) — `llmRunPrelude` makes the two;
3. any of `LlmSystemInit`, `LlmThinkingDelta`, `LlmTextDelta`, `LlmToolCall`
   and `LlmToolResult`, `LlmRetry`, `LlmUsage`, `LlmStall`, `LlmNotice`,
   `LlmRunError`;
4. exactly one `LlmRunEnded`.

The end is `LlmRunCompleted`, which always carries its `LlmCallReport`, or
`LlmRunFailed`, which always carries its `LlmFailure` — a class code and a
message — and a report when the provider got far enough to account the call.
`LlmRunEnded(outcome, …)` picks the subclass and refuses a completed run
without a report or a failed one without a reason.

A non-streaming backend emits its answer as one `LlmTextDelta`. The opening
event and the report name the same route: consumers log the route from the
first event, long before a report exists.

`complete` buffers a run into its report, and throws `LlmTransportException`
when the run did not complete — with the first `LlmRunError`'s kind and
message, or the failure's. A provider may override `complete` with a cheaper
path; what it throws on failure is then its own.

## Accounting

`LlmRunAccount` keeps what a run reports about itself — `LlmRunStarted`
(provider, model, call id), `LlmSystemInit` (model), `LlmUsage` (tokens,
cost), each `LlmRetry` and `LlmToolCall`, the first `LlmRunError` — and
`end` makes the terminal event from it. Several parts of one provider can end
a run (a translator that saw the result, a bound that gave up on silence, a
session that was cancelled); each ends it through an account, so the end
always says what the run said.

## Sessions and trails

Every event converts to a map of primitives and back (`toMap`, `fromMap`), so
a run can execute in another isolate. `LlmTrailRecord` is the envelope a
session sends an event in: session, run, sequence number and UTC time.

`LlmTrails` keeps every session's records, its newest twenty runs each, with
synchronous broadcast streams for a view and a file writer. `llmSessionFor`
puts the `agent` purpose in `chat` and every other purpose in `default`, and a
session refuses a second run with `LlmSessionBusyException` rather than
queueing it. `LlmSessionRegistry` adds the sessions a user creates, with an
encoded form an application stores.

`llmTrailEntries` folds records into what a reader sees: a run header with the
instruction and context summary, thinking and text blocks continued while the
same kind keeps arriving, a tool call with its result, notice lines, and a
summary with the usage — runs kept apart across an interleaving.

`LlmTrailFileWriter` keeps one `live-trail.<session>.md` per session in the
VS Code extension's live-trail format, through an `LlmTrailMedium` an
application supplies: the newest five runs and at most 1 MiB, written at most
every 250 ms while a run streams and at once when it ends, continued from
what is on disk. A run whose request keeps its trail in memory reaches no file
unless the session is switched to keep it. A session with an `LlmQuestTarget`
also gets per-run prompt and answer history entries
(`llmSummaryTrailPrepend`). A failed write is reported once per episode
through the `LlmTrailLog` callback and never reaches the run.

## The Node search

An agent server written for Node needs a Node at or above
`llmRequiredNodeMajorVersion`. A desktop app started from a launcher has a
minimal `PATH`, so `llmDiscoverNode` looks where Node actually is — `PATH`,
nvm's versions newest first, Homebrew, `/usr/local` — and takes the first at
or above the floor by version, recording every place it looked. `llmNodeAt`
is the path a user set instead. `LlmProcessNodeHost` and `llmNodeResolverFor`
in `io.dart` are the running machine as the search sees it.
