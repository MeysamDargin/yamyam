import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamyam/models/client_account.dart';
import 'package:yamyam/services/vpn_service.dart';

void main() {
  const link =
      'vless://11111111-2222-3333-4444-555555555555@example.com:443?type=tcp&security=reality&pbk=abc&fp=chrome&sni=www.example.com&sid=ab&flow=xtls-rprx-vision#t';

  test('config gets direct/blackhole routing and route-only sniffing', () {
    final cfg = jsonDecode(VpnService.buildConfig(link)) as Map<String, dynamic>;
    final rules = (cfg['routing']['rules'] as List).cast<Map>();
    final tags = (cfg['outbounds'] as List).map((o) => o['tag']).toSet();

    expect(rules.length, 3);
    for (final r in rules) {
      expect(tags, contains(r['outboundTag']));
    }
    expect(rules[0]['ip'], contains('192.168.0.0/16'));
    expect(rules[1]['domain'], contains('domain:ir'));
    expect(rules[2]['port'], '443');

    final sniff = (cfg['inbounds'] as List).first['sniffing'];
    expect(sniff['routeOnly'], isTrue);
  });

  test('account keeps the cached link through JSON', () {
    final a = ClientAccount(
      serverId: 1,
      email: 'e',
      uuid: 'u',
      baseUrl: 'b',
      inboundId: 2,
      createdAt: DateTime(2026),
    );
    expect(a.link, isNull);
    final b = ClientAccount.fromJson(a.withLink(link).toJson());
    expect(b.link, link);
    expect(ClientAccount.fromJson(a.toJson()).link, isNull);
  });
}
