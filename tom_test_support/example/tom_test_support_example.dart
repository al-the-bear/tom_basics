import 'package:tom_test_support/tom_test_support.dart';

void main() {
  // The repository this example runs in, found by its marker file.
  print(tomFindRepositoryRoot().path);

  // Whether a live suite would run here, and what its skip would say.
  final live = TomGitHubLiveConfig.fromEnvironment();
  print(live ?? tomLiveSkipReason());

  // The Dart CLI a test may spawn, never the runner taken on trust.
  print(tomDartCli() ?? tomMissingDartReason('run this example'));
}
