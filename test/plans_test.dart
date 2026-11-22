import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yamyam/ads/ad_ledger.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ads_manager.dart';
import 'package:yamyam/ads/media_cache.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/services/xui_service.dart';

const _gb = 1024 * 1024 * 1024;

void main() {
  group('plan models', () {
    test('plans off by default / when disabled', () {
      expect(PlansInfo.fromJson(null).enabled, isFalse);
      expect(PlansInfo.fromJson({'enabled': false}).canPurchase, isFalse);
      expect(const PlansInfo().canPurchase, isFalse);
    });

    test('plans info parses packages, payment and ui', () {
      final p = PlansInfo.fromJson({
        'enabled': true,
        'free': {'title': 'رایگان'},
        'gold': {
          'title': 'طلایی',
          'packages': [
            {
              'id': 7,
              'title': 'یک ماهه',
              'price': 100000,
              'old_price': 150000,
              'duration_days': 30,
              'daily_gb': 0,
              'total_gb': 200,
            }
          ],
        },
        'payment': {'card_number': '6037997400000000', 'card_holder': 'علی', 'receipt': 'image'},
        'ui': {'show_plan_chip': true},
      });
      expect(p.canPurchase, isTrue);
      final pk = p.gold.packages.single;
      expect(pk.hasDiscount, isTrue);
      expect(pk.dailyUnlimited, isTrue);
      expect(pk.totalUnlimited, isFalse);
      expect(p.payment.hasCard, isTrue);
      expect(p.payment.wantsImage, isTrue);
      expect(p.payment.wantsTracking, isFalse);
    });

    test('server plan modes', () {
      expect(ServerPlan.fromJson(null), isNull);
      final g = ServerPlan.fromJson({'free_mode': 'gold_only'})!;
      expect(g.goldOnly, isTrue);
      final l = ServerPlan.fromJson({'free_mode': 'limited', 'free_daily_gb': 2})!;
      expect(l.goldOnly, isFalse);
      expect(l.freeDailyGb, 2);
    });

    test('server spec', () {
      final s = ServerSpec.fromJson({
        'mode': 'gold',
        'total': 5 * _gb,
        'reset': 'daily',
        'cap': 100 * _gb,
        'cap_period': 'monthly',
      });
      expect(s.gold, isTrue);
      expect(s.dailyReset, isTrue);
      expect(s.unlimited, isFalse);
      expect(s.totalGb, 5);
      expect(s.capGb, 100);
      expect(ServerSpec.fromJson({'mode': 'blocked', 'enabled': false}).blocked, isTrue);
      expect(ServerSpec.fromJson({'mode': 'free'}).unlimited, isTrue);
    });

    test('user plan parsing + changed flag + open order', () {
      final u = UserPlan.fromJson({
        'enabled': true,
        'plan': {'kind': 'gold', 'title': 'طلایی', 'days_left': 12, 'expires_ms': 1},
        'servers': {
          '1': {'mode': 'gold', 'total': 0},
          'x': {'mode': 'free'},
        },
        'applied': {
          'servers': {
            '1': {'changed': true, 'ok': true},
          }
        },
        'orders': [
          {'id': 3, 'status': 'approved'},
          {'id': 4, 'status': 'pending'},
        ],
      });
      expect(u.gold, isTrue);
      expect(u.daysLeft, 12);
      expect(u.servers.keys, [1]);
      expect(u.changed, isTrue);
      expect(u.openOrder!.id, 4);
      expect(u.hasOpenOrder, isTrue);
      expect(UserPlan.free.gold, isFalse);
    });

    test('app config carries plans + per-server plan', () {
      final c = AppConfig.fromJson({
        'servers': [
          {
            'id': 1,
            'title': 'a',
            'plan': {'free_mode': 'gold_only'},
          },
          {'id': 2, 'title': 'b'},
        ],
        'plans': {'enabled': true},
      });
      expect(c.plans.enabled, isTrue);
      expect(c.servers[0].plan!.goldOnly, isTrue);
      expect(c.servers[1].plan, isNull);
    });
  });

  group('XuiApi.clientBody', () {
    const d = ClientDefaults(trafficGb: 10, expiryDays: 30, limitIp: 2);

    test('no spec → legacy defaults', () {
      final b = XuiApi.clientBody(email: 'yy-a', flow: '', defaults: d, nowMs: 1000);
      expect(b['totalGB'], 10 * _gb);
      expect(b['expiryTime'], 1000 + 30 * 86400000);
      expect(b['limitIp'], 2);
      expect(b.containsKey('trafficReset'), isFalse);
    });

    test('free daily spec', () {
      final b = XuiApi.clientBody(
        email: 'yy-a',
        flow: '',
        defaults: d,
        nowMs: 1000,
        spec: const ServerSpec(mode: 'free', totalBytes: 2 * _gb, reset: 'daily', limitIp: 1),
      );
      expect(b['totalGB'], 2 * _gb);
      expect(b['trafficReset'], 'daily');
      expect(b['reset'], 1);
      expect(b['expiryTime'], 0);
      expect(b['limitIp'], 1);
      expect(b['enable'], isTrue);
    });

    test('gold with absolute expiry; blocked → disabled', () {
      final g = XuiApi.clientBody(
        email: 'yy-a',
        flow: '',
        defaults: d,
        nowMs: 1000,
        spec: const ServerSpec(mode: 'gold', expiryMs: 99999),
      );
      expect(g['expiryTime'], 99999);
      expect(g['totalGB'], 0);
      final x = XuiApi.clientBody(
        email: 'yy-a',
        flow: '',
        defaults: d,
        nowMs: 1000,
        spec: const ServerSpec(mode: 'blocked', enabled: false),
      );
      expect(x['enable'], isFalse);
    });
  });

  group('ads gating by plan', () {
    late Directory tmp;
    setUpAll(() => tmp = Directory.systemTemp.createTempSync('yy_plan_'));
    tearDownAll(() => tmp.deleteSync(recursive: true));

    test('gold → no ads, except reward center when allowed', () async {
      final m = AdsManager(
        kv: MemoryAdKv(),
        appState: () => (serverId: 1, vpnConnected: false, versionCode: 10),
        eventsEndpoint: Uri.parse('http://x/api/v1/ads/events'),
        media: MediaCache(dir: Directory('${tmp.path}/m')..createSync()),
        client: MockClient((r) async => http.Response('{}', 200)),
        random: Random(1),
        clock: () => DateTime.utc(2026, 10, 14, 12).millisecondsSinceEpoch,
        platform: 'android',
        language: 'fa',
        checkConnectivity: () async => [ConnectivityResult.wifi],
        connectivityChanges: const Stream.empty(),
      );
      await m.init();
      m.configure(AdsConfig.fromJson({
        'enabled': true,
        'settings': {'banner_refresh_sec': 0},
        'items': [
          {'id': 1, 'format': 'text', 'placements': ['home_top'], 'headline': 'x'},
        ],
      }));
      expect(m.gateOpen(AdPlacement.homeTop), isTrue);
      m.setPlanPolicy(adFree: true);
      expect(m.gateOpen(AdPlacement.homeTop), isFalse);
      expect(m.pick('home_top'), isNull);
      expect(m.gateOpen(AdPlacement.rewardCenter), isFalse);
      m.setPlanPolicy(adFree: true, rewardCenter: true);
      expect(m.gateOpen(AdPlacement.rewardCenter), isTrue);
      m.setPlanPolicy(adFree: false);
      expect(m.gateOpen(AdPlacement.homeTop), isTrue);
      m.dispose();
    });
  });
}
