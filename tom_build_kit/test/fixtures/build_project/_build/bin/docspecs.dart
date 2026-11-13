// DocSpecs - Document specification validator
// A pseudo-binary of the fixture (never compiled)
import 'package:_build/_build.dart';

void main(List<String> args) {
  if (isVersionRequest(args)) {
    printToolVersion('docspecs');
    return;
  }
  print('docspecs: a pseudo-binary of the build_project test fixture');
}
