import 'package:flutter_test/flutter_test.dart';
import 'package:yamyam/services/vpn_service.dart';

void main() {
  const id = '11111111-2222-3333-4444-555555555555';

  test('plain VLESS on a public host is flagged', () {
    expect(
      VpnService.incompatibility(
        'vless://$id@game.dargin.net:8443?type=httpupgrade&path=%2Fgame&security=none&encryption=none#x',
      ),
      isNotNull,
    );
  });

  test('VLESS with TLS / Reality / encryption is fine', () {
    expect(VpnService.incompatibility('vless://$id@a.com:443?security=tls&type=ws#x'), isNull);
    expect(
      VpnService.incompatibility('vless://$id@1.2.3.4:443?security=reality&pbk=k&type=tcp#x'),
      isNull,
    );
    expect(
      VpnService.incompatibility('vless://$id@a.com:443?security=none&encryption=mlkem768x25519plus.native.0rtt.abc#x'),
      isNull,
    );
  });

  test('plain VLESS on a private IP and other protocols are allowed', () {
    expect(VpnService.incompatibility('vless://$id@192.168.1.5:8443?security=none#x'), isNull);
    expect(VpnService.incompatibility('vmess://abcdef'), isNull);
    expect(VpnService.incompatibility('trojan://pw@a.com:443#x'), isNull);
  });
}
