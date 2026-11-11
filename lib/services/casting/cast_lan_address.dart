import 'dart:io';

/// A Cast receiver must reach the Wi-Fi/Ethernet side of the sender. Cellular
/// and VPN adapters can also have private IPv4 addresses but are not that LAN.
String? castLanAddress(Map<String, Iterable<String>> interfaces) {
  final candidates = <(int, String)>[];
  for (final entry in interfaces.entries) {
    final name = entry.key.toLowerCase();
    if (RegExp(
      r'^(tun|utun|tap|wg|rmnet|ccmni|pdp_ip|veth|docker|br-|lo\b)|vpn|tailscale',
    ).hasMatch(name))
      continue;
    final physical = RegExp(r'^(wlan|wifi|wi-fi|en\d|eth\d|ethernet)')
        .hasMatch(name);
    for (final host in entry.value) {
      final address = InternetAddress.tryParse(host);
      if (address == null ||
          address.type != InternetAddressType.IPv4 ||
          address.isLoopback ||
          address.isMulticast)
        continue;
      final bytes = address.rawAddress;
      if (bytes[0] == 0 || bytes[0] >= 224) continue;
      final private =
          bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127);
      if (physical || private) candidates.add((physical ? 0 : 1, host));
    }
  }
  candidates.sort((a, b) => a.$1.compareTo(b.$1));
  return candidates.firstOrNull?.$2;
}
