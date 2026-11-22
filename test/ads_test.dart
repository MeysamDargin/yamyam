import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yamyam/ads/ad_events.dart';
import 'package:yamyam/ads/ad_ledger.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ad_rules.dart';
import 'package:yamyam/ads/ads_manager.dart';
import 'package:yamyam/ads/media_cache.dart';
import 'package:yamyam/ads/network_adapters.dart';

// 2026-10-14 (چهارشنبه) 12:00 UTC = 15:30 به وقت ایران
final _t0 = DateTime.utc(2026, 10, 14, 12).millisecondsSinceEpoch;
const _day = Duration.millisecondsPerDay;

Map<String, dynamic> raw(
  int id,
  String format,
  List<String> placements, [
  Map<String, dynamic> extra = const {},
]) =>
    {'id': id, 'format': format, 'placements': placements, ...extra};

AdItem item(
  int id,
  String format,
  List<String> placements, [
  Map<String, dynamic> extra = const {},
]) =>
    AdItem.fromJson(raw(id, format, placements, extra));

class _Counters implements AdCounters {
  final today = <int, int>{};
  final total = <int, int>{};
  final session = <int, int>{};
  final last = <int, int>{};
  final rewards = <int, int>{};
  @override
  int impressionsToday(int id) => today[id] ?? 0;
  @override
  int impressionsTotal(int id) => total[id] ?? 0;
  @override
  int impressionsSession(int id) => session[id] ?? 0;
  @override
  int lastShownMs(int id) => last[id] ?? 0;
  @override
  int rewardsToday(int id) => rewards[id] ?? 0;
}

class _FakeAdapter extends AdNetworkAdapter {
  @override
  String get id => 'admob';
  @override
  bool get available => true;
  @override
  Future<void> initialize(NetworkCreds creds, {required bool testMode}) async {}
  @override
  Widget? buildInline(BuildContext context, AdItem ad, String unitId,
          {required VoidCallback onLoaded,
          required VoidCallback onFailed,
          required VoidCallback onClick}) =>
      const SizedBox();
  @override
  Future<NetworkShowResult> showFullscreen(
          BuildContext context, AdItem ad, String unitId) async =>
      const NetworkShowResult(shown: true, completed: true);
}

void main() {
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('yy_ads_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  // ===================================================================== //
  group('parse', () {
    test('disabled / missing block → off', () {
      expect(AdsConfig.fromJson(null).enabled, isFalse);
      expect(AdsConfig.fromJson({'enabled': false, 'items': [raw(1, 'text', ['home_top'])]}).items,
          isEmpty);
    });

    test('full panel payload', () {
      final cfg = AdsConfig.fromJson({
        'enabled': true,
        'settings': {
          'min_gap_fullscreen_sec': 60,
          'pre_connect_enabled': true,
          'pre_connect_mode': 'must_watch',
          'fallback': 'block',
          'disabled_placements': ['floating'],
          'utc_offset_minutes': 210,
          'ad_label': 'اسپانسر',
        },
        'waterfall': ['admob', 'custom'],
        'networks': {
          'admob': {
            'app_id': 'ca-app-pub-1',
            'units': {'interstitial': 'u1'},
            'test_units': {'interstitial': 't1'},
          },
        },
        'items': [
          raw(1, 'banner', ['home_top'], {
            'media_type': 'image',
            'media_url': 'https://p/a.png',
            'weight': 500, // خارج از بازه → ۱۰۰
            'days_of_week': [0, 1],
            'start_ts': 1760000000,
            'hour_from': 8,
            'hour_to': 22,
          }),
          raw(2, 'rewarded_video', ['reward_center'], {
            'reward_type': 'traffic_mb',
            'reward_amount': 300,
            'reward_daily_limit': 3,
          }),
          {'id': 3, 'format': '', 'placements': ['x']}, // نامعتبر
          'garbage',
        ],
      });
      expect(cfg.enabled, isTrue);
      expect(cfg.items.map((e) => e.id), [1, 2]);
      expect(cfg.waterfall, ['admob', 'custom']);
      expect(cfg.settings.fallback, 'block');
      expect(cfg.settings.preConnectMode, 'must_watch');
      expect(cfg.settings.disabledPlacements, {'floating'});
      expect(cfg.settings.adLabel, 'اسپانسر');
      expect(cfg.settings.minGapFullscreenSec, 60);
      expect(cfg.networks['admob']!.units['interstitial'], 'u1');
      final a = cfg.items.first;
      expect(a.weight, 100);
      expect(a.isImage, isTrue);
      expect(a.daysOfWeek, [0, 1]);
      expect(a.startTs, 1760000000);
      expect(a.hourFrom, 8);
      expect(a.hourTo, 22);
      final r = cfg.items.last;
      expect(r.hasReward, isTrue);
      expect(r.rewardAmount, 300);
    });

    test('bad enum values fall back to defaults', () {
      final s = AdsSettings.fromJson({'pre_connect_mode': 'nope', 'fallback': 'x'});
      expect(s.preConnectMode, 'skippable');
      expect(s.fallback, 'connect_anyway');
    });
  });

  // ===================================================================== //
  group('rules', () {
    const s = AdsSettings();
    final env = AdEnv(nowMs: _t0, serverId: 7, versionCode: 20, installedAtMs: _t0 - 30 * _day);

    test('panel clock: Persian weekday + crossing midnight', () {
      final c = panelClock(_t0, 210);
      expect(c.weekday, 4); // شنبه=۰ … چهارشنبه=۴
      expect(c.hour, 15);
      expect(c.day, '2026-10-14');
      // 21:00 UTC = 00:30 فردا (پنجشنبه)
      final n = panelClock(DateTime.utc(2026, 10, 14, 21).millisecondsSinceEpoch, 210);
      expect(n.weekday, 5);
      expect(n.hour, 0);
      expect(n.day, '2026-10-15');
      // شنبه و جمعه
      expect(panelClock(DateTime.utc(2026, 10, 17, 12).millisecondsSinceEpoch, 210).weekday, 0);
      expect(panelClock(DateTime.utc(2026, 10, 16, 12).millisecondsSinceEpoch, 210).weekday, 6);
    });

    bool ok(AdItem a, {AdEnv? e, AdsSettings st = s, _Counters? c, String p = 'home_top'}) =>
        AdRules.eligible(a, p, e ?? env, st, c ?? _Counters());

    test('placement + disabled placements', () {
      final a = item(1, 'text', ['home_top']);
      expect(ok(a), isTrue);
      expect(ok(a, p: 'home_bottom'), isFalse);
      expect(ok(a, st: const AdsSettings(disabledPlacements: {'home_top'})), isFalse);
    });

    test('schedule: start/end, weekday, hour window (panel time)', () {
      final nowSec = _t0 ~/ 1000;
      expect(ok(item(1, 'text', ['home_top'], {'start_ts': nowSec + 60})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'start_ts': nowSec - 60})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'end_ts': nowSec})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'end_ts': nowSec + 1})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'days_of_week': [4]})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'days_of_week': [0, 1, 2, 3, 5, 6]})), isFalse);
      // ساعت پنل ۱۵ است (نه ۱۲ UTC)
      expect(ok(item(1, 'text', ['home_top'], {'hour_from': 15, 'hour_to': 16})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'hour_from': 9, 'hour_to': 12})), isFalse);
    });

    test('targeting: platform, version, server, user type, language', () {
      expect(ok(item(1, 'text', ['home_top'], {'platforms': ['ios']})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'platforms': ['android']})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'min_version_code': 21})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'min_version_code': 20})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'max_version_code': 19})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'server_ids': [7, 8]})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'server_ids': [8]})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'server_ids': [7]}), e: AdEnv(nowMs: _t0, installedAtMs: 0)),
          isFalse); // سروری انتخاب نشده
      // نصب ۳۰ روز پیش
      expect(ok(item(1, 'text', ['home_top'], {'user_type': 'new', 'new_user_days': 7})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'user_type': 'returning', 'new_user_days': 7})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'user_type': 'new', 'new_user_days': 60})), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'languages': ['en']})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'languages': ['en', 'fa-IR']})), isTrue);
    });

    test('connection state + wifi only', () {
      final conn = AdEnv(nowMs: _t0, installedAtMs: 0, vpnConnected: true);
      final cell = AdEnv(nowMs: _t0, installedAtMs: 0, onWifi: false);
      expect(ok(item(1, 'text', ['home_top'], {'connection_state': 'connected'}), e: conn), isTrue);
      expect(ok(item(1, 'text', ['home_top'], {'connection_state': 'connected'})), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'connection_state': 'disconnected'}), e: conn), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'wifi_only': true}), e: cell), isFalse);
      expect(ok(item(1, 'text', ['home_top'], {'wifi_only': true})), isTrue);
    });

    test('frequency caps, min interval, reward daily limit', () {
      final c = _Counters();
      final a = item(1, 'text', ['home_top'], {
        'freq_per_session': 2,
        'freq_per_day': 3,
        'freq_total': 10,
        'min_interval_sec': 60,
      });
      expect(ok(a, c: c), isTrue);
      c.session[1] = 2;
      expect(ok(a, c: c), isFalse);
      c.session[1] = 0;
      c.today[1] = 3;
      expect(ok(a, c: c), isFalse);
      c.today[1] = 0;
      c.total[1] = 10;
      expect(ok(a, c: c), isFalse);
      c.total[1] = 0;
      c.last[1] = _t0 - 30 * 1000;
      expect(ok(a, c: c), isFalse);
      c.last[1] = _t0 - 61 * 1000;
      expect(ok(a, c: c), isTrue);

      final r = item(2, 'rewarded_video', ['reward_center'], {
        'reward_type': 'days',
        'reward_amount': 1,
        'reward_daily_limit': 2,
      });
      c.rewards[2] = 2;
      expect(ok(r, c: c, p: 'reward_center'), isFalse);
      c.rewards[2] = 1;
      expect(ok(r, c: c, p: 'reward_center'), isTrue);
    });

    test('data saving: video on cellular only when cached', () {
      final v = item(1, 'video_banner', ['home_top'], {
        'media_type': 'video',
        'media_url': 'https://p/v.mp4',
      });
      final cell = AdEnv(nowMs: _t0, installedAtMs: 0, onWifi: false);
      expect(AdRules.eligible(v, 'home_top', cell, s, _Counters()), isFalse);
      expect(AdRules.eligible(v, 'home_top', cell, s, _Counters(), isCached: (_) => true), isTrue);
      expect(
          AdRules.eligible(v, 'home_top', cell, const AdsSettings(videoWifiOnly: false), _Counters()),
          isTrue);
      expect(AdRules.eligible(v, 'home_top', env, s, _Counters()), isTrue); // Wi‑Fi
    });

    test('weighted pick: priority first, then weight; prefer inside top group', () {
      final lo = item(1, 'text', ['home_top'], {'priority': 1, 'weight': 100});
      final a = item(2, 'text', ['home_top'], {'priority': 5, 'weight': 90});
      final b = item(3, 'text', ['home_top'], {'priority': 5, 'weight': 10});
      final rnd = Random(42);
      final hits = <int, int>{1: 0, 2: 0, 3: 0};
      for (var i = 0; i < 4000; i++) {
        final id = AdRules.weightedPick([lo, a, b], rnd)!.id;
        hits[id] = hits[id]! + 1;
      }
      expect(hits[1], 0); // اولویت پایین هرگز
      expect(hits[2]! / (hits[2]! + hits[3]!), closeTo(0.9, 0.04));
      // prefer: فقط b ترجیح داده می‌شود ولی lo با اولویت پایین‌تر هیچ‌وقت نه
      for (var i = 0; i < 50; i++) {
        expect(AdRules.weightedPick([lo, a, b], rnd, prefer: (x) => x.id == 3)!.id, 3);
        expect(AdRules.weightedPick([lo, a, b], rnd, prefer: (x) => x.id == 1)!.priority, 5);
      }
      expect(AdRules.weightedPick(const [], rnd), isNull);
    });
  });

  // ===================================================================== //
  group('ledger', () {
    test('counters, day roll (panel time), persistence', () {
      var now = _t0;
      final kv = MemoryAdKv();
      final l = AdLedger(kv, clock: () => now)..load();
      final a = item(1, 'text', ['home_top']);
      l.recordImpression(a, interruptive: false);
      l.recordImpression(a, interruptive: true);
      expect(l.impressionsToday(1), 2);
      expect(l.impressionsTotal(1), 2);
      expect(l.impressionsSession(1), 2);
      expect(l.interruptiveToday, 1);
      expect(l.interruptiveSession, 1);
      expect(l.lastShownMs(1), now);

      // ساعت ۲۱ UTC = نیمه‌شب ایران → روز عوض می‌شود
      now = DateTime.utc(2026, 10, 14, 21).millisecondsSinceEpoch;
      expect(l.impressionsToday(1), 0);
      expect(l.interruptiveToday, 0);
      expect(l.impressionsTotal(1), 2);
      expect(l.impressionsSession(1), 2);

      // با آفست دیگر همان لحظه هنوز «امروز» است
      final l2 = AdLedger(kv, clock: () => now)
        ..utcOffsetMinutes = 0
        ..load();
      expect(l2.impressionsTotal(1), 2); // از ذخیره‌سازی خوانده شد
    });

    test('no-ads, coins, pending rewards, reward counters', () {
      var now = _t0;
      final l = AdLedger(MemoryAdKv(), clock: () => now)..load();
      expect(l.noAdsActive, isFalse);
      l.grantNoAds(30);
      expect(l.noAdsActive, isTrue);
      l.grantNoAds(30); // تمدید روی باقی‌مانده
      expect(l.noAdsUntilMs, _t0 + 60 * Duration.millisecondsPerMinute);
      now += 61 * Duration.millisecondsPerMinute;
      expect(l.noAdsActive, isFalse);

      l.addCoins(5);
      l.addCoins(2);
      expect(l.coins, 7);

      l.addPending(const PendingReward('traffic_mb', 100));
      l.addPending(const PendingReward('days', 1));
      expect(l.pending.map((e) => e.type), ['traffic_mb', 'days']);
      l.setPending([l.pending.last]);
      expect(l.pending.single.type, 'days');

      final r = item(9, 'rewarded_video', ['reward_center']);
      l.recordReward(r);
      expect(l.rewardsToday(9), 1);
    });

    test('connect attempt counter', () {
      final l = AdLedger(MemoryAdKv())..load();
      expect(l.noteConnectAttempt(), 1);
      expect(l.noteConnectAttempt(), 2);
    });
  });

  // ===================================================================== //
  group('events', () {
    test('batches by key, chunks counts, keeps queue on failure, drops on 422', () async {
      final kv = MemoryAdKv();
      final bodies = <Map<String, dynamic>>[];
      var status = 500;
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{}', status);
      });
      final q = AdEventQueue(kv, endpoint: Uri.parse('http://x/api/v1/ads/events'), client: client);
      for (var i = 0; i < 3; i++) {
        q.add(1, 'impression', 'home_top');
      }
      q.add(1, 'click', 'home_top');
      for (var i = 0; i < 250; i++) {
        q.add(2, 'impression', 'splash');
      }
      expect(q.pending, 3);

      expect(await q.flush(), isFalse); // ۵۰۰ → صف حفظ
      expect(q.pending, 3);

      status = 200;
      expect(await q.flush(), isTrue);
      expect(q.pending, 0);
      final events = (bodies.last['events'] as List).cast<Map<String, dynamic>>();
      int sum(int id, String ev) => events
          .where((e) => e['ad_id'] == id && e['event'] == ev)
          .fold(0, (n, e) => n + (e['count'] as int));
      expect(sum(1, 'impression'), 3);
      expect(sum(1, 'click'), 1);
      expect(sum(2, 'impression'), 250);
      expect(events.every((e) => (e['count'] as int) <= 100), isTrue);

      // پایدار: صف جدید از همان ذخیره‌سازی
      q.add(5, 'impression', 'settings');
      final q2 = AdEventQueue(kv, endpoint: Uri.parse('http://x/e'), client: client)..load();
      expect(q2.pending, 1);

      status = 422;
      expect(await q.flush(), isTrue);
      expect(q.pending, 0);
    });
  });

  // ===================================================================== //
  group('media cache', () {
    test('nameFor is stable and keeps a sane extension', () {
      final a = MediaCache.nameFor('https://p/x/a.png?v=1');
      expect(a, MediaCache.nameFor('https://p/x/a.png?v=1'));
      expect(a, endsWith('.png'));
      expect(a, isNot(MediaCache.nameFor('https://p/x/b.png')));
      expect(MediaCache.nameFor('https://p/x/noext'), endsWith('.bin'));
    });

    test('downloads once, dedupes in-flight, persists, enforces cap', () async {
      final dir = Directory('${tmp.path}/media')..createSync();
      var requests = 0;
      final client = MockClient((req) async {
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response.bytes(List.filled(10, 7), 200);
      });
      final c = MediaCache(client: client, dir: dir);
      await c.init();
      expect(c.has('https://p/a.png'), isFalse);
      final r = await Future.wait([c.ensure('https://p/a.png'), c.ensure('https://p/a.png')]);
      expect(requests, 1);
      expect(r.first!.lengthSync(), 10);
      expect(c.has('https://p/a.png'), isTrue);
      await c.ensure('https://p/a.png');
      expect(requests, 1);

      // بعد از «ری‌استارت» هنوز در کش است
      final c2 = MediaCache(client: client, dir: dir);
      await c2.init();
      expect(c2.has('https://p/a.png'), isTrue);

      // بزرگ‌تر از سقف: رد می‌شود و چیزی روی دیسک نمی‌ماند
      expect(await c2.ensure('https://p/big.png', maxBytes: 5), isNull);
      expect(c2.has('https://p/big.png'), isFalse);
      expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);

      // prune: آدرس‌هایی که دیگر در کانفیگ نیستند پاک می‌شوند
      await c2.prune({'https://p/other.png'});
      expect(c2.has('https://p/a.png'), isFalse);
    });

    test('http error → null', () async {
      final dir = Directory('${tmp.path}/media2')..createSync();
      final c = MediaCache(client: MockClient((_) async => http.Response('no', 404)), dir: dir);
      await c.init();
      expect(await c.ensure('https://p/a.png'), isNull);
    });
  });

  // ===================================================================== //
  group('manager', () {
    var now = _t0;
    final made = <AdsManager>[];

    Future<AdsManager> mk(Map<String, dynamic> cfg, {List<http.Request>? sent}) async {
      final m = AdsManager(
        kv: MemoryAdKv(),
        appState: () => (serverId: 1, vpnConnected: false, versionCode: 10),
        eventsEndpoint: Uri.parse('http://x/api/v1/ads/events'),
        media: MediaCache(dir: Directory('${tmp.path}/m${made.length}')..createSync()),
        client: MockClient((r) async {
          sent?.add(r);
          return http.Response('{}', 200);
        }),
        random: Random(1),
        clock: () => now,
        platform: 'android',
        language: 'fa',
        checkConnectivity: () async => [ConnectivityResult.wifi],
        connectivityChanges: const Stream.empty(),
      );
      made.add(m);
      await m.init();
      m.configure(AdsConfig.fromJson(cfg));
      return m;
    }

    setUp(() => now = _t0);
    tearDown(() {
      for (final m in made) {
        m.dispose();
      }
      made.clear();
      AdNetworks.unregister('admob');
    });

    test('master switch off → nothing', () async {
      final m = await mk({'enabled': false});
      expect(m.enabled, isFalse);
      expect(m.pick('home_top'), isNull);
    });

    test('frequency cap per day blocks, then resets next (panel) day', () async {
      final m = await mk({
        'enabled': true,
        'items': [raw(1, 'text', ['home_top'], {'freq_per_day': 2})],
      });
      for (var i = 0; i < 2; i++) {
        final a = m.pick('home_top')!;
        m.recordImpression(a, 'home_top');
      }
      expect(m.pick('home_top'), isNull);
      now += _day;
      expect(m.pick('home_top')?.id, 1);
    });

    test('waterfall: unregistered network is skipped → custom; registered network wins', () async {
      final cfg = {
        'enabled': true,
        'waterfall': ['admob', 'custom'],
        'networks': {
          'admob': {'units': {'banner': 'unit-1'}},
        },
        'items': [
          raw(1, 'banner', ['home_top'], {'source': 'network', 'network': 'admob', 'priority': 9}),
          raw(2, 'text', ['home_top']),
        ],
      };
      var m = await mk(cfg);
      expect(m.pick('home_top')?.id, 2);

      AdNetworks.register(_FakeAdapter());
      m = await mk(cfg);
      expect(m.pick('home_top')?.id, 1);
      expect(m.unitIdFor(m.config.items.first), 'unit-1');
      // با formats غیرمرتبط: تبلیغ شبکه نباید برگردد
      expect(m.pick('home_top', formats: {'text'})?.id, 2);
    });

    test('test mode prefers test unit ids', () async {
      AdNetworks.register(_FakeAdapter());
      final m = await mk({
        'enabled': true,
        'settings': {'test_mode': true},
        'waterfall': ['admob'],
        'networks': {
          'admob': {
            'units': {'banner': 'real'},
            'test_units': {'banner': 'test'},
          },
        },
        'items': [raw(1, 'banner', ['home_top'], {'source': 'network', 'network': 'admob'})],
      });
      expect(m.unitIdFor(m.config.items.first), 'test');
    });

    test('global gates: grace, disabled placement, no-ads, fullscreen gap/session/day', () async {
      final m = await mk({
        'enabled': true,
        'settings': {
          'grace_minutes_after_install': 10,
          'min_gap_fullscreen_sec': 120,
          'max_fullscreen_per_session': 2,
          'max_ads_per_day': 3,
          'disabled_placements': ['floating'],
        },
        'items': [
          raw(1, 'interstitial', ['post_connect']),
          raw(2, 'text', ['home_top']),
          raw(3, 'rewarded_video', ['reward_center'], {
            'reward_type': 'days',
            'reward_amount': 1,
          }),
        ],
      });
      // دوره‌ی آرامش بعد از نصب
      expect(m.gateOpen('home_top'), isFalse);
      expect(m.gateOpen('reward_center'), isTrue); // انتخاب خود کاربر
      now += 11 * Duration.millisecondsPerMinute;
      expect(m.gateOpen('home_top'), isTrue);
      expect(m.gateOpen('floating'), isFalse);

      // تمام‌صفحه: فاصله‌ی بین دو نمایش
      final a = m.pick('post_connect')!;
      m.recordImpression(a, 'post_connect');
      expect(m.gateOpen('post_connect'), isFalse);
      now += 121 * 1000;
      expect(m.gateOpen('post_connect'), isTrue);
      m.recordImpression(a, 'post_connect');
      now += 121 * 1000;
      expect(m.gateOpen('post_connect'), isFalse); // سقف نشست (۲)

      // هم‌پوشانی
      m.interruptiveActive = true;
      expect(m.gateOpen('launch_popup'), isFalse);
      m.interruptiveActive = false;

      // بدون تبلیغ
      m.ledger.grantNoAds(30);
      expect(m.gateOpen('home_top'), isFalse);
      expect(m.pick('home_top'), isNull);
      expect(m.gateOpen('reward_center'), isTrue);
    });

    test('app open cooldown', () async {
      final m = await mk({
        'enabled': true,
        'settings': {'app_open_cooldown_sec': 240, 'min_gap_fullscreen_sec': 0},
        'items': [raw(1, 'app_open', ['app_open'])],
      });
      expect(m.gateOpen('app_open'), isTrue);
      m.ledger.markAppOpenShown();
      expect(m.gateOpen('app_open'), isFalse);
      now += 241 * 1000;
      expect(m.gateOpen('app_open'), isTrue);

      // برگشت کوتاه از پس‌زمینه یا بازگشت از مرورگر = App Open نیست
      expect(m.shouldShowAppOpen(const Duration(seconds: 1)), isFalse);
      expect(m.shouldShowAppOpen(const Duration(seconds: 30)), isTrue);
      m.markExternalLaunch();
      expect(m.shouldShowAppOpen(const Duration(seconds: 30)), isFalse);
      expect(m.shouldShowAppOpen(const Duration(seconds: 30)), isTrue);
    });

    test('pre-connect plan: every N, modes, fallback=block, rewarded', () async {
      final m = await mk({
        'enabled': true,
        'settings': {
          'pre_connect_enabled': true,
          'pre_connect_every_n_connects': 2,
          'pre_connect_mode': 'timed',
          'pre_connect_skip_after_sec': 4,
          'pre_connect_max_wait_sec': 9,
          'pre_connect_connect_in_background': true,
        },
        'items': [raw(1, 'pre_connect', ['pre_connect'])],
      });
      final p1 = m.planPreConnect();
      expect(p1, isNotNull); // اتصال ۱
      expect(p1!.mode, 'timed');
      expect(p1.skipAfterSec, 4);
      expect(p1.maxWaitSec, 9);
      expect(p1.connectInBackground, isTrue);
      expect(m.planPreConnect(), isNull); // اتصال ۲
      expect(m.planPreConnect(), isNotNull); // اتصال ۳

      // تنظیم اختصاصی خود تبلیغ
      final own = item(2, 'pre_connect', ['pre_connect'], {
        'wait_mode': 'must_watch',
        'skip_after_sec': 7,
        'connect_in_background': 'no',
      });
      final po = m.planFor(own);
      expect(po.mode, 'must_watch');
      expect(po.skipAfterSec, 7);
      expect(po.connectInBackground, isFalse);

      // جایزه‌دار: باید کامل دیده شود و زمان انتظار بلندتر
      final rw = item(3, 'rewarded_video', ['pre_connect']);
      final pr = m.planFor(rw);
      expect(pr.mode, 'must_watch');
      expect(pr.maxWaitSec, greaterThanOrEqualTo(120));

      // fallback=block: اتصال بعد از تبلیغ شروع می‌شود، نه هم‌زمان
      final b = await mk({
        'enabled': true,
        'settings': {'pre_connect_enabled': true, 'fallback': 'block'},
        'items': [raw(1, 'pre_connect', ['pre_connect'])],
      });
      expect(b.planPreConnect()!.connectInBackground, isFalse);
    });

    test('pre-connect disabled → no plan', () async {
      final m = await mk({
        'enabled': true,
        'items': [raw(1, 'pre_connect', ['pre_connect'])],
      });
      expect(m.planPreConnect(), isNull);
    });

    test('events are batched and flushed in one request', () async {
      final sent = <http.Request>[];
      final m = await mk({
        'enabled': true,
        'items': [raw(1, 'text', ['home_top'], {'impression_pixel_url': ''})],
      }, sent: sent);
      final a = m.config.items.first;
      m.recordImpression(a, 'home_top');
      m.recordImpression(a, 'home_top');
      m.recordClick(a, 'home_top');
      expect(m.pendingEvents, 2);
      expect(sent, isEmpty);
      await m.flushEvents();
      expect(sent, hasLength(1));
      expect(sent.single.url.path, '/api/v1/ads/events');
      final ev = (jsonDecode(sent.single.body)['events'] as List).cast<Map<String, dynamic>>();
      expect(ev.firstWhere((e) => e['event'] == 'impression')['count'], 2);
      expect(ev.firstWhere((e) => e['event'] == 'click')['count'], 1);
      expect(m.pendingEvents, 0);
    });

    test('markFailed sidelines an ad for 10 minutes', () async {
      final m = await mk({
        'enabled': true,
        'items': [
          raw(1, 'text', ['home_top'], {'priority': 2}),
          raw(2, 'text', ['home_top']),
        ],
      });
      expect(m.pick('home_top')!.id, 1);
      m.markFailed(m.config.items.first, 'home_top');
      expect(m.pick('home_top')!.id, 2);
      now += 11 * Duration.millisecondsPerMinute;
      expect(m.pick('home_top')!.id, 1);
    });

    test('requireCached skips ads whose media is not on device', () async {
      final m = await mk({
        'enabled': true,
        'items': [
          raw(1, 'splash', ['splash'], {'media_type': 'image', 'media_url': 'http://127.0.0.1:1/a.png'}),
        ],
      });
      expect(m.pick('splash', requireCached: true), isNull);
      expect(m.pick('splash')?.id, 1);
    });

    test('pickMany returns distinct ads', () async {
      final m = await mk({
        'enabled': true,
        'items': [
          raw(1, 'sponsored_server', ['server_list_inline']),
          raw(2, 'sponsored_server', ['server_list_inline']),
          raw(3, 'sponsored_server', ['server_list_inline']),
        ],
      });
      final l = m.pickMany('server_list_inline', max: 2);
      expect(l, hasLength(2));
      expect(l.first.id, isNot(l.last.id));
    });
  });
}
