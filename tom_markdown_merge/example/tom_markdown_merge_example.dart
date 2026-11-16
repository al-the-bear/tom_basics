// Tom Markdown Merge: a generator refreshes the regions of a Markdown file it
// owns and leaves everything a person wrote alone.
//
// The program builds a document from marker blocks, merges fresh generated
// prose into it, shows that an override region wins over a managed region of
// the same key, renders the display form without markers, and shows that a
// malformed document is refused.
//
// Run from the package folder:
//
//   dart run example/tom_markdown_merge_example.dart

import 'package:tom_markdown_merge/tom_markdown_merge.dart';

void main() {
  const merge = MarkdownMerge();

  // A README as a generator first writes it: two managed regions, the
  // author's notes between them, and an override the author added for
  // `status`, which supersedes the generated status.
  final readme = [
    '# Order Service',
    '',
    merge.managedBlock('overview', 'Generated overview, version 1.'),
    '',
    'Notes written by hand. No generator touches this paragraph.',
    '',
    merge.managedBlock('status', 'Generated status: 3 open issues.'),
    merge.overrideBlock('status', 'Status: in review until the next release.'),
  ].join('\n');

  print('managed keys  : ${merge.managedKeys(readme)}'); // {overview, status}
  print('override keys : ${merge.overrideKeys(readme)}'); // {status}

  // The next generator run supplies fresh prose for the keys it owns.
  final merged = merge.merge(readme, {
    'overview': 'Generated overview, version 2.',
    'status': 'Generated status: 0 open issues.',
  });

  print('\n--- merged (markers kept, ready for the next run) ---');
  print(merged);
  // # Order Service
  //
  // <!--$insert:tom.managed.overview-->
  // Generated overview, version 2.
  // <!--$end-insert-->
  //
  // Notes written by hand. No generator touches this paragraph.
  //
  // <!--$insert:tom.managed.status-->
  // Generated status: 3 open issues.        <- not refreshed: overridden
  // <!--$end-insert-->
  // <!--$insert:tom.override.status-->
  // Status: in review until the next release.
  // <!--$end-insert-->

  print('\n--- display form (what a reader sees) ---');
  print(merge.flatten(merged));
  // # Order Service
  //
  // Generated overview, version 2.
  //
  // Notes written by hand. No generator touches this paragraph.
  //
  // Status: in review until the next release.

  // A merge is repeatable: merging the same prose again changes nothing.
  final again = merge.merge(merged, {
    'overview': 'Generated overview, version 2.',
  });
  print('\nsecond merge unchanged : ${again == merged}'); // true

  // A document with an unclosed marker is refused, not half-merged.
  try {
    merge.merge('<!--\$insert:tom.managed.overview-->\nno end marker', {
      'overview': 'x',
    });
  } on FormatException catch (e) {
    print('malformed document     : ${e.message}');
    // malformed document     : Unclosed insert marker
    //   <!--$insert:tom.managed.overview--> at line 1.
  }
}
