// Clone, commit and push with no git binary — here against a git server held
// in memory, so the example runs offline. Point `GitHttpRemote` at any smart
// HTTP URL (GitHub, Gitea, GitLab) with `GitCredentials.token` to do the same
// over the network.
import 'dart:convert';

import 'package:tom_git/testing.dart';
import 'package:tom_git/tom_git.dart';

Future<void> main() async {
  final server = GitMemoryServer();
  await server.seed({'README.md': utf8.encode('# Hello\n')});

  final remote = GitHttpRemote(server.url, client: server.client);
  final clone = GitRepository.memory();

  // Fetch the default branch.
  final refs = await remote.listRefs();
  final branch = refs.defaultBranch ?? 'main';
  final fetched = await clone.fetchBranch(remote, branch, refs: refs);
  final tip = fetched.tip!;
  print('fetched $branch at ${tip.hex}');

  // Commit a change without an index or a working tree.
  final base = (await clone.readCommit(tip)).tree;
  final tree = await clone.editTree(
    base,
    writes: {'notes/today.md': utf8.encode('- write the example\n')},
  );
  final commit = await clone.commit(
    tree: tree,
    parents: [tip],
    message: 'Add a note',
    author: GitPerson.now('Example', 'example@localhost'),
  );

  // Push it; a refusal says whether somebody else moved the branch.
  final result = await clone.pushBranch(remote, branch, commit, remoteTip: tip);
  print(result.ok ? 'pushed ${commit.hex}' : 'refused: $result');

  for (final entry in await clone.listFiles(tree, '')) {
    print('  ${entry.path}');
  }
  remote.close();
}
