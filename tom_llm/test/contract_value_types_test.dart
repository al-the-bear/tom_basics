// The contract's value types, which a provider test reaches only in passing.
//
// A provider's own suite constructs an `LlmOptions` and a `WirePrompt` on the
// way to something else. That is enough to catch a type that fails to build
// and nothing else: the two behaviours
// below are both *distinctions* — omit versus clear, and which channels are
// present — so a test that exercises one arm of each proves nothing about the
// other.
//
// `WirePrompt.combined` is the one with reach beyond its own file. It feeds
// `promptSha256`, which stamps `LlmCallReport.promptHash`, which is how a trail
// correlates prompts across runs; a change to the join silently changes every
// hash that has ever been recorded, and nothing would fail.
library;

import 'package:test/test.dart';
import 'package:tom_llm/tom_llm.dart';

void main() {
  group('LlmOptions.copyWith distinguishes omitting from clearing', () {
    const populated = LlmOptions(
      model: 'm-1',
      temperature: 0.5,
      maxOutputTokens: 256,
      stopSequences: ['STOP'],
      responseFormat: {'type': 'json'},
      sessionId: 's-1',
    );

    test('omitting a nullable field keeps its value', () {
      // Every sentinel-guarded field at once: the copy changes nothing because
      // nothing was passed. This is the arm a `??` implementation also
      // satisfies, which is why the clearing test below is the real one.
      final copy = populated.copyWith();

      expect(copy.model, 'm-1');
      expect(copy.temperature, 0.5);
      expect(copy.maxOutputTokens, 256);
      expect(copy.responseFormat, {'type': 'json'});
      expect(copy.sessionId, 's-1');
    });

    test('passing null to a nullable field clears it', () {
      // The arm the `_unset` sentinel exists for, and the one a `??`
      // implementation gets wrong by keeping the old value instead.
      final cleared = populated.copyWith(
        model: null,
        temperature: null,
        maxOutputTokens: null,
        responseFormat: null,
        sessionId: null,
      );

      expect(cleared.model, isNull);
      expect(cleared.temperature, isNull);
      expect(cleared.maxOutputTokens, isNull);
      expect(cleared.responseFormat, isNull);
      expect(cleared.sessionId, isNull);
    });

    test('each nullable field clears independently', () {
      // Clearing one must not disturb the others. The five share one sentinel
      // and one expression shape, so a copy-paste slip between them is the
      // realistic defect and is invisible to the all-at-once tests above.
      expect(populated.copyWith(model: null).temperature, 0.5);
      expect(populated.copyWith(temperature: null).model, 'm-1');
      expect(populated.copyWith(maxOutputTokens: null).sessionId, 's-1');
      expect(populated.copyWith(responseFormat: null).maxOutputTokens, 256);
      expect(populated.copyWith(sessionId: null).responseFormat, {
        'type': 'json',
      });
    });

    test('the two non-nullable fields cannot be cleared, only replaced', () {
      // `stopSequences` and `toolCatalogue` are non-nullable with defaults, so
      // their parameters mean "replace, or leave alone" — `null` is the second,
      // not "clear". The asymmetry with the five above is deliberate and is
      // exactly the kind of thing a reader assumes away.
      expect(populated.copyWith(stopSequences: null).stopSequences, ['STOP']);
      expect(
        populated.copyWith(stopSequences: const []).stopSequences,
        isEmpty,
      );

      final catalogue = ToolCatalogue(const [
        ToolDescriptor(name: 't', description: 'd', parametersSchema: {}),
      ]);
      final withTools = populated.copyWith(toolCatalogue: catalogue);
      expect(withTools.toolCatalogue.tools.single.name, 't');
      expect(
        withTools.copyWith(toolCatalogue: null).toolCatalogue,
        same(catalogue),
      );
    });

    test('LlmOptions.empty is all defaults', () {
      expect(LlmOptions.empty.model, isNull);
      expect(LlmOptions.empty.stopSequences, isEmpty);
      expect(LlmOptions.empty.toolCatalogue.isEmpty, isTrue);
    });
  });

  group('WirePrompt.combined joins the two channels', () {
    test('both channels present: system first, blank line between', () {
      const prompt = WirePrompt(
        system: 'ANCHOR\n\nframing',
        user: 'inputs',
        anchorHash: 'h',
        roleId: 'r',
      );

      expect(prompt.combined, 'ANCHOR\n\nframing\n\ninputs');
    });

    test('empty user: no trailing separator', () {
      // The system-only role. A naive join leaves the prompt ending in two
      // newlines, which changes its hash without changing its meaning.
      const prompt = WirePrompt(
        system: 'ANCHOR\n\nframing',
        anchorHash: 'h',
        roleId: 'r',
      );

      expect(prompt.user, isEmpty);
      expect(prompt.combined, 'ANCHOR\n\nframing');
    });

    test('empty system: the user channel alone', () {
      // Not a shape a producer should emit — the anchor is supposed to lead
      // `system` — but the join defines an answer for it, and an untested
      // branch is one a refactor is free to change.
      const prompt = WirePrompt(
        system: '',
        user: 'inputs',
        anchorHash: 'h',
        roleId: 'r',
      );

      expect(prompt.combined, 'inputs');
    });

    test('the anchor leads combined whenever it leads system', () {
      // The property the whole anchor invariant rests on once a provider with
      // no channel separation sends `combined` rather than the two parts.
      const prompt = WirePrompt(
        system: 'ANCHOR-BLOCK\n\nframing',
        user: 'inputs',
        anchorHash: 'h',
        roleId: 'r',
      );

      expect(prompt.combined.startsWith('ANCHOR-BLOCK'), isTrue);
    });

    test('templateSha stays null rather than becoming a placeholder', () {
      const prompt = WirePrompt(system: 's', anchorHash: 'h', roleId: 'r');

      expect(prompt.templateSha, isNull);
    });
  });

  group('the tool types, as a caller meets them', () {
    test('an empty catalogue is how a role says "no tools"', () {
      expect(ToolCatalogue.empty.isEmpty, isTrue);
      expect(ToolCatalogue.empty.isNotEmpty, isFalse);
      expect(ToolCatalogue.empty.tools, isEmpty);
      // The default on every call: a provider that surfaces tool calls reads
      // this and finds nothing to offer.
      expect(LlmOptions.empty.toolCatalogue.isEmpty, isTrue);
    });

    test('a populated catalogue keeps declaration order', () {
      const first = ToolDescriptor(
        name: 'search',
        description: 'Find a thing.',
        parametersSchema: {'type': 'object'},
      );
      const second = ToolDescriptor(
        name: 'write',
        description: 'Change a thing.',
        parametersSchema: {},
      );
      const catalogue = ToolCatalogue([first, second]);

      expect(catalogue.isNotEmpty, isTrue);
      // Order is part of the contract: provider adapters translate these into
      // provider-native schemas, and a reordered catalogue is a different
      // prompt.
      expect(catalogue.tools.map((t) => t.name), ['search', 'write']);
      expect(second.parametersSchema, isEmpty);
    });
  });

  group('the run events', () {
    test('each run event is told apart by its type', () {
      // `LlmToolCall` is never emitted by the shipped provider —
      // Claude Code owns its own tool loop — but it is a variant of a *sealed*
      // family, so every consumer that switches must still handle it. This is
      // the shape that consumer takes, and it is what makes the variant part
      // of the surface rather than dead weight.
      const report = LlmCallReport(
        providerId: 'p',
        modelId: 'm',
        anchorHash: 'h',
        promptHash: 'ph',
        tokensIn: 0,
        tokensOut: 0,
        retries: 0,
        wallClockMs: 0,
      );
      final events = <LlmEvent>[
        const LlmRunStarted(callId: 'c', providerId: 'p', modelId: 'm'),
        const LlmTextDelta('hello'),
        const LlmToolCall(
          callId: 'tc-1',
          name: 'search',
          arguments: {'q': 'anchor'},
        ),
        const LlmRunCompleted(callId: 'c', report: report),
        const LlmRunFailed(
          callId: 'c',
          failure: LlmFailure(classCode: 'unknown', message: 'nope'),
          report: report,
        ),
      ];

      final seen = [
        for (final event in events)
          switch (event) {
            LlmRunStarted() => 'started',
            LlmTextDelta() => 'chunk',
            LlmToolCall() => 'tool',
            LlmRunCompleted() => 'completed',
            LlmRunFailed() => 'failed',
            _ => 'other',
          },
      ];

      expect(seen, ['started', 'chunk', 'tool', 'completed', 'failed']);
    });

    test('a proposed tool call carries what a caller needs to resolve it', () {
      const proposed = LlmToolCall(
        callId: 'tc-1',
        name: 'search',
        arguments: {'q': 'anchor'},
      );

      // The id is what pairs the caller's answer back to the proposal; the
      // name is what it resolves against its own catalogue.
      expect(proposed.callId, 'tc-1');
      expect(proposed.name, 'search');
      expect(proposed.arguments['q'], 'anchor');
    });

    test('a failed run still carries an attributable report', () {
      // The property that makes a failure auditable: the call is still
      // attributed to a route even though it produced no answer.
      const failed = LlmRunFailed(
        callId: 'c',
        failure: LlmFailure(classCode: 'unknown', message: 'nope'),
        report: LlmCallReport(
          providerId: 'p',
          modelId: 'm',
          anchorHash: 'h',
          promptHash: 'ph',
          tokensIn: 0,
          tokensOut: 0,
          retries: 1,
          wallClockMs: 12,
        ),
      );

      expect(failed.report!.providerId, 'p');
      expect(failed.report!.retries, 1);
      expect(failed.failure.cause, isNull);
    });
  });
}
