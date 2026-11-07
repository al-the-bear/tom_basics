import 'file_system.dart';

/// Writing a file whose folder may not exist yet, and reading one that may
/// not exist — what a store keeping its state in a file of its own does on
/// every load and save.
extension TomFileSystemFolders on TomFileSystem {
  /// The folder holding [uri].
  Uri folderOf(Uri uri) => uri.resolve('.');

  /// Makes [folder] (and its parents) when it does not exist.
  Future<void> ensureFolder(Uri folder) async {
    if (!await exists(folder)) await create(folder, directory: true);
  }

  /// [writeText] of [text] to [uri], making its folder first when it is
  /// missing.
  Future<TomFileRevision> writeTextMakingFolder(Uri uri, String text) async {
    await ensureFolder(folderOf(uri));
    return writeText(uri, text);
  }

  /// The text of [uri], or null when it does not exist.
  Future<String?> readTextIfExists(Uri uri) async =>
      await exists(uri) ? await readText(uri) : null;
}
