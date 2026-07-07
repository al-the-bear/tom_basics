/// Unit tests for [GuidedGitFlows] driven by a [ScriptedPromptDriver].
///
/// Each git command's guided flow gathers menu/confirm/input answers and
/// resolves them into the exact option flags the corresponding git executor
/// understands. These tests drive every flow with scripted answers and assert
/// the resolved flag list — the interactive `-g` behaviour end-to-end, minus the
/// real-terminal I/O. The pure dispatch helpers (`targetCommand`, `rewriteArgs`)
/// that `bin/buildkit.dart` uses to re-dispatch are covered too.
///
/// Menu answers are 1-based indices into the presented options, where
/// [GuidedMode] appends a trailing "Cancel"; the final "Proceed?" confirmation
/// gate consumes one extra `y`/`n` per non-cancelled flow.
///
/// Test IDs: BK-GITGUIDE-1 through BK-GITGUIDE-40
@TestOn('!browser')
library;

import 'package:tom_build_kit/src/guided/guided_git_flows.dart';
import 'package:tom_build_kit/src/guided/guided_mode.dart';
import 'package:tom_build_kit/src/guided/prompt_driver.dart';
import 'package:test/test.dart';

/// Build a resolver whose prompts replay [answers].
GuidedGitFlows _flows(List<String> answers) =>
    GuidedGitFlows(mode: GuidedMode(driver: ScriptedPromptDriver(answers)));

void main() {
  group('gitstatus', () {
    test('BK-GITGUIDE-1: quick overview, no stash, no skip-fetch [2026-07-06]',
        () {
      // view "1"=Quick, stash "n", skip-fetch "n", Proceed "y".
      expect(_flows(['1', 'n', 'n', 'y']).resolve('gitstatus'), <String>[]);
    });

    test('BK-GITGUIDE-2: detailed + stash flags [2026-07-06]', () {
      // view "2"=Detailed → --details, stash "y" → --stash, skip-fetch "n".
      expect(_flows(['2', 'y', 'n', 'y']).resolve('gitstatus'),
          ['--details', '--stash']);
    });

    test('BK-GITGUIDE-3: cancelling the view menu returns null [2026-07-06]',
        () {
      // "3" → Cancel (third option after Quick/Detailed).
      expect(_flows(['3']).resolve('gitstatus'), isNull);
    });
  });

  group('gitcommit', () {
    test('BK-GITGUIDE-4: stage all, commit and push [2026-07-06]', () {
      // stage "1"=all, action "1"=commit+push, message, Proceed "y".
      expect(_flows(['1', '1', 'Fix bug', 'y']).resolve('gitcommit'),
          ['--message', 'Fix bug', '--all', '--push']);
    });

    test('BK-GITGUIDE-5: staged only, commit without push [2026-07-06]', () {
      // stage "2"=only staged, action "2"=commit only, message, Proceed "y".
      expect(_flows(['2', '2', 'wip', 'y']).resolve('gitcommit'),
          ['--message', 'wip']);
    });

    test('BK-GITGUIDE-6: amend takes no message [2026-07-06]', () {
      // stage "1"=all, action "3"=amend, Proceed "y".
      expect(_flows(['1', '3', 'y']).resolve('gitcommit'), ['--amend', '--all']);
    });

    test('BK-GITGUIDE-7: declining the gate returns null [2026-07-06]', () {
      // stage "1", action "1", message, Proceed "n".
      expect(_flows(['1', '1', 'x', 'n']).resolve('gitcommit'), isNull);
    });

    test('BK-GITGUIDE-8: empty message re-prompts until non-empty [2026-07-06]',
        () {
      // stage "1"=all, action "2", message "" (re-prompt), then "real", gate.
      expect(_flows(['1', '2', '', 'real', 'y']).resolve('gitcommit'),
          ['--message', 'real', '--all']);
    });
  });

  group('gitpull', () {
    test('BK-GITGUIDE-9: fast-forward only [2026-07-06]', () {
      expect(_flows(['1', 'y']).resolve('gitpull'), ['--ff-only']);
    });
    test('BK-GITGUIDE-10: allow merge (no flags) [2026-07-06]', () {
      expect(_flows(['2', 'y']).resolve('gitpull'), <String>[]);
    });
    test('BK-GITGUIDE-11: rebase [2026-07-06]', () {
      expect(_flows(['3', 'y']).resolve('gitpull'), ['--rebase']);
    });
    test('BK-GITGUIDE-12: cancel [2026-07-06]', () {
      expect(_flows(['4']).resolve('gitpull'), isNull);
    });
  });

  group('gitbranch', () {
    test('BK-GITGUIDE-13: list with remotes [2026-07-06]', () {
      // action "1"=list, include-remotes "y", Proceed "y".
      expect(_flows(['1', 'y', 'y']).resolve('gitbranch'), ['--all']);
    });
    test('BK-GITGUIDE-14: create branch [2026-07-06]', () {
      expect(_flows(['2', 'feature/x', 'y']).resolve('gitbranch'),
          ['--create', 'feature/x']);
    });
    test('BK-GITGUIDE-15: delete branch [2026-07-06]', () {
      expect(_flows(['3', 'old', 'y']).resolve('gitbranch'),
          ['--delete', 'old']);
    });
  });

  group('gittag', () {
    test('BK-GITGUIDE-16: annotated tag with push [2026-07-06]', () {
      // action "2"=create, name, annotated "y", message, push "y", Proceed "y".
      expect(
          _flows(['2', 'v1.0.0', 'y', 'Release', 'y', 'y']).resolve('gittag'),
          ['--create', 'v1.0.0', '--message', 'Release', '--push']);
    });
    test('BK-GITGUIDE-17: lightweight tag, no push [2026-07-06]', () {
      // create, name, annotated "n", push "n", Proceed "y".
      expect(_flows(['2', 'v2', 'n', 'n', 'y']).resolve('gittag'),
          ['--create', 'v2']);
    });
    test('BK-GITGUIDE-18: delete tag [2026-07-06]', () {
      expect(_flows(['3', 'v0.9', 'y']).resolve('gittag'), ['--delete', 'v0.9']);
    });
    test('BK-GITGUIDE-19: list tags (no flags) [2026-07-06]', () {
      expect(_flows(['1', 'y']).resolve('gittag'), <String>[]);
    });
  });

  group('gitcheckout', () {
    test('BK-GITGUIDE-20: existing branch [2026-07-06]', () {
      expect(_flows(['1', 'main', 'y']).resolve('gitcheckout'),
          ['--branch', 'main']);
    });
    test('BK-GITGUIDE-21: new branch from current [2026-07-06]', () {
      expect(_flows(['2', 'feature/y', 'y']).resolve('gitcheckout'),
          ['--branch', 'feature/y', '--create']);
    });
  });

  group('gitreset', () {
    test('BK-GITGUIDE-22: mixed to HEAD (no flags) [2026-07-06]', () {
      // kind "1"=mixed, target "1"=HEAD, Proceed "y".
      expect(_flows(['1', '1', 'y']).resolve('gitreset'), <String>[]);
    });
    test('BK-GITGUIDE-23: soft to specific ref [2026-07-06]', () {
      // kind "2"=soft, target "3"=specific, ref, Proceed "y".
      expect(_flows(['2', '3', 'abc123', 'y']).resolve('gitreset'),
          ['--soft', '--to', 'abc123']);
    });
    test('BK-GITGUIDE-24: hard to HEAD~1 with danger confirm [2026-07-06]', () {
      // kind "3"=hard, danger "y", target "2"=HEAD~1, Proceed "y".
      expect(_flows(['3', 'y', '2', 'y']).resolve('gitreset'),
          ['--hard', '--to', 'HEAD~1']);
    });
    test('BK-GITGUIDE-25: declining hard danger aborts [2026-07-06]', () {
      // kind "3"=hard, danger "n" → null.
      expect(_flows(['3', 'n']).resolve('gitreset'), isNull);
    });
  });

  group('gitclean', () {
    test('BK-GITGUIDE-26: files and directories [2026-07-06]', () {
      // scope "2"=files+dirs, danger "y", Proceed "y".
      expect(_flows(['2', 'y', 'y']).resolve('gitclean'),
          ['--force', '--directories']);
    });
    test('BK-GITGUIDE-27: files only [2026-07-06]', () {
      expect(_flows(['1', 'y', 'y']).resolve('gitclean'), ['--force']);
    });
    test('BK-GITGUIDE-28: declining danger aborts [2026-07-06]', () {
      expect(_flows(['1', 'n']).resolve('gitclean'), isNull);
    });
  });

  group('gitsync', () {
    test('BK-GITGUIDE-29: merge (no flags) [2026-07-06]', () {
      expect(_flows(['1', 'y']).resolve('gitsync'), <String>[]);
    });
    test('BK-GITGUIDE-30: rebase [2026-07-06]', () {
      expect(_flows(['2', 'y']).resolve('gitsync'), ['--rebase']);
    });
  });

  group('gitprune', () {
    test('BK-GITGUIDE-31: default remote origin [2026-07-06]', () {
      // empty input → default "origin".
      expect(_flows(['', 'y']).resolve('gitprune'), ['--remote', 'origin']);
    });
    test('BK-GITGUIDE-32: custom remote [2026-07-06]', () {
      expect(_flows(['upstream', 'y']).resolve('gitprune'),
          ['--remote', 'upstream']);
    });
  });

  group('gitstash', () {
    test('BK-GITGUIDE-33: tracked only (no flags) [2026-07-06]', () {
      expect(_flows(['1', 'y']).resolve('gitstash'), <String>[]);
    });
    test('BK-GITGUIDE-34: with message [2026-07-06]', () {
      expect(_flows(['2', 'wip', 'y']).resolve('gitstash'),
          ['--message', 'wip']);
    });
    test('BK-GITGUIDE-35: include untracked [2026-07-06]', () {
      expect(_flows(['3', 'y']).resolve('gitstash'), ['--include-untracked']);
    });
  });

  group('gitunstash', () {
    test('BK-GITGUIDE-36: apply most recent (no flags) [2026-07-06]', () {
      expect(_flows(['1', 'y']).resolve('gitunstash'), <String>[]);
    });
    test('BK-GITGUIDE-37: pop most recent [2026-07-06]', () {
      expect(_flows(['2', 'y']).resolve('gitunstash'), ['--pop']);
    });
    test('BK-GITGUIDE-38: apply specific index [2026-07-06]', () {
      expect(_flows(['3', '1', 'y']).resolve('gitunstash'), ['--index', '1']);
    });
  });

  group('gitcompare', () {
    test('BK-GITGUIDE-39: custom base with diffstat [2026-07-06]', () {
      expect(_flows(['develop', '2', 'y']).resolve('gitcompare'),
          ['--base', 'develop', '--stat']);
    });
    test('BK-GITGUIDE-40: default base main, short summary [2026-07-06]', () {
      expect(_flows(['', '1', 'y']).resolve('gitcompare'), ['--base', 'main']);
    });
  });

  group('gitmerge', () {
    test('BK-GITGUIDE-41: standard merge [2026-07-06]', () {
      expect(_flows(['feature/z', '1', 'y']).resolve('gitmerge'),
          ['--branch', 'feature/z']);
    });
    test('BK-GITGUIDE-42: squash [2026-07-06]', () {
      expect(_flows(['feature/z', '2', 'y']).resolve('gitmerge'),
          ['--branch', 'feature/z', '--squash']);
    });
    test('BK-GITGUIDE-43: no fast-forward [2026-07-06]', () {
      expect(_flows(['b', '3', 'y']).resolve('gitmerge'),
          ['--branch', 'b', '--no-ff']);
    });
  });

  group('gitsquash', () {
    test('BK-GITGUIDE-44: count with message [2026-07-06]', () {
      // count "3", message "y", message text, Proceed "y".
      expect(_flows(['3', 'y', 'combined', 'y']).resolve('gitsquash'),
          ['--count', '3', '--message', 'combined']);
    });
    test('BK-GITGUIDE-45: count without message [2026-07-06]', () {
      expect(_flows(['4', 'n', 'y']).resolve('gitsquash'), ['--count', '4']);
    });
    test('BK-GITGUIDE-46: invalid count re-prompts [2026-07-06]', () {
      // "1" invalid (<2), "abc" invalid, "3" valid; then message "n", Proceed.
      expect(_flows(['1', 'abc', '3', 'n', 'y']).resolve('gitsquash'),
          ['--count', '3']);
    });
  });

  group('gitrebase', () {
    test('BK-GITGUIDE-47: rebase onto branch [2026-07-06]', () {
      expect(_flows(['1', 'main', 'y']).resolve('gitrebase'),
          ['--onto', 'main']);
    });
    test('BK-GITGUIDE-48: interactive rebase [2026-07-06]', () {
      expect(_flows(['2', 'main', 'y']).resolve('gitrebase'),
          ['--onto', 'main', '--interactive']);
    });
    test('BK-GITGUIDE-49: abort [2026-07-06]', () {
      expect(_flows(['3', 'y']).resolve('gitrebase'), ['--abort']);
    });
    test('BK-GITGUIDE-50: continue [2026-07-06]', () {
      expect(_flows(['4', 'y']).resolve('gitrebase'), ['--continue']);
    });
  });

  group('unsupported command', () {
    test('BK-GITGUIDE-51: git passthrough has no guided flow [2026-07-06]', () {
      expect(_flows(['1']).resolve('git'), isNull);
      expect(GuidedGitFlows.supports('git'), isFalse);
      expect(GuidedGitFlows.supports('gitcommit'), isTrue);
    });
  });

  group('dispatch helpers', () {
    test('BK-GITGUIDE-52: targetCommand resolves alias to canonical '
        '[2026-07-06]', () {
      // Canonicalizer maps the alias "gc" to "gitcommit".
      final canonical = GuidedGitFlows.targetCommand(
        ['gc'],
        (t) => t == 'gc' ? 'gitcommit' : t,
      );
      expect(canonical, 'gitcommit');
    });

    test('BK-GITGUIDE-53: targetCommand skips unsupported commands '
        '[2026-07-06]', () {
      final canonical = GuidedGitFlows.targetCommand(
        ['compiler', 'gitpull'],
        (t) => t,
      );
      expect(canonical, 'gitpull');
    });

    test('BK-GITGUIDE-54: targetCommand returns null when none supported '
        '[2026-07-06]', () {
      expect(GuidedGitFlows.targetCommand(['compiler'], (t) => t), isNull);
    });

    test('BK-GITGUIDE-55: rewriteArgs strips guide flag and appends flags '
        '[2026-07-06]', () {
      expect(
        GuidedGitFlows.rewriteArgs(
          [':gitcommit', '-g', '-i'],
          ['--message', 'msg', '--push'],
        ),
        [':gitcommit', '-i', '--message', 'msg', '--push'],
      );
    });

    test('BK-GITGUIDE-56: rewriteArgs strips long --guide form [2026-07-06]',
        () {
      expect(
        GuidedGitFlows.rewriteArgs(['--guide', ':gitpull'], ['--rebase']),
        [':gitpull', '--rebase'],
      );
    });
  });
}
