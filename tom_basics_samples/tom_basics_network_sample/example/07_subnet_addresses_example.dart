// The /24 sweep that powers subnet discovery.
//
// When scanSubnet is on, ServerDiscovery expands each local IP into the 253
// other host addresses on its /24 — .1 through .254, skipping the network (.0)
// and broadcast (.255) addresses and the machine's own IP (already probed
// directly). getSubnetAddresses() exposes that arithmetic on its own, so you
// can see exactly which hosts a scan would touch. Pure computation — no network.
//
// Run with: dart run example/07_subnet_addresses_example.dart
import 'package:tom_basics_network/tom_basics_network.dart';

void main() {
  final hosts = ServerDiscovery.getSubnetAddresses('192.168.1.50');

  print('count: ${hosts.length}');
  print('first: ${hosts.first}');
  print('last: ${hosts.last}');
  print('includes own ip (.50): ${hosts.contains('192.168.1.50')}');
  print('includes broadcast (.255): ${hosts.contains('192.168.1.255')}');
  print('includes network (.0): ${hosts.contains('192.168.1.0')}');

  // A malformed address yields nothing rather than throwing.
  print('malformed -> empty: ${ServerDiscovery.getSubnetAddresses('not-an-ip').isEmpty}');

  // expected output:
  // count: 253
  // first: 192.168.1.1
  // last: 192.168.1.254
  // includes own ip (.50): false
  // includes broadcast (.255): false
  // includes network (.0): false
  // malformed -> empty: true
}
