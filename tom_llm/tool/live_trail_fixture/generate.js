// Regenerates test/fixtures/live_trail/ — `extension_kinds.md` after the
// first three runs (every block kind) and `extension_rolling.md` after seven
// (the newest five kept) — by running the
// VS Code extension's own LiveTrailWriter (its compiled `out/`) through the
// scenario `wonetesta19_live_trail_file_test.dart` renders, so the fixture is
// what the extension writes rather than what somebody believes it writes.
//
//   node tool/live_trail_fixture/generate.js <extension root> <output folder>
//
// The extension root is the folder holding the extension's `out/`. `vscode`
// is stubbed; the clock is fixed to local wall-clock times, which the Dart
// side renders from the same local times.
'use strict';
const Module = require('module');
const path = require('path');
const fs = require('fs');

const [extensionRoot, folder] = process.argv.slice(2).map((p) => p && path.resolve(p));
if (!extensionRoot || !folder) {
  console.error('usage: generate.js <extension root> <output folder>');
  process.exit(2);
}

const vscodeStub = {
  workspace: {
    workspaceFolders: [{ uri: { fsPath: folder } }],
    getConfiguration: () => ({ get: () => undefined }),
  },
  window: { activeTextEditor: undefined },
  Uri: { file: (p) => ({ fsPath: p }) },
};
const load = Module._load;
Module._load = function (request, ...rest) {
  if (request === 'vscode') return vscodeStub;
  return load.call(this, request, ...rest);
};

// A clock the script moves by hand: each run starts at its own minute.
const RealDate = Date;
let now = new RealDate(2026, 9, 12, 14, 30, 0).getTime();
global.Date = class extends RealDate {
  constructor(...args) { super(...(args.length ? args : [now])); }
  static now() { return now; }
};

const { LiveTrailWriter } = require(path.join(extensionRoot, 'out/services/live-trail.js'));
const output = path.join(folder, 'extension_rolling.md');
if (fs.existsSync(output)) fs.unlinkSync(output);
const w = new LiveTrailWriter('fixture');
w.filePath = output; // the writer's own field; the stub workspace is not used

function at(minute) { now = new RealDate(2026, 9, 12, 14, minute, 0).getTime(); }

// Run 1: every block kind.
at(30);
w.beginPrompt({ transport: 'hosted-cli', config: 'agent', userText: 'Rename the plan section.\nKeep its children.' });
// The session hands the writer whole lines: the deltas 'Let me ' and
// 'look first.' arrive as one call when the thinking block ends.
w.appendThinking('Let me look first.');
w.appendAssistantText('Reading the section.');
w.beginToolCall('webwork_get_section', { sectionId: '7f3c9e21', depth: 1 }, 'c1');
w.appendToolResult('# Plan\nThree beds.', 18);
w.beginToolCall('webwork_update_section', { sectionId: '7f3c9e21', headline: 'x'.repeat(2100) }, 'c2');
w.appendToolResult('y'.repeat(900), 5000);
w.appendRetry('Retrying (attempt 2).', 'HTTP 529 overloaded');
w.appendNotice('Waiting for background tasks.');
w.appendThinking('Now rename.');
w.appendAssistantText('Renamed **Plan**.');
at(31);
w.appendUsage({
  totals: { inputTokens: 12412, outputTokens: 318, cacheReadInputTokens: 2000, cacheCreationInputTokens: 0 },
  models: [{ model: 'claude-sonnet-4-5', inputTokens: 12412, outputTokens: 318, cacheReadInputTokens: 2000, cacheCreationInputTokens: 0, costUSD: 0.0119 }],
  totalCostUsd: 0.0119,
  durationApiMs: 5200,
});
w.endPrompt({ rounds: 3, toolCalls: 2, durationMs: 6400 });

// Run 2: a failure after a stall.
at(32);
w.beginPrompt({ transport: 'standalone-node', config: 'summarize', userText: 'Summarize.' });
w.appendNotice('Nothing arrived for 120 s; the run was abandoned.');
w.endPromptWithError('No answer from the AI server for 120 seconds.');

// Run 3: cancelled.
at(33);
w.beginPrompt({ transport: 'hosted-cli', config: 'generate', userText: 'Write an intro.' });
w.appendAssistantText('Once');
w.endPromptWithInterruption('cancelled', 'The run was cancelled.');

fs.copyFileSync(output, path.join(folder, 'extension_kinds.md'));

// Runs 4–7: short, to push the first two out of the newest five.
for (let i = 4; i <= 7; i++) {
  at(30 + i);
  w.beginPrompt({ transport: 'hosted-cli', config: 'categorize', userText: `Run ${i}.` });
  w.appendAssistantText(`Answer ${i}.`);
  w.endPrompt({ rounds: 1, toolCalls: 0, durationMs: 1000 * i });
}
console.log(`wrote ${folder}`);
