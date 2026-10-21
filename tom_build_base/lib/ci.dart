/// A framework for a CI run by hand from the repository.
///
/// Stages run strictly one after another, past any red; every child process
/// runs under the workspace flutter lock ([CiLock]) with each line of its
/// output written to its log as it arrives ([CiProcessRunner]); every log is
/// kept in one timestamped folder; and the run ends with one summary line
/// ([ciSummaryLine]) naming every red step and the log that holds it. What a
/// stage does is the repository's: a [CiStageRunner] handed to [CiRun].
/// [ciToolDefinition] and [ciToolRunner] put the stages on this package's
/// command-line framework.
///
/// Nothing here schedules a run: it is started by a person.
library;

export 'src/ci/ci_lock.dart';
export 'src/ci/ci_process.dart';
export 'src/ci/ci_run.dart';
export 'src/ci/ci_tool.dart';
