import 'dart:io';

/// Resolves GitHub authentication tokens from multiple sources.
class GitHubAuth {
  /// Resolve a token from multiple sources (in order):
  /// 1. Explicit [token] parameter
  /// 2. `GITHUB_TOKEN` environment variable
  /// 3. Token file at `~/.tom/github_token`
  ///
  /// Returns null if no token is found.
  static String? resolveToken({String? token}) {
    // 1. Explicit parameter
    if (token != null && token.isNotEmpty) return token;

    // 2. Environment variable
    final envToken = Platform.environment['GITHUB_TOKEN'];
    if (envToken != null && envToken.isNotEmpty) return envToken;

    // 3. Token file
    final homeDir = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (homeDir.isNotEmpty) {
      final tokenFile = File('$homeDir/.tom/github_token');
      if (tokenFile.existsSync()) {
        final content = tokenFile.readAsStringSync().trim();
        if (content.isNotEmpty) {
          // Return the first line only
          return content.split('\n').first.trim();
        }
      }
    }

    return null;
  }

  /// Resolve a token, throwing [GitHubAuthError] if not found.
  static String resolveTokenOrThrow({String? token}) {
    final resolved = resolveToken(token: token);
    if (resolved == null) {
      throw GitHubAuthError(
        'No GitHub token found. Provide a token via:\n'
        '  1. Explicit parameter\n'
        '  2. GITHUB_TOKEN environment variable\n'
        '  3. File: ~/.tom/github_token',
      );
    }
    return resolved;
  }
}

/// Error thrown when no GitHub token can be resolved.
class GitHubAuthError extends Error {
  final String message;
  GitHubAuthError(this.message);

  @override
  String toString() => 'GitHubAuthError: $message';
}
