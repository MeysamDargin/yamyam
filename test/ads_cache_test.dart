import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yamyam/ads/ad_ledger.dart';
import 'package:yamyam/ads/ads_manager.dart';
import 'package:yamyam/ads/media_cache.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/services/app_exception.dart';
import 'package:yamyam/services/panel_service.dart';
import 'package:yamyam/services/storage_service.dart';
import 'package:yamyam/services/vpn_service.dart';
import 'package:yamyam/state/app_controller.dart';

class _FakePanel extends PanelService {
  Map<String, dynamic>? next; // null → خطای شبکه
  int calls = 0;

  @override
  Future<({String raw, AppConfig config})> fetchConfig() async {
    calls++;
    final n = next;
    if (n == null) throw const AppException('offline');
    final raw = jsonEncode(n);
    return (raw: raw, config: AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>));
  }
}

class _FakeVpn extends VpnService {
  @override
  Future<void> init({required String packageName}) async {}
  @override
  void dispose() {}
}

Map<String, dynamic> _cfg(List<Map<String, dynamic>> items) => {
      'servers': [],
      'ads': {
        'enabled': true,
        'settings': {'banner_refresh_sec': 0},
        'items': items,
      },
    };

Map<String, dynamic> _ad(int id, [String headline = 'x']) => {
      'id': id,
      'format': 'text',
      'placements': ['home_top'],
      'headline': headline,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late StorageService storage;
  late AdsManager ads;
  late _FakePanel panel;
  late AppController c;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'yy',
      packageName: 'com.example.yy',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    tmp = Directory.systemTemp.createTempSync('yy_cache_');
    Hive.init(tmp.path);
    storage = StorageService.forTesting(await Hive.openBox('t'));
    ads = AdsManager(
      kv: MemoryAdKv(),
      appState: () => (serverId: 1, vpnConnected: false, versionCode: 1),
      eventsEndpoint: Uri.parse('http://x/e'),
      media: MediaCache(dir: Directory('${tmp.path}/m')..createSync()),
      client: MockClient((_) async => http.Response('{}', 200)),
      platform: 'android',
      language: 'fa',
      checkConnectivity: () async => [ConnectivityResult.wifi],
      connectivityChanges: const Stream.empty(),
    );
    panel = _FakePanel();
    c = AppController(storage: storage, panel: panel, vpn: _FakeVpn(), ads: ads);
  });

  tearDown(() async {
    ads.dispose();
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  test('ads are never read from the disk cache; offline start shows no ads', () async {
    // کش قدیمی حاوی تبلیغ (مثل نسخه‌ی قبلی اپ) + پنلِ در دسترس نیست
    await storage.saveConfig(jsonEncode(_cfg([_ad(1)])));
    panel.next = null;
    await c.start();
    await c.refreshConfig();
    await c.adsReady.timeout(const Duration(seconds: 2));
    expect(ads.enabled, isFalse);
    expect(ads.config.items, isEmpty);
    expect(ads.pick('home_top'), isNull);
    // سرورها/کانفیگ هنوز از کش می‌آیند
    expect(c.config, isNotNull);
  });

  test('fresh config replaces ads completely; deleted ads disappear; cache has no ads', () async {
    panel.next = _cfg([_ad(1), _ad(2)]);
    await c.start();
    await c.refreshConfig();
    await c.adsReady;
    await Future<void>.delayed(Duration.zero);
    expect(ads.config.items.map((e) => e.id), [1, 2]);
    expect(jsonDecode(storage.cachedConfig!).containsKey('ads'), isFalse);

    // مدیر یکی را حذف می‌کند
    panel.next = _cfg([_ad(2)]);
    await c.refreshConfig();
    await Future<void>.delayed(Duration.zero);
    expect(ads.config.items.map((e) => e.id), [2]);

    // مدیر همه را حذف می‌کند
    panel.next = _cfg([]);
    await c.refreshConfig();
    await Future<void>.delayed(Duration.zero);
    expect(ads.config.items, isEmpty);
    expect(ads.pick('home_top'), isNull);

    // مدیر کلید اصلی را خاموش می‌کند
    panel.next = {'servers': [], 'ads': {'enabled': false, 'items': [_ad(3)]}};
    await c.refreshConfig();
    await Future<void>.delayed(Duration.zero);
    expect(ads.enabled, isFalse);
  });

  test('ensureFreshAds refetches when stale, skips when fresh or ads are off', () async {
    panel.next = _cfg([_ad(1)]);
    await c.start();
    await c.refreshConfig();
    await c.adsReady;
    await Future<void>.delayed(Duration.zero);
    expect(ads.enabled, isTrue);
    final n = panel.calls;

    await c.ensureFreshAds(); // تازه است
    expect(panel.calls, n);

    panel.next = {'servers': []}; // مدیر تبلیغات را خاموش کرده
    await c.ensureFreshAds(maxAge: Duration.zero); // کهنه حساب شود
    await Future<void>.delayed(Duration.zero);
    expect(panel.calls, n + 1);
    expect(ads.enabled, isFalse);

    // تبلیغات خاموش: هیچ درخواستی لازم نیست
    final m = panel.calls;
    await c.ensureFreshAds(maxAge: Duration.zero);
    expect(panel.calls, m);
  });
}
