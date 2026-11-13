// Markdown to LaTeX converter
// A pseudo-binary of the fixture (never compiled)
import 'package:_build/_build.dart';

void main(List<String> args) {
  if (isVersionRequest(args)) {
    printToolVersion('md2latex');
    return;
  }
  print('md2latex: a pseudo-binary of the build_project test fixture');
}
