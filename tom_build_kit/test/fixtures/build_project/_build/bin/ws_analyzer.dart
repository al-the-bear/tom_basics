// Workspace Analyzer - Analyzes workspace structure
// Delegates to tom_build_cli functionality
import 'package:_build/_build.dart';
import 'package:tom_build_cli/cli_entry.dart';

void main(List<String> args) {
  if (isVersionRequest(args)) {
    printToolVersion('ws_analyzer');
    return;
  }
  wsAnalyzerMain(args);
}
