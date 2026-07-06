/// Guided mode utilities for BuildKit CLI tools.
///
/// Provides interactive prompts through an injectable [PromptDriver], so guided
/// flows run against a real terminal in production and scripted answers in
/// tests.
library;

export 'guided_git_flows.dart';
export 'guided_mode.dart';
export 'project_group_picker.dart';
export 'prompt_driver.dart';
