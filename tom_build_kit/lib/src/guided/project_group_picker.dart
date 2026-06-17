/// Project group picker for git operations.
///
/// Provides project-level file scope selection instead of individual files.
library;

import 'dart:io';

import 'package:dcli/dcli.dart' as dcli;
import 'package:path/path.dart' as p;

/// Multi-select using DCli menu with toggle pattern.
///
/// Returns list of selected indices.
List<int> _multiSelect({
  required String prompt,
  required List<String> options,
  List<bool>? defaults,
}) {
  final selected = List<bool>.filled(options.length, false);
  if (defaults != null && defaults.length == options.length) {
    for (var i = 0; i < defaults.length; i++) {
      selected[i] = defaults[i];
    }
  }

  print('$prompt (toggle with Enter, type "done" when finished)');

  while (true) {
    final menuOptions = <String>[
      ...options.asMap().entries.map(
            (e) => '${selected[e.key] ? "[x]" : "[ ]"} ${e.value}',
          ),
      '--- Done ---',
    ];

    final choice = dcli.menu(
      'Toggle selection:',
      options: menuOptions,
      defaultOption: menuOptions.last,
    );

    if (choice == '--- Done ---') break;

    // Find which option was selected and toggle it
    final index = menuOptions.indexOf(choice);
    if (index >= 0 && index < options.length) {
      selected[index] = !selected[index];
    }
  }

  return [for (var i = 0; i < selected.length; i++) if (selected[i]) i];
}

/// Represents a project scope group for git operations.
enum ProjectScope {
  /// Complete project (all files)
  complete('Complete project', 'All files in the project'),

  /// Code only (bin/ and lib/)
  code('Code only', 'bin/ and lib/ folders'),

  /// Examples (example/)
  example('Examples', 'example/ folder'),

  /// Tests (test/)
  tests('Tests', 'test/ folder');

  const ProjectScope(this.label, this.description);

  /// Display label
  final String label;

  /// Description
  final String description;

  /// Get the folder paths for this scope (relative to project root).
  List<String> get folders {
    switch (this) {
      case ProjectScope.complete:
        return ['.'];
      case ProjectScope.code:
        return ['bin', 'lib'];
      case ProjectScope.example:
        return ['example'];
      case ProjectScope.tests:
        return ['test'];
    }
  }
}

/// Result of project group selection.
class ProjectGroupSelection {
  ProjectGroupSelection({
    required this.projects,
    required this.scopes,
  });

  /// Selected project directories
  final List<String> projects;

  /// Selected scopes for each project
  final Map<String, List<ProjectScope>> scopes;

  /// Get all file paths based on selection.
  ///
  /// This returns the folder paths that should be included in git operations.
  List<String> getFilePaths() {
    final paths = <String>[];

    for (final project in projects) {
      final projectScopes = scopes[project] ?? [ProjectScope.complete];

      for (final scope in projectScopes) {
        for (final folder in scope.folders) {
          final path = folder == '.' ? project : p.join(project, folder);
          if (Directory(path).existsSync()) {
            paths.add(path);
          }
        }
      }
    }

    return paths;
  }

  /// Check if selection is empty.
  bool get isEmpty => projects.isEmpty;

  /// Check if any project has partial scope (not complete).
  bool get hasPartialScope => scopes.values.any(
        (list) => !list.contains(ProjectScope.complete),
      );
}

/// Project group picker for selecting project scopes in git operations.
class ProjectGroupPicker {
  ProjectGroupPicker({
    required this.workspaceRoot,
    this.changedProjects,
  });

  /// Workspace root directory
  final String workspaceRoot;

  /// Optional list of projects with changes (for smart defaults)
  final List<String>? changedProjects;

  /// Show the project group picker.
  ///
  /// Returns null if cancelled.
  ProjectGroupSelection? pick() {
    // Step 1: Project scope selection
    print('');
    final scopeOptions = [
      'All changed projects (complete)',
      'All changed projects (select scope per project)',
      'Select specific projects',
      'Cancel',
    ];
    final scopeChoice = scopeOptions.indexOf(dcli.menu(
      'What to include?',
      options: scopeOptions,
      defaultOption: scopeOptions[0],
    ));

    if (scopeChoice == 3) return null;

    List<String> selectedProjects;
    Map<String, List<ProjectScope>> scopes = {};

    switch (scopeChoice) {
      case 0:
        // All changed projects, complete scope
        selectedProjects = changedProjects ?? [];
        for (final proj in selectedProjects) {
          scopes[proj] = [ProjectScope.complete];
        }

      case 1:
        // All changed projects, select scope per project
        selectedProjects = changedProjects ?? [];
        for (final proj in selectedProjects) {
          final projectScopes = _pickScopesForProject(proj);
          if (projectScopes == null) return null;
          scopes[proj] = projectScopes;
        }

      case 2:
        // Select specific projects
        if (changedProjects == null || changedProjects!.isEmpty) {
          print('No projects with changes detected.');
          return null;
        }

        final selected = _multiSelect(
          prompt: 'Select projects',
          options: changedProjects!.map((p) => _formatProjectName(p)).toList(),
          defaults: List.filled(changedProjects!.length, true),
        );

        if (selected.isEmpty) return null;

        selectedProjects = selected.map((i) => changedProjects![i]).toList();

        // Ask for scope selection mode
        final perProject = dcli.confirm(
          'Select scope per project?',
          defaultValue: false,
        );

        if (perProject) {
          for (final proj in selectedProjects) {
            final projectScopes = _pickScopesForProject(proj);
            if (projectScopes == null) return null;
            scopes[proj] = projectScopes;
          }
        } else {
          // Same scope for all
          final commonScopes = _pickScopes('Select scope for all projects');
          if (commonScopes == null) return null;
          for (final proj in selectedProjects) {
            scopes[proj] = commonScopes;
          }
        }

      default:
        return null;
    }

    return ProjectGroupSelection(
      projects: selectedProjects,
      scopes: scopes,
    );
  }

  /// Pick scopes for a specific project.
  List<ProjectScope>? _pickScopesForProject(String project) {
    final name = _formatProjectName(project);
    return _pickScopes('Select scope for $name',
        projectPath: project);
  }

  /// Pick scopes with multi-select.
  List<ProjectScope>? _pickScopes(String prompt, {String? projectPath}) {
    // Build options based on what folders exist
    final availableScopes = <ProjectScope>[];
    final options = <String>[];

    for (final scope in ProjectScope.values) {
      bool exists = true;

      if (projectPath != null && scope != ProjectScope.complete) {
        // Check if folders exist
        exists = scope.folders.any(
          (f) => Directory(p.join(projectPath, f)).existsSync(),
        );
      }

      if (exists) {
        availableScopes.add(scope);
        options.add('${scope.label} (${scope.description})');
      }
    }

    if (options.isEmpty) {
      options.add('Complete project');
      availableScopes.add(ProjectScope.complete);
    }

    // If only Complete is available, return it directly
    if (availableScopes.length == 1) {
      return [ProjectScope.complete];
    }

    final selected = _multiSelect(
      prompt: prompt,
      options: options,
      defaults: [true, ...List.filled(options.length - 1, false)],
    );

    if (selected.isEmpty) return null;

    return selected.map((i) => availableScopes[i]).toList();
  }

  /// Format project path for display.
  String _formatProjectName(String projectPath) {
    // Show relative path from workspace root
    if (projectPath.startsWith(workspaceRoot)) {
      return p.relative(projectPath, from: workspaceRoot);
    }
    return p.basename(projectPath);
  }
}

/// Quick scope picker for simpler use cases.
///
/// Returns list of [ProjectScope]s selected, or null if cancelled.
List<ProjectScope>? pickProjectScopes({
  String prompt = 'What to include?',
  bool allowMultiple = true,
}) {
  final options = ProjectScope.values
      .map((s) => '${s.label} (${s.description})')
      .toList();
  options.add('Cancel');

  if (allowMultiple) {
    final selected = _multiSelect(
      prompt: prompt,
      options: options.sublist(0, options.length - 1), // Exclude Cancel
      defaults: [true, false, false, false],
    );

    if (selected.isEmpty) return null;
    return selected.map((i) => ProjectScope.values[i]).toList();
  } else {
    final choice = dcli.menu(
      prompt,
      options: options,
      defaultOption: options[0],
    );

    final selectedIndex = options.indexOf(choice);
    if (selectedIndex == options.length - 1) return null;
    return [ProjectScope.values[selectedIndex]];
  }
}
