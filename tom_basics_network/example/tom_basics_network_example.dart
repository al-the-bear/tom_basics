import 'package:tom_basics_network/tom_basics_network.dart';

void main() async {
  // Example of using withRetry for HTTP operations
  print('HTTP Retry Configuration:');
  print('Default delays: ${kDefaultRetryDelaysMs.map((ms) => '${ms / 1000}s').join(', ')}');

  // Custom configuration
  const config = RetryConfig(
    retryDelaysMs: [1000, 2000, 4000],
    onRetry: null,
  );

  print('Custom delays: ${config.retryDelaysMs.map((ms) => '${ms / 1000}s').join(', ')}');
}
