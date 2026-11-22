import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yamyam/ads/ad_ledger.dart';
import 'package:yamyam/ads/ad_flow.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ads_manager.dart';
import 'package:yamyam/ads/media_cache.dart';
import 'package:yamyam/ads/widgets/ad_slot.dart';
import 'package:yamyam/ads/widgets/fullscreen_ad.dart' show AdRunResult;
import 'package:yamyam/services/storage_service.dart';
import 'package:yamyam/state/app_controller.dart';
import 'package:yamyam/state/app_scope.dart';

Map<String, dynamic> _ad(int id, String format, String placement, [Map<String, dynamic> x = const {}]) => {
      'id': id,
      'format': format,
      'placements': [placement],
      'headline': 'عنوان $id',
      'body': 'متن $id',
      'cta_text': 'باز کن',
      'click_action': 'none',
      ...x,
    };

void main() {
  late Directory tmp;
  late AdsManager ads;
  late AppController controller;

  Future<void> setup(WidgetTester t, Map<String, dynamic> cfg) async {
    await t.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('yy_adw_');
      Hive.init(tmp.path);
      final box = await Hive.openBox('t');
      final storage = StorageService.forTesting(box);
      ads = AdsManager(
        kv: MemoryAdKv(),
        appState: () => (serverId: 1, vpnConnected: false, versionCode: 1),
        eventsEndpoint: Uri.parse('http://x/api/v1/ads/events'),
        media: MediaCache(dir: Directory('${tmp.path}/media')..createSync()),
        client: MockClient((_) async => http.Response('{}', 200)),
        platform: 'android',
        language: 'fa',
        checkConnectivity: () async => [ConnectivityResult.wifi],
        connectivityChanges: const Stream.empty(),
      );
      await ads.init();
      ads.configure(AdsConfig.fromJson(cfg));
      controller = AppController(storage: storage, ads: ads);
    });
  }

  tearDown(() async {
    ads.dispose();
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  // مثل main.dart: AppScope بالای MaterialApp (مسیرهای تمام‌صفحه هم به آن دسترسی دارند)
  Widget host(Widget body) => AppScope(
        controller: controller,
        child: MaterialApp(home: Scaffold(body: body)),
      );

  testWidgets('slots live inside IntrinsicHeight + Column + Spacer (home layout) without errors',
      (t) async {
    await setup(t, {
      'enabled': true,
      'settings': {'banner_refresh_sec': 0},
      'items': [
        _ad(1, 'text', 'home_top'),
        _ad(2, 'native', 'home_middle'),
        _ad(3, 'html', 'home_bottom', {
          'media_type': 'html',
          'html': '<b>x</b>',
        }),
      ],
    });
    await t.pumpWidget(host(
      SizedBox(
        height: 700,
        child: IntrinsicHeight(
          child: Column(
            children: const [
              AdSlot(placement: AdPlacement.homeTop),
              Spacer(),
              AdSlot(placement: AdPlacement.homeMiddle, padding: EdgeInsets.all(8)),
            ],
          ),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400));

    expect(t.takeException(), isNull);
    expect(find.textContaining('عنوان 1'), findsOneWidget);
    expect(find.textContaining('عنوان 2'), findsOneWidget);
    // نمایش‌ها شمرده شد (یک‌بار برای هر اسلات)
    expect(ads.ledger.impressionsToday(1), 1);
    expect(ads.ledger.impressionsToday(2), 1);
    expect(ads.pendingEvents, 2);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('tapping counts a click; empty placement takes no space', (t) async {
    await setup(t, {
      'enabled': true,
      'settings': {'banner_refresh_sec': 0},
      'items': [
        _ad(1, 'text', 'home_top', {'click_action': 'open_url', 'click_url': 'https://example.com'}),
      ],
    });
    await t.pumpWidget(host(
      const Column(children: [
        AdSlot(placement: AdPlacement.homeTop),
        AdSlot(placement: AdPlacement.settings, key: Key('empty')),
      ]),
    ));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.getSize(find.byKey(const Key('empty'))), Size.zero);

    await t.tap(find.textContaining('عنوان 1'));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    // impression + click
    expect(ads.pendingEvents, 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('"no ads" reward hides slots live', (t) async {
    await setup(t, {
      'enabled': true,
      'settings': {'banner_refresh_sec': 0},
      'items': [_ad(1, 'text', 'home_top')],
    });
    await t.pumpWidget(host(const Column(children: [AdSlot(placement: AdPlacement.homeTop)])));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('عنوان 1'), findsOneWidget);

    ads.ledger.grantNoAds(30);
    ads.changed();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('عنوان 1'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('fullscreen ad without usable media fails fast and is sidelined (waterfall continues)',
      (t) async {
    await setup(t, {
      'enabled': true,
      'items': [
        _ad(1, 'interstitial', 'launch_popup', {'priority': 5}),
        _ad(2, 'text', 'home_top'),
      ],
    });
    late BuildContext ctx;
    await t.pumpWidget(host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));

    AdRunResult? res;
    unawaited(AdFlow.present(ctx, ads, ads.config.items.first, 'launch_popup').then((r) => res = r));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(res, isNotNull);
    expect(res!.failed, isTrue);
    expect(res!.shown, isFalse);
    expect(ads.interruptiveActive, isFalse);
    // تبلیغ خراب ۱۰ دقیقه کنار گذاشته می‌شود
    expect(ads.pick('launch_popup', formats: {'interstitial'}), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('config update (new ad) shows up in an empty slot', (t) async {
    await setup(t, {'enabled': true, 'settings': {'banner_refresh_sec': 0}, 'items': []});
    await t.pumpWidget(host(const Column(children: [AdSlot(placement: AdPlacement.homeTop)])));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('عنوان 5'), findsNothing);

    await t.runAsync(() async {
      ads.configure(AdsConfig.fromJson({
        'enabled': true,
        'settings': {'banner_refresh_sec': 0},
        'items': [_ad(5, 'text', 'home_top')],
      }));
    });
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('عنوان 5'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
