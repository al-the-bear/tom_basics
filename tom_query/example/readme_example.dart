// The README example, compiled: a small task index, queried through the one
// evaluator, sorted, and a backlink index over notes that reference each other.
import 'package:tom_query/tom_query.dart';

/// Tasks, keyed by id, each owned by a project.
class TaskIndex with TomIndexQuery<String> {
  TaskIndex._(this._tasks);

  factory TaskIndex.build(Map<String, Map<String, Object?>> tasks) =>
      TaskIndex._(tasks);

  final Map<String, Map<String, Object?>> _tasks;

  @override
  List<TomIndexEntry<String>> get entries => [
    for (final MapEntry(:key, :value) in _tasks.entries)
      TomIndexEntry(
        payload: value['title']! as String,
        id: key,
        ownerId: value['project']! as String,
      ),
  ];

  @override
  Set<String> get properties => const {'status', 'due', 'tags'};

  @override
  Object? valueOf(TomIndexEntry<String> entry, String key) =>
      _tasks[entry.id]![key];
}

/// Notes: each note lists the notes it links to, `#id` or `other#id`.
class NoteLinks implements TomRefSource<Map<String, List<String>>> {
  const NoteLinks();

  @override
  Iterable<String> recordIds(Map<String, List<String>> document) =>
      document.keys;

  @override
  bool holds(Map<String, List<String>> document, String recordId) =>
      document.containsKey(recordId);

  @override
  List<TomRefSlot> slotsOf(
    String locator,
    Map<String, List<String>> document,
    String recordId,
  ) => [
    for (final (i, link) in (document[recordId] ?? const <String>[]).indexed)
      TomRefSlot(
        childIndex: i,
        embedded: false,
        alias: null,
        targetLocator: link.startsWith('#') ? locator : link.split('#').first,
        targetId: link.split('#').last,
      ),
  ];
}

class NoteBacklinks extends TomBacklinkIndex<Map<String, List<String>>> {
  NoteBacklinks() : super(const NoteLinks());

  @override
  Set<String> get properties => const {};

  @override
  Object? valueOf(TomIndexEntry<TomBackref> entry, String key) => null;
}

void main() {
  final tasks = TaskIndex.build({
    't1': {
      'title': 'Write spec',
      'project': 'p1',
      'status': 'open',
      'due': DateTime.utc(2026, 10, 20),
      'tags': {'docs/api'},
    },
    't2': {
      'title': 'Ship',
      'project': 'p1',
      'status': 'done',
      'due': DateTime.utc(2026, 10, 25),
    },
    't3': {'title': 'Review', 'project': 'p2', 'status': 'open'},
  });

  // Open, and tagged under docs/ (which covers docs/api).
  final openDocs = tasks.query(
    const TomPropertyQuery([
      TomQueryTerm('status', TomAnyOf(['open'])),
      TomQueryTerm('tags', TomAnyOf(['docs'], hierarchical: true)),
    ]),
  );
  print([for (final e in openDocs) e.payload]);

  final undated = tasks.query(
    const TomPropertyQuery([TomQueryTerm('due', TomUnset())]),
  );
  print([for (final e in undated) e.id]);

  final byDue = TomPropertySorter<TomIndexEntry<String>>(
    value: (e) => tasks.valueOf(e, 'due'),
    tieBreak: (e) => [e.id],
    descending: true,
  );
  print([for (final e in byDue.sorted(tasks.entries)) e.id]);

  final links = NoteBacklinks()
    ..openDocument('a', {
      'home': ['#ideas', 'b#plan'],
      'ideas': ['#home'],
    });
  print(links.backrefsOf('a', 'ideas').map((e) => e.sourceId).toList());
  final toPlan = links.forwardRefsOf('a', 'home').last;
  print(
    '${toPlan.targetLocator}#${toPlan.targetId} '
    'pending=${links.isPending(toPlan)}',
  );
  links.openDocument('b', {'plan': []});
  print('pending=${links.isPending(toPlan)}');
}
