import 'dart:io';

import 'package:dcli/dcli.dart' as dcli;
import 'package:path/path.dart' as p;

import 'cli_arg_parser.dart';
import 'command_executor.dart';
import 'tool_runner.dart';
import '../traversal/command_context.dart';

/// Generic cross-platform symbolic-link executor.
///
/// Intended for non-traversal command use (e.g. `:mklink <target> <link>`).
/// Uses dcli filesystem helpers for link creation.
class MkLinkExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: 'mklink uses executeWithoutTraversal',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final positional = args.positionalArgs;
    if (positional.length < 2) {
      return const ToolResult.failure(
        'Usage: :mklink <target-path> <link-path> [--force]',
      );
    }

    final targetPath = positional[0].trim();
    final linkPath = positional[1].trim();

    if (targetPath.isEmpty || linkPath.isEmpty) {
      return const ToolResult.failure(
        'Target path and link path must both be non-empty.',
      );
    }

    final force = args.force || args.extraOptions['force'] == true;

    if (args.dryRun) {
      stdout.writeln('[DRY RUN] mklink "$targetPath" "$linkPath"');
      return const ToolResult.success();
    }

    try {
      final linkEntityType = FileSystemEntity.typeSync(
        linkPath,
        followLinks: false,
      );
      if (linkEntityType != FileSystemEntityType.notFound) {
        if (!force) {
          return ToolResult.failure(
            'Destination already exists: $linkPath (use --force to replace)',
          );
        }
        _deleteExistingEntity(linkPath, linkEntityType);
      }

      final linkParentDir = Directory(p.dirname(linkPath));
      if (!linkParentDir.existsSync()) {
        linkParentDir.createSync(recursive: true);
      }

      dcli.createSymLink(targetPath: targetPath, linkPath: linkPath);

      if (args.verbose) {
        stdout.writeln('Created symbolic link: $linkPath -> $targetPath');
      }
      return const ToolResult.success();
    } catch (error) {
      return ToolResult.failure('Failed to create symbolic link: $error');
    }
  }

  void _deleteExistingEntity(String path, FileSystemEntityType type) {
    switch (type) {
      case FileSystemEntityType.directory:
        Directory(path).deleteSync(recursive: true);
      case FileSystemEntityType.file:
        File(path).deleteSync();
      case FileSystemEntityType.link:
        Link(path).deleteSync();
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
      case FileSystemEntityType.notFound:
        return;
    }
  }
}
