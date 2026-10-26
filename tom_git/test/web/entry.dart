// Compiled by web_safe_test.dart: everything the default entry point exports
// has to link for the browser.
import 'package:tom_git/tom_git.dart';

void main() {
  print(GitObject.blob([1, 2, 3]).id);
  print(GitRepository.memory().objects);
  print(GitHttpRemote(Uri.parse('https://example.test/r.git')).url);
}
