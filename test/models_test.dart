import 'package:flutter_test/flutter_test.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/models/client_stats.dart';

void main() {
  test('AppConfig parses the panel /api/v1/config payload', () {
    final cfg = AppConfig.fromJson({
      'maintenance': {'enabled': true, 'message': 'تعمیر'},
      'update': {
        'available': true,
        'version_name': '1.2.0',
        'version_code': 12,
        'download_url': 'https://x.com/a.apk',
        'changelog': ['a', 'b'],
        'force': false,
        'min_supported_code': 5,
      },
      'message': {
        'id': 3, 'title': 'hi', 'body': 'x', 'level': 'warning',
        'button_text': '', 'button_url': '', 'dismissible': true,
      },
      'support': {'telegram': '@yy', 'website': '', 'email': ''},
      'client_defaults': {'traffic_gb': 50, 'expiry_days': 30, 'limit_ip': 2},
      'servers': [
        {
          'id': 2, 'title': 'US', 'country': 'آمریکا', 'country_code': 'US',
          'flag': '🇺🇸', 'base_url': 'https://b.com:2053/p/', 'inbound_id': 1,
          'priority': 2, 'verify_ssl': false, 'api_token': 'tok',
        },
        {
          'id': 1, 'title': 'DE', 'country': 'آلمان', 'country_code': 'DE',
          'flag': '🇩🇪', 'base_url': 'https://a.com', 'inbound_id': 3,
          'priority': 1, 'verify_ssl': true,
        },
      ],
    });

    expect(cfg.maintenance.enabled, isTrue);
    expect(cfg.message!.id, 3);
    expect(cfg.clientDefaults.trafficGb, 50);
    expect(cfg.servers.map((s) => s.id), [1, 2]); // sorted by priority
    expect(cfg.servers[1].baseUrl, 'https://b.com:2053/p'); // trailing slash trimmed
    expect(cfg.servers[1].verifySsl, isFalse);
    expect(cfg.servers[0].canManageClients, isFalse); // no token exposed
    expect(cfg.servers[1].canManageClients, isTrue);
    expect(cfg.serverById(1)!.title, 'DE');
  });

  test('UpdateInfo: optional vs forced', () {
    const u = UpdateInfo(
      available: true, versionCode: 12, downloadUrl: 'https://x',
      force: false, minSupportedCode: 5,
    );
    expect(u.needsUpdate(12), isFalse);
    expect(u.needsUpdate(11), isTrue);
    expect(u.isForced(11), isFalse); // optional
    expect(u.isForced(4), isTrue); // below min supported
    expect(const UpdateInfo(available: true, versionCode: 12, downloadUrl: 'u', force: true).isForced(11), isTrue);
    expect(const UpdateInfo(available: false, versionCode: 12, downloadUrl: 'u').needsUpdate(1), isFalse);
  });

  group('ClientStats', () {
    ClientStats mk({bool enable = true, int up = 0, int down = 0, int total = 0, int expiry = 0}) =>
        ClientStats(
          email: 'e', uuid: 'u', enable: enable, up: up, down: down,
          total: total, expiryTime: expiry, lastOnline: 0, fetchedAt: DateTime.now(),
        );

    test('states', () {
      expect(mk().state, AccountState.active);
      expect(mk(enable: false).state, AccountState.disabled);
      expect(mk(expiry: 1000).state, AccountState.expired);
      expect(mk(total: 100, up: 60, down: 40).state, AccountState.depleted);
      expect(mk(total: 100, up: 10).canConnect, isTrue);
    });

    test('usage + days', () {
      final s = mk(total: 1000, up: 100, down: 150,
          expiry: DateTime.now().add(const Duration(days: 10, hours: 1)).millisecondsSinceEpoch);
      expect(s.used, 250);
      expect(s.usedFraction, closeTo(0.25, 1e-9));
      expect(s.usedPercent, 25);
      expect(s.remainingBytes, 750);
      expect(mk().usedPercent, isNull);
      expect(mk(total: 100, up: 100).usedPercent, 100);
      expect(s.daysLeft, 11);
      expect(mk().daysLeft, isNull);
      expect(mk(expiry: -3 * 86400000).daysLeft, 3);
    });
  });
}
