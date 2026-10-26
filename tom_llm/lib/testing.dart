/// Test support for code that runs an [LlmProvider]: [llmFakeRun], the run
/// of a fake provider built from the text it answers, so every fake gives
/// the shape the contract promises.
///
/// A test double, kept beside the contract it stands in for. Nothing a
/// product links imports this library.
library;

import 'tom_llm.dart';

export 'src/testing/fake_run.dart';
