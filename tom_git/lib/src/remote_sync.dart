/// Fetching a branch into a repository and pushing one out of it.
library;

import 'object_id.dart';
import 'pack.dart';
import 'remote.dart';
import 'repository.dart';

/// The remote-tracking ref for [branch] of [remoteName]:
/// `refs/remotes/origin/main`.
String gitTrackingRef(String branch, {String remoteName = 'origin'}) =>
    'refs/remotes/$remoteName/$branch';

/// What a fetch found.
class GitFetchResult {
  const GitFetchResult({required this.tip, required this.fetched});

  /// The branch tip on the remote, or null when the remote has no such
  /// branch.
  final GitObjectId? tip;

  /// Whether objects had to be transferred (false when the tip was here).
  final bool fetched;
}

/// Fetching and pushing for a [GitRepository].
extension GitRepositoryRemote on GitRepository {
  /// Brings [branch] of [remote] into this repository: its objects, and the
  /// remote-tracking ref. Transfers nothing when the tip is already here.
  ///
  /// [refs] is a listing already made — passing it saves a round trip when
  /// one listing serves several branches.
  Future<GitFetchResult> fetchBranch(
    GitHttpRemote remote,
    String branch, {
    String remoteName = 'origin',
    GitRemoteRefs? refs,
  }) async {
    final listing = refs ?? await remote.listRefs();
    final tip = listing.refs['refs/heads/$branch'];
    final tracking = gitTrackingRef(branch, remoteName: remoteName);
    if (tip == null) {
      await this.refs.delete(tracking);
      return const GitFetchResult(tip: null, fetched: false);
    }
    var fetched = false;
    if (!await objects.contains(tip)) {
      final haves = [
        for (final id in (await this.refs.list(
          'refs/remotes/$remoteName/',
        )).values)
          if (await objects.contains(id)) id,
      ];
      final pack = await remote.fetchPack(wants: [tip], haves: haves);
      await objects.writePack(pack);
      fetched = true;
    }
    await this.refs.write(tracking, tip);
    return GitFetchResult(tip: tip, fetched: fetched);
  }

  /// Moves [branch] on [remote] from [remoteTip] (null: create it) to
  /// [newTip], sending the objects the remote lacks.
  ///
  /// The server decides: a refusal is reported in the result, not thrown, so
  /// a caller can tell a lost race ([GitPushResult.isRace]) from a fault — a
  /// refused ref is checked against a fresh listing, so the verdict does not
  /// rest on how the server words it. On success the remote-tracking ref
  /// follows.
  Future<GitPushResult> pushBranch(
    GitHttpRemote remote,
    String branch,
    GitObjectId newTip, {
    GitObjectId? remoteTip,
    String remoteName = 'origin',
  }) async {
    final send = await objectsToSend(
      [newTip],
      excluded: [if (remoteTip != null) remoteTip],
    );
    final result = await remote.push([
      GitRefUpdate(
        'refs/heads/$branch',
        oldId: remoteTip ?? GitObjectId.zero,
        newId: newTip,
      ),
    ], gitWritePack(send));
    if (result.ok) {
      await refs.write(gitTrackingRef(branch, remoteName: remoteName), newTip);
      return result;
    }
    if (result.unpackError != null || result.refErrors.isEmpty) return result;
    // Servers word a stale old value differently, so whether the ref moved is
    // measured rather than read from the reason.
    final now = (await remote.listRefs()).refs['refs/heads/$branch'];
    return result.withRemoteMoved(now != remoteTip);
  }

  /// Deletes [branch] on [remote], which must be at [remoteTip].
  Future<GitPushResult> deleteRemoteBranch(
    GitHttpRemote remote,
    String branch, {
    required GitObjectId remoteTip,
    String remoteName = 'origin',
  }) async {
    final result = await remote.push([
      GitRefUpdate(
        'refs/heads/$branch',
        oldId: remoteTip,
        newId: GitObjectId.zero,
      ),
    ], null);
    if (result.ok) {
      await refs.delete(gitTrackingRef(branch, remoteName: remoteName));
    }
    return result;
  }
}
