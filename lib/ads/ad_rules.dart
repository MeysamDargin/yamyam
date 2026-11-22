/// منطق خالصِ انتخاب تبلیغ: هدف‌گیری، زمان‌بندی، فرکانس و انتخاب وزنی.
/// بدون وابستگی به UI/شبکه تا کاملاً قابل تست باشد.
library;

import 'dart:math';

import 'package:yamyam/ads/ad_models.dart';

/// وضعیت لحظه‌ای کاربر/دستگاه
class AdEnv {
  final int nowMs;
  final String platform; // android | ios
  final int versionCode;
  final int? serverId;
  final String language; // کد زبان دستگاه (fa, en, ...)
  final bool onWifi;
  final bool vpnConnected;
  final int installedAtMs;

  const AdEnv({
    required this.nowMs,
    this.platform = 'android',
    this.versionCode = 0,
    this.serverId,
    this.language = 'fa',
    this.onWifi = true,
    this.vpnConnected = false,
    required this.installedAtMs,
  });
}

/// شمارنده‌هایی که قواعد فرکانس لازم دارند (پیاده‌سازی: [AdLedger]).
abstract interface class AdCounters {
  int impressionsToday(int adId);
  int impressionsTotal(int adId);
  int impressionsSession(int adId);
  int lastShownMs(int adId); // ۰ = هرگز
  int rewardsToday(int adId);
}

/// تاریخ/ساعت به وقت پنل (offset دقیقه نسبت به UTC)
({int weekday, int hour, String day}) panelClock(int nowMs, int offsetMinutes) {
  final t = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true)
      .add(Duration(minutes: offsetMinutes));
  String two(int n) => n.toString().padLeft(2, '0');
  return (
    // Dart: Mon=1…Sun=7 → پنل: شنبه=۰ … جمعه=۶
    weekday: (t.weekday + 1) % 7,
    hour: t.hour,
    day: '${t.year}-${two(t.month)}-${two(t.day)}',
  );
}

abstract final class AdRules {
  /// آیا [a] برای نمایش در [placement] مجاز است؟ (هدف‌گیری + زمان + فرکانس + مصرف داده)
  static bool eligible(
    AdItem a,
    String placement,
    AdEnv env,
    AdsSettings s,
    AdCounters counters, {
    bool Function(String url)? isCached,
  }) {
    if (!a.hasPlacement(placement) || s.disabledPlacements.contains(placement)) {
      return false;
    }

    // --- زمان‌بندی
    final nowSec = env.nowMs ~/ 1000;
    if (a.startTs != null && nowSec < a.startTs!) return false;
    if (a.endTs != null && nowSec >= a.endTs!) return false;
    final clock = panelClock(env.nowMs, s.utcOffsetMinutes);
    if (a.daysOfWeek.isNotEmpty && !a.daysOfWeek.contains(clock.weekday)) {
      return false;
    }
    if (clock.hour < a.hourFrom || clock.hour >= a.hourTo) return false;

    // --- هدف‌گیری
    if (a.platforms.isNotEmpty && !a.platforms.contains(env.platform)) return false;
    if (a.minVersionCode > 0 && env.versionCode < a.minVersionCode) return false;
    if (a.maxVersionCode > 0 && env.versionCode > a.maxVersionCode) return false;
    if (a.serverIds.isNotEmpty &&
        (env.serverId == null || !a.serverIds.contains(env.serverId))) {
      return false;
    }
    if (a.userType != 'all') {
      final ageMs = env.nowMs - env.installedAtMs;
      final isNew = ageMs < a.newUserDays * Duration.millisecondsPerDay;
      if (a.userType == 'new' && !isNew) return false;
      if (a.userType == 'returning' && isNew) return false;
    }
    if (a.languages.isNotEmpty) {
      final mine = env.language.toLowerCase();
      final ok = a.languages.any((l) => l.split(RegExp(r'[-_]')).first == mine);
      if (!ok) return false;
    }
    if (a.wifiOnly && !env.onWifi) return false;
    if (a.connectionState == 'connected' && !env.vpnConnected) return false;
    if (a.connectionState == 'disconnected' && env.vpnConnected) return false;

    // --- فرکانس
    if (a.freqPerSession > 0 && counters.impressionsSession(a.id) >= a.freqPerSession) {
      return false;
    }
    if (a.freqPerDay > 0 && counters.impressionsToday(a.id) >= a.freqPerDay) {
      return false;
    }
    if (a.freqTotal > 0 && counters.impressionsTotal(a.id) >= a.freqTotal) {
      return false;
    }
    if (a.minIntervalSec > 0) {
      final last = counters.lastShownMs(a.id);
      if (last > 0 && env.nowMs - last < a.minIntervalSec * 1000) return false;
    }
    if (a.hasReward &&
        a.rewardDailyLimit > 0 &&
        counters.rewardsToday(a.id) >= a.rewardDailyLimit) {
      return false;
    }

    // --- صرفه‌جویی در اینترنت کاربر
    if (!dataAllows(a, env, s, isCached)) return false;
    return true;
  }

  /// ویدیو روی اینترنت همراه (وقتی تنظیم «فقط Wi‑Fi» روشن است) فقط اگر از قبل در کش باشد.
  static bool dataAllows(
    AdItem a,
    AdEnv env,
    AdsSettings s,
    bool Function(String url)? isCached,
  ) {
    if (a.isNetwork) return true; // مصرف شبکه‌ی SDK را خود SDK مدیریت می‌کند
    if (a.isVideo && !env.onWifi && s.videoWifiOnly) {
      return isCached != null && isCached(a.mediaUrl);
    }
    return true;
  }

  /// بین هم‌اولویت‌ها (بالاترین اولویت) به‌صورت وزنی یکی را انتخاب می‌کند.
  /// [prefer]: اگر داخل همان گروهِ اولویت، تبلیغ مطلوب (مثلاً رسانه‌ی کش‌شده) هست فقط از آن‌ها انتخاب شود
  /// (اولویت هیچ‌وقت نادیده گرفته نمی‌شود).
  static AdItem? weightedPick(
    List<AdItem> list,
    Random rnd, {
    bool Function(AdItem)? prefer,
  }) {
    if (list.isEmpty) return null;
    var top = list.first.priority;
    for (final a in list) {
      if (a.priority > top) top = a.priority;
    }
    var group = list.where((a) => a.priority == top).toList();
    if (prefer != null) {
      final liked = group.where(prefer).toList();
      if (liked.isNotEmpty) group = liked;
    }
    final total = group.fold<int>(0, (n, a) => n + a.weight);
    var r = rnd.nextInt(total);
    for (final a in group) {
      if (r < a.weight) return a;
      r -= a.weight;
    }
    return group.last;
  }
}
