// Doc Scanner - Documentation scanner
// A pseudo-binary of the fixture (never compiled)
import 'package:_build/_build.dart';

void main(List<String> args) {
  if (isVersionRequest(args)) {
    printToolVersion('doc_scanner');
    return;
  }
  print('doc_scanner: a pseudo-binary of the build_project test fixture');
}
