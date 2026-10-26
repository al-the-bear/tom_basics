/// A GitHub label with name, color, and optional description.
class GitHubLabel {
  final int? id;
  final String name;
  final String? color;
  final String? description;

  const GitHubLabel({
    this.id,
    required this.name,
    this.color,
    this.description,
  });

  factory GitHubLabel.fromJson(Map<String, dynamic> json) {
    return GitHubLabel(
      id: json['id'] as int?,
      name: json['name'] as String,
      color: json['color'] as String?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        if (color != null) 'color': color,
        if (description != null) 'description': description,
      };

  @override
  String toString() => 'GitHubLabel($name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GitHubLabel && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
