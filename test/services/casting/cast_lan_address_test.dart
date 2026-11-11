import 'package:flick/services/casting/cast_lan_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Wi-Fi address wins over cellular and VPN private addresses', () {
    expect(
      castLanAddress({
        'rmnet_data0': ['10.30.0.2'],
        'tun0': ['10.8.0.2'],
        'pdp_ip0': ['10.1.1.1'],
        'unknown': ['172.19.0.2'],
        'wlan0': ['192.168.1.20'],
      }),
      '192.168.1.20',
    );
    expect(
      castLanAddress({
        'utun4': ['10.1.1.1'],
        'en0': ['192.168.1.8'],
      }),
      '192.168.1.8',
    );
  });
  test('cellular/VPN only cannot advertise an unreachable media URL', () {
    expect(
      castLanAddress({
        'rmnet0': ['10.1.1.1'],
        'tun0': ['192.168.1.20'],
      }),
      isNull,
    );
    expect(castLanAddress({}), isNull);
  });
  test('Ethernet and carrier-shared Wi-Fi work, invalid and local-only hosts do not', () {
    expect(
      castLanAddress({
        'eth0': ['172.20.1.5'],
      }),
      '172.20.1.5',
    );
    expect(
      castLanAddress({
        'wlan0': ['100.65.1.2'],
      }),
      '100.65.1.2',
    );
    expect(
      castLanAddress({
        'wlan0': ['0.0.0.0', '127.0.0.1', '224.0.0.1', '::1', 'invalid'],
      }),
      isNull,
    );
  });
}
