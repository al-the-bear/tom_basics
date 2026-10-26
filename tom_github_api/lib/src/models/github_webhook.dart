/// A repository webhook, as `POST /repos/{o}/{r}/hooks` returns it.
///
/// Only what a caller can act on is modelled: the id (to delete it), whether
/// it is active, and the events it subscribed to — which is the whole answer
/// when the question is "does GitHub accept this event on this repository",
/// asked by creating an inactive hook and reading the reply.
class GitHubWebhook {
  final int id;
  final bool active;
  final List<String> events;

  const GitHubWebhook({
    required this.id,
    required this.active,
    required this.events,
  });

  factory GitHubWebhook.fromJson(Map<String, dynamic> json) => GitHubWebhook(
        id: json['id'] as int,
        active: json['active'] as bool? ?? true,
        events: (json['events'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(growable: false),
      );

  @override
  String toString() => 'GitHubWebhook(#$id, active: $active, $events)';
}
