/// Macro expansion with placeholder support for CLI tools.
///
/// Macros are defined as `name=value` pairs where value can contain:
/// - `$1` through `$9` - positional placeholders
/// - `$$` - rest placeholder (all remaining arguments)
/// - `\$n` - escaped literal `$n`
///
/// Example usage:
/// ```dart
/// final macros = {'vp': ':versioner --project \$1'};
/// final args = ['@vp', 'tom_build_base', '--list'];
/// final expanded = expandMacros(args, macros);
/// // Result: [':versioner', '--project', 'tom_build_base', '--list']
/// ```
library;

/// Exception thrown when macro expansion fails.
class MacroExpansionException implements Exception {
  final String message;
  final String macroName;
  final String? detail;

  MacroExpansionException(this.message, this.macroName, {this.detail});

  @override
  String toString() {
    final d = detail != null ? ': $detail' : '';
    return 'MacroExpansionException: $message (macro: @$macroName)$d';
  }
}

/// Expand macros in argument list.
///
/// Finds tokens starting with `@` and expands them using the provided
/// [macros] map. Placeholders in the macro value are substituted with
/// arguments following the macro invocation.
///
/// Returns a new list with macros expanded. Throws [MacroExpansionException]
/// if a macro requires more arguments than provided.
List<String> expandMacros(List<String> args, Map<String, String> macros) {
  if (args.isEmpty || macros.isEmpty) return List.of(args);

  final result = <String>[];
  var i = 0;

  while (i < args.length) {
    final arg = args[i];

    // Check if this is a macro invocation (starts with @ and has content)
    if (arg.startsWith('@') && arg.length > 1 && !arg.contains('@', 1)) {
      final macroName = arg.substring(1);
      final macroValue = macros[macroName];

      if (macroValue != null) {
        // Expand this macro
        final (expanded, consumed) = _expandMacro(
          macroName,
          macroValue,
          args,
          i + 1,
          macros,
        );
        result.addAll(expanded);
        i += 1 + consumed; // Skip macro token + consumed args
      } else {
        // Undefined macro - keep as-is
        result.add(arg);
        i++;
      }
    } else {
      // Not a macro - keep as-is
      result.add(arg);
      i++;
    }
  }

  return result;
}

/// Expand a single macro with its arguments.
///
/// Returns a tuple of (expanded tokens, number of arguments consumed).
(List<String>, int) _expandMacro(
  String name,
  String value,
  List<String> args,
  int argStart,
  Map<String, String> macros,
) {
  // First, recursively expand any nested macros in the value
  final valueTokens = _tokenize(value);
  final expandedValueTokens = expandMacros(valueTokens, macros);

  // Find placeholders in the value
  final hasRest = value.contains(r'$$');
  final requiredArgs = _getMaxPlaceholder(value);

  // Calculate how many args we need to consume
  int argsToConsume;
  if (hasRest) {
    // $$ consumes all remaining args after positional placeholders
    argsToConsume = args.length - argStart;
  } else {
    argsToConsume = requiredArgs;
  }

  // Validate we have enough args
  final availableArgs = args.length - argStart;
  if (requiredArgs > availableArgs) {
    throw MacroExpansionException(
      'Not enough arguments for macro',
      name,
      detail: 'requires $requiredArgs argument(s), got $availableArgs',
    );
  }

  // Build positional arg map
  final positionalArgs = <int, String>{};
  for (var n = 1; n <= requiredArgs && (argStart + n - 1) < args.length; n++) {
    positionalArgs[n] = args[argStart + n - 1];
  }

  // Get rest args
  final restStart = argStart + requiredArgs;
  final restArgs = restStart < args.length
      ? args.sublist(restStart)
      : <String>[];

  // Process each token in the expanded value, preserving argument boundaries
  final resultTokens = <String>[];
  for (final token in expandedValueTokens) {
    // Check if this token is exactly a placeholder
    if (RegExp(r'^\$([1-9])$').hasMatch(token)) {
      // Single placeholder token - replace with arg (preserving as single token)
      final n = int.parse(token.substring(1));
      if (positionalArgs.containsKey(n)) {
        resultTokens.add(positionalArgs[n]!);
      } else {
        resultTokens.add(token); // Keep as-is if no arg
      }
    } else if (token == r'$$') {
      // Rest placeholder - add each rest arg as separate token
      resultTokens.addAll(restArgs);
    } else if (token.contains(r'$')) {
      // Token contains placeholders mixed with other text
      var processed = token;

      // Handle escaped placeholders first
      const escapeMarker = '\x00ESC\x00';
      processed = processed.replaceAllMapped(
        RegExp(r'\\(\$\d|\$\$)'),
        (m) => '$escapeMarker${m.group(1)}$escapeMarker',
      );

      // Substitute positional placeholders
      for (final entry in positionalArgs.entries) {
        processed = processed.replaceAll('\$${entry.key}', entry.value);
      }

      // Substitute rest placeholder
      processed = processed.replaceAll(r'$$', restArgs.join(' '));

      // Restore escaped placeholders
      processed = processed.replaceAllMapped(
        RegExp(
          '${RegExp.escape(escapeMarker)}(.*?)${RegExp.escape(escapeMarker)}',
        ),
        (m) => m.group(1)!,
      );

      resultTokens.add(processed);
    } else {
      // No placeholders - keep as-is
      resultTokens.add(token);
    }
  }

  return (resultTokens, argsToConsume);
}

/// Get the highest placeholder number in a string.
int _getMaxPlaceholder(String value) {
  var max = 0;
  // Match $1 through $9, but not escaped \$n or $$
  final regex = RegExp(r'(?<!\\)\$([1-9])');
  for (final match in regex.allMatches(value)) {
    final n = int.parse(match.group(1)!);
    if (n > max) max = n;
  }
  return max;
}

/// Tokenize a string into arguments.
///
/// Handles quoted strings to preserve argument boundaries.
List<String> _tokenize(String input) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inQuote = false;
  var quoteChar = '';

  for (var i = 0; i < input.length; i++) {
    final c = input[i];

    if (inQuote) {
      if (c == quoteChar) {
        inQuote = false;
        // Keep the content without quotes
      } else {
        buffer.write(c);
      }
    } else if (c == '"' || c == "'") {
      inQuote = true;
      quoteChar = c;
    } else if (c == ' ' || c == '\t') {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
    } else {
      buffer.write(c);
    }
  }

  if (buffer.isNotEmpty) {
    tokens.add(buffer.toString());
  }

  return tokens;
}

/// Get the number of required arguments for a macro.
///
/// Returns the highest placeholder number, or -1 if the macro uses `$$`.
int getRequiredArgCount(String macroValue) {
  if (macroValue.contains(r'$$')) return -1;
  return _getMaxPlaceholder(macroValue);
}
