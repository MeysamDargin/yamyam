/// دفتر محلیِ نمایش‌ها: شمارنده‌های فرکانس، سقف تمام‌صفحه، «بدون تبلیغ»، سکه و جوایز در انتظار.
/// روی دستگاه ذخیره می‌شود (Hive) و هیچ داده‌ی شخصی‌ای به سرور نمی‌رود.
library;

import 'dart:async';
import 'dart:convert';

import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ad_rules.dart';

/// ذخیره‌ی ساده‌ی کلید/مقدار رشته‌ای (در اپ: StorageService، در تست: حافظه).
abstract interface class AdKv {
  String? read(String key);
  Future<void> write(String key, String value);
}

class MemoryAdKv implements AdKv {
  final Map<String, String> map = {};
  @override
  String? read(String key) => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

class PendingReward {
  final String type; // traffic_mb | days
  final double amount;
  const PendingReward(this.type, this.amount);
  Map<String, dynamic> toJson() => {'type': type, 'amount': amount};
}

class AdLedger implements AdCounters {
  AdLedger(this._kv, {int Function()? clock})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const _key = 'ads_ledger';
  final AdKv _kv;
  final int Function() _clock;

  /// اختلاف زمانیِ پنل (برای «امروز»)؛ با هر کانفیگ جدید به‌روز می‌شود.
  int utcOffsetMinutes = 210;

  Map<String, dynamic> _d = {};
  final Map<int, int> _session = {};
  int _fullscreenSession = 0;

  void load() {
    try {
      final raw = _kv.read(_key);
      if (raw != null) _d = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      _d = {};
    }
    if (_i('installed') == 0) {
      _d['installed'] = _clock();
      _save();
    }
  }

  void _save() => unawaited(_kv.write(_key, jsonEncode(_d)));

  int _i(String k) => (_d[k] as num?)?.toInt() ?? 0;

  Map<String, dynamic> get _ads =>
      (_d['ads'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  Map<String, dynamic> _ad(int id) =>
      (_ads['$id'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  /// با عوض شدن روز (به وقت پنل) شمارنده‌های روزانه صفر می‌شوند.
  void _roll() {
    final today = panelClock(_clock(), utcOffsetMinutes).day;
    if (_d['day'] == today) return;
    _d['day'] = today;
    _d['fsToday'] = 0;
    for (final v in _ads.values) {
      if (v is Map) {
        v['d'] = 0;
        v['rd'] = 0;
      }
    }
    _save();
  }

  // ---------- AdCounters ----------
  @override
  int impressionsToday(int adId) {
    _roll();
    return (_ads['$adId']?['d'] as num?)?.toInt() ?? 0;
  }

  @override
  int impressionsTotal(int adId) => (_ads['$adId']?['t'] as num?)?.toInt() ?? 0;

  @override
  int impressionsSession(int adId) => _session[adId] ?? 0;

  @override
  int lastShownMs(int adId) => (_ads['$adId']?['l'] as num?)?.toInt() ?? 0;

  @override
  int rewardsToday(int adId) {
    _roll();
    return (_ads['$adId']?['rd'] as num?)?.toInt() ?? 0;
  }

  // ---------- ثبت ----------
  /// [interruptive]: تمام‌صفحه/پاپ‌آپ (در سقف‌های سراسری شمرده می‌شود)
  void recordImpression(AdItem ad, {required bool interruptive}) {
    _roll();
    final a = _ad(ad.id);
    a['t'] = ((a['t'] as num?)?.toInt() ?? 0) + 1;
    a['d'] = ((a['d'] as num?)?.toInt() ?? 0) + 1;
    a['l'] = _clock();
    _session[ad.id] = (_session[ad.id] ?? 0) + 1;
    if (interruptive) {
      _d['fsToday'] = _i('fsToday') + 1;
      _d['lastFs'] = _clock();
      _fullscreenSession++;
    }
    _save();
  }

  void recordReward(AdItem ad) {
    _roll();
    final a = _ad(ad.id);
    a['rd'] = ((a['rd'] as num?)?.toInt() ?? 0) + 1;
    _save();
  }

  // ---------- سقف‌های سراسری ----------
  int get interruptiveToday {
    _roll();
    return _i('fsToday');
  }

  int get interruptiveSession => _fullscreenSession;
  int get lastInterruptiveMs => _i('lastFs');

  int get lastAppOpenMs => _i('lastAppOpen');
  void markAppOpenShown() {
    _d['lastAppOpen'] = _clock();
    _save();
  }

  int get installedAtMs => _i('installed');

  // ---------- تعداد اتصال (برای «هر N بار») ----------
  int noteConnectAttempt() {
    _d['connects'] = _i('connects') + 1;
    _save();
    return _i('connects');
  }

  // ---------- بدون تبلیغ ----------
  int get noAdsUntilMs => _i('noAdsUntil');
  bool get noAdsActive => noAdsUntilMs > _clock();

  void grantNoAds(int minutes) {
    final base = noAdsUntilMs > _clock() ? noAdsUntilMs : _clock();
    _d['noAdsUntil'] = base + minutes * Duration.millisecondsPerMinute;
    _save();
  }

  // ---------- سکه ----------
  int get coins => _i('coins');
  void addCoins(int n) {
    _d['coins'] = coins + n;
    _save();
  }

  // ---------- جوایز در انتظار (حجم/روز که باید روی 3X-UI اعمال شوند) ----------
  List<PendingReward> get pending {
    final raw = _d['pending'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map)
          PendingReward('${e['type']}', (e['amount'] as num?)?.toDouble() ?? 0),
    ];
  }

  void addPending(PendingReward r) {
    _d['pending'] = [...pending, r].map((e) => e.toJson()).toList();
    _save();
  }

  void setPending(List<PendingReward> list) {
    _d['pending'] = list.map((e) => e.toJson()).toList();
    _save();
  }
}
