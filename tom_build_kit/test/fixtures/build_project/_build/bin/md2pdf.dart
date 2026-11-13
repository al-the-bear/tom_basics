// Markdown to PDF converter
// A pseudo-binary of the fixture (never compiled)
import 'package:_build/_build.dart';

void main(List<String> args) {
  if (isVersionRequest(args)) {
    printToolVersion('md2pdf');
    return;
  }
  print('md2pdf: a pseudo-binary of the build_project test fixture');
}
