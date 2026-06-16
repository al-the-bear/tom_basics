/// The four publication states a component (Dart package) can be in
/// (spec §4.2.1), ordered from least to most mature.
enum ComponentStatus {
  /// The package path is missing, or `lib/` is a stub at or below the LOC
  /// threshold.
  notStarted('not_started'),

  /// Real code — `lib/` carries more than the LOC threshold — but the package
  /// is not published from a public repo.
  works('works'),

  /// Lives in a public repo and is a real, publishable pub package
  /// (`publish_to` is not `none` and it has a version).
  published('published'),

  /// Carries an explicit release marker — a `tom_project.yaml`
  /// `release.state: released`, or a `release.md` in the package dir.
  released('released');

  const ComponentStatus(this.yamlValue);

  /// The canonical token written to `content/modules/*.yaml`.
  final String yamlValue;
}
