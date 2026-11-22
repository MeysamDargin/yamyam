/// مدیر تبلیغات: نگه‌داری کانفیگ پنل، انتخاب تبلیغ (Waterfall + هدف‌گیری + فرکانس)،
/// ثبت و ارسال دسته‌ایِ آمار، کش/پیش‌بارگذاری رسانه و رعایت صرفه‌جویی در اینترنت.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yamyam/ads/ad_events.dart';
import 'package:yamyam/ads/ad_ledger.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ad_rules.dart';
import 'package:yamyam/ads/media_cache.dart';
import 'package:yamyam/ads/network_adapters.dart';

/// وضعیتی که مدیر تبلیغات از اپ می‌خواهد (سرور انتخاب‌شده، وضعیت VPN، نسخه).
typedef AdAppState = ({int? serverId, bool vpnConnected, int versionCode});

/// برنامه‌ی تبلیغ پیش از اتصال VPN
class PreConnectPlan {
  final AdItem ad;
  final String mode; // skippable | must_watch | timed
  final int skipAfterSec;
  final int maxWaitSec;
  final bool connectInBackground;
  const PreConnectPlan({
    required this.ad,
    required this.mode,
    required this.skipAfterSec,
    required this.maxWaitSec,
    required this.connectInBackground,
  });
}

class AdsManager extends ChangeNotifier {
  AdsManager({
    required AdKv kv,
    required this.appState,
    required Uri eventsEndpoint,
    MediaCache? media,
    http.Client? client,
    Random? random,
    int Function()? clock,
    String? platform,
    String? language,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  })  : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _rnd = random ?? Random(),
        _client = client ?? http.Client(),
        _platform = platform ?? (Platform.isIOS ? 'ios' : 'android'),
        _language = language,
        _checkConn = checkConnectivity ?? (() => Connectivity().checkConnectivity()),
        _connChanges = connectivityChanges,
        media = media ?? MediaCache() {
    ledger = AdLedger(kv, clock: _clock);
    _events = AdEventQueue(kv, endpoint: eventsEndpoint, client: _client);
  }

  final AdAppState Function() appState;
  final MediaCache media;
  final http.Client _client;
  final Random _rnd;
  final int Function() _clock;
  final String _platform;
  final String? _language;
  final Future<List<ConnectivityResult>> Function() _checkConn;
  final Stream<List<ConnectivityResult>>? _connChanges;

  late final AdLedger ledger;
  late final AdEventQueue _events;

  AdsConfig config = AdsConfig.off;
  AdsSettings get settings => config.settings;
  bool get enabled => config.enabled;

  bool _wifi = false;
  bool get onWifi => _wifi;
  bool _foreground = true;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _flushTimer;
  Timer? _preloadTimer;
  bool _preloading = false;
  bool _disposed = false;

  /// یک تمام‌صفحه/پاپ‌آپ در حال نمایش است؟ (هم‌پوشانی جلوگیری می‌شود)
  bool interruptiveActive = false;

  // ---------- سیاست پلن (کاربر طلایی) ----------
  bool _planAdFree = false;
  bool _planRewardCenter = false;

  /// کاربر طلایی: همه‌ی جایگاه‌های تبلیغاتی بسته است (جز مرکز جایزه اگر مدیر خواسته).
  bool get planAdFree => _planAdFree;

  void setPlanPolicy({required bool adFree, bool rewardCenter = false}) {
    if (_planAdFree == adFree && _planRewardCenter == rewardCenter) return;
    _planAdFree = adFree;
    _planRewardCenter = rewardCenter;
    changed();
  }

  bool _suppressAppOpen = false;
  final Map<int, int> _failedAt = {};

  // ===================================================================== //
  // lifecycle
  // ===================================================================== //
  Future<void> init() async {
    ledger.load();
    _events.load();
    try {
      await media.init();
    } catch (e) {
      debugPrint('ads media init failed: $e');
    }
    try {
      _applyConn(await _checkConn());
    } catch (_) {}
    try {
      _connSub = (_connChanges ?? Connectivity().onConnectivityChanged).listen(_onConn);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
    _flushTimer?.cancel();
    _preloadTimer?.cancel();
    media.dispose();
    _events.dispose();
    _client.close();
    super.dispose();
  }

  void _onConn(List<ConnectivityResult> r) {
    final was = _wifi;
    _applyConn(r);
    if (_wifi && !was) _schedulePreload();
  }

  /// Wi‑Fi/اترنت = true، اینترنت همراه = false. اگر فقط «vpn» گزارش شد (نوع زیرین
  /// معلوم نیست) آخرین وضعیتِ شناخته‌شده حفظ می‌شود.
  void _applyConn(List<ConnectivityResult> r) {
    if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) {
      _wifi = true;
    } else if (r.contains(ConnectivityResult.mobile)) {
      _wifi = false;
    }
  }

  /// تغییر وضعیت درونی (مثلاً «بدون تبلیغ» فعال شد) تا اسلات‌ها خودشان را بروز کنند.
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void setForeground(bool v) {
    if (_foreground == v) return;
    _foreground = v;
    if (!v) unawaited(flushEvents());
  }

  /// کانفیگ تازه‌ی پنل
  void configure(AdsConfig c) {
    config = c;
    ledger.utcOffsetMinutes = c.settings.utcOffsetMinutes;
    _flushTimer?.cancel();
    if (c.enabled) {
      _flushTimer = Timer.periodic(Duration(seconds: c.settings.eventsFlushSec), (_) {
        if (_foreground) unawaited(flushEvents());
      });
      unawaited(_initNetworks(c));
    }
    _schedulePreload();
    notifyListeners();
  }

  Future<void> _initNetworks(AdsConfig c) async {
    for (final e in c.networks.entries) {
      final a = AdNetworks.of(e.key);
      if (a == null) continue;
      try {
        await a.initialize(e.value, testMode: c.settings.testMode);
      } catch (err) {
        debugPrint('ad network ${e.key} init failed: $err');
      }
    }
  }

  // ===================================================================== //
  // محیط و دروازه‌های سراسری
  // ===================================================================== //
  AdEnv env() {
    final s = appState();
    return AdEnv(
      nowMs: _clock(),
      platform: _platform,
      versionCode: s.versionCode,
      serverId: s.serverId,
      language: _language ?? ui.PlatformDispatcher.instance.locale.languageCode,
      onWifi: _wifi,
      vpnConnected: s.vpnConnected,
      installedAtMs: ledger.installedAtMs,
    );
  }

  /// قواعد سراسری (مستقل از تبلیغ): کلید اصلی، جایگاه خاموش، دوره‌ی آرامش بعد از نصب،
  /// «بدون تبلیغ»، سقف روزانه/نشست، فاصله‌ی تمام‌صفحه‌ها و کول‌داون App Open.
  bool gateOpen(String placement) {
    final s = settings;
    if (!config.enabled || s.disabledPlacements.contains(placement)) return false;
    if (_planAdFree) return placement == AdPlacement.rewardCenter && _planRewardCenter;
    if (placement == AdPlacement.rewardCenter) return true; // انتخاب خودِ کاربر
    final now = _clock();
    if (s.graceMinutesAfterInstall > 0 &&
        now - ledger.installedAtMs < s.graceMinutesAfterInstall * Duration.millisecondsPerMinute) {
      return false;
    }
    final keepForNoAds =
        placement == AdPlacement.preConnect && !s.preConnectSkipForRewardedUsers;
    if (ledger.noAdsActive && !keepForNoAds) return false;

    if (AdPlacement.interruptive.contains(placement)) {
      if (interruptiveActive) return false;
      if (s.maxAdsPerDay > 0 && ledger.interruptiveToday >= s.maxAdsPerDay) return false;
      if (placement != AdPlacement.preConnect) {
        final last = ledger.lastInterruptiveMs;
        if (s.minGapFullscreenSec > 0 &&
            last > 0 &&
            now - last < s.minGapFullscreenSec * 1000) {
          return false;
        }
        if (s.maxFullscreenPerSession > 0 &&
            ledger.interruptiveSession >= s.maxFullscreenPerSession) {
          return false;
        }
      }
      if (placement == AdPlacement.appOpen) {
        final last = ledger.lastAppOpenMs;
        if (last > 0 && now - last < s.appOpenCooldownSec * 1000) return false;
      }
    }
    return true;
  }

  // ===================================================================== //
  // انتخاب تبلیغ
  // ===================================================================== //
  bool mediaReady(AdItem a) {
    if (a.isNetwork) return true;
    if (a.isImage || a.isVideo) return media.has(a.mediaUrl);
    return true;
  }

  /// شناسه‌ی واحد تبلیغاتی یک تبلیغِ شبکه‌ای (null = نامشخص)
  String? unitIdFor(AdItem a) {
    if (!a.isNetwork) return null;
    final c = config.networks[a.network];
    String? v;
    if (settings.testMode) v = c?.testUnits[a.format];
    if (v == null || v.isEmpty) v = a.networkUnitId;
    if (v.isEmpty) v = c?.units[a.format];
    return (v == null || v.isEmpty) ? null : v;
  }

  /// بهترین تبلیغ برای [placement] یا null.
  ///
  /// منابع به ترتیب Waterfall پنل بررسی می‌شوند؛ داخل هر منبع: اولویت و بعد وزن.
  /// [requireCached]: فقط تبلیغ‌هایی که رسانه‌شان از قبل روی دستگاه است (برای لحظه‌های
  /// حساس به تأخیر مثل اسپلش). موارد ناقص در پس‌زمینه گرم می‌شوند.
  /// [preferCached]: داخل همان اولویت، تبلیغ آماده را ترجیح بده.
  AdItem? pick(
    String placement, {
    Set<String>? formats,
    Set<int> exclude = const {},
    bool requireCached = false,
    bool preferCached = false,
  }) {
    if (!gateOpen(placement)) return null;
    final e = env();
    for (final src in config.waterfall) {
      final cands = <AdItem>[];
      for (final a in config.items) {
        if (formats != null && !formats.contains(a.format)) continue;
        if (exclude.contains(a.id) || _recentlyFailed(a.id)) continue;
        final fromThisSource = src == 'custom' ? !a.isNetwork : (a.isNetwork && a.network == src);
        if (!fromThisSource) continue;
        if (a.isNetwork && (!AdNetworks.canServe(a) || unitIdFor(a) == null)) continue;
        if (!AdRules.eligible(a, placement, e, settings, ledger, isCached: media.has)) continue;
        if (requireCached && !mediaReady(a)) {
          unawaited(ensureMedia(a));
          continue;
        }
        cands.add(a);
      }
      final p = AdRules.weightedPick(cands, _rnd, prefer: preferCached ? mediaReady : null);
      if (p != null) return p;
    }
    return null;
  }

  /// چند تبلیغِ متفاوت (مثلاً برای قرار دادن در لیست سرورها).
  List<AdItem> pickMany(String placement, {Set<String>? formats, int max = 2}) {
    final out = <AdItem>[];
    for (var i = 0; i < max; i++) {
      final a = pick(placement, formats: formats, exclude: {for (final x in out) x.id});
      if (a == null) break;
      out.add(a);
    }
    return out;
  }

  bool available(String placement, {Set<String>? formats}) =>
      pick(placement, formats: formats) != null;

  bool _recentlyFailed(int id) {
    final t = _failedAt[id];
    if (t == null) return false;
    if (_clock() - t > 10 * Duration.millisecondsPerMinute) {
      _failedAt.remove(id);
      return false;
    }
    return true;
  }

  /// تبلیغ بالا نیامد (خطای رسانه/SDK) → ۱۰ دقیقه کنار گذاشته می‌شود.
  void markFailed(AdItem a, String placement) {
    _failedAt[a.id] = _clock();
    recordEvent(a, 'error', placement);
  }

  // ===================================================================== //
  // رسانه
  // ===================================================================== //
  /// روی اینترنت همراه سقف حجم دارد؛ روی Wi‑Fi فقط سقف مطلق.
  int? _capFor() => _wifi ? null : settings.maxMediaMbCellular * 1024 * 1024;

  /// فایل رسانه را از کش می‌دهد یا (با رعایت سقف) دانلود می‌کند.
  Future<File?> loadMedia(String url) => media.ensure(url, maxBytes: _capFor());

  /// رسانه‌ی اصلی (ضروری) و فرعی‌ها (پوستر/آیکون، در حد تلاش)
  Future<bool> ensureMedia(AdItem a) async {
    if (a.isNetwork || a.isHtml) return true;
    final futures = <Future<File?>>[
      for (final u in a.mediaUrls) if (!media.has(u)) loadMedia(u),
    ];
    if (futures.isNotEmpty) await Future.wait(futures);
    return mediaReady(a);
  }

  void _schedulePreload() {
    _preloadTimer?.cancel();
    // با تأخیر تا با درخواست‌های شروع اپ رقابت نکند
    _preloadTimer = Timer(const Duration(seconds: 5), () => unawaited(_preload()));
  }

  Future<void> _preload() async {
    if (_preloading || _disposed) return;
    _preloading = true;
    try {
      if (!config.enabled) {
        await media.prune(const {});
        return;
      }
      await media.prune({for (final a in config.items) ...a.mediaUrls});
      if (!settings.preloadMedia || !_wifi) return;
      final v = appState().versionCode;
      final list = config.items.where((a) {
        if (a.isNetwork || a.isHtml) return false;
        if (!a.platforms.contains(_platform)) return false;
        if (a.maxVersionCode > 0 && v > a.maxVersionCode) return false;
        if (a.minVersionCode > 0 && v < a.minVersionCode) return false;
        return true;
      }).toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));
      for (final a in list) {
        if (_disposed || !_wifi) return;
        await ensureMedia(a);
      }
    } finally {
      _preloading = false;
    }
  }

  // ===================================================================== //
  // ثبت آمار
  // ===================================================================== //
  bool _isInterruptive(String placement) => AdPlacement.interruptive.contains(placement);

  void recordImpression(AdItem ad, String placement) {
    ledger.recordImpression(ad, interruptive: _isInterruptive(placement));
    _events.add(ad.id, 'impression', placement);
    if (ad.impressionPixelUrl.isNotEmpty) unawaited(firePixel(_client, ad.impressionPixelUrl));
    _flushIfBig();
  }

  /// start | complete | skip | close | click | reward | error
  void recordEvent(AdItem ad, String event, String placement) {
    _events.add(ad.id, event, placement);
    if (event == 'click' && ad.clickPixelUrl.isNotEmpty) {
      unawaited(firePixel(_client, ad.clickPixelUrl));
    }
    _flushIfBig();
  }

  void recordClick(AdItem ad, String placement) {
    markExternalLaunch();
    recordEvent(ad, 'click', placement);
  }

  void recordReward(AdItem ad, String placement) {
    ledger.recordReward(ad);
    recordEvent(ad, 'reward', placement);
  }

  void _flushIfBig() {
    if (_events.pending >= 60) unawaited(flushEvents());
  }

  Future<void> flushEvents() => _events.flush();

  @visibleForTesting
  int get pendingEvents => _events.pending;

  // ===================================================================== //
  // App Open
  // ===================================================================== //
  /// قبل از باز کردن مرورگر/شیت مجوز صدا بزن؛ برگشت بعدی به اپ «App Open» حساب نمی‌شود.
  void markExternalLaunch() => _suppressAppOpen = true;

  /// آیا برگشت از پس‌زمینه باید تبلیغ App Open داشته باشد؟
  bool shouldShowAppOpen(Duration pausedFor) {
    if (_suppressAppOpen) {
      _suppressAppOpen = false;
      return false;
    }
    return pausedFor >= const Duration(seconds: 3);
  }

  // ===================================================================== //
  // قبل از اتصال VPN
  // ===================================================================== //
  static const preConnectFormats = {
    AdFormat.preConnect,
    AdFormat.interstitial,
    AdFormat.rewardedVideo,
    AdFormat.rewardedInterstitial,
  };

  /// هر بار که کاربر دکمه‌ی اتصال را می‌زند صدا زده می‌شود (شمارنده‌ی «هر N بار» را هم جلو می‌برد).
  PreConnectPlan? planPreConnect({Set<int> exclude = const {}, bool countAttempt = true}) {
    final s = settings;
    final n = countAttempt ? ledger.noteConnectAttempt() : 0;
    if (!config.enabled || !s.preConnectEnabled) {
      debugPrint('ads: pre-connect skipped — '
          '${!config.enabled ? "ads master switch is OFF" : "pre_connect_enabled is OFF in panel settings"}');
      return null;
    }
    if (countAttempt && (n - 1) % s.preConnectEveryNConnects != 0) {
      debugPrint('ads: pre-connect skipped — every ${s.preConnectEveryNConnects} connects (attempt $n)');
      return null;
    }
    final ad = pick(
      AdPlacement.preConnect,
      formats: preConnectFormats,
      exclude: exclude,
      preferCached: true,
    );
    if (ad == null) {
      debugPrint('ads: pre-connect skipped — no eligible ad '
          '(gate=${gateOpen(AdPlacement.preConnect)}, items=${config.items.length})');
      return null;
    }
    return planFor(ad);
  }

  PreConnectPlan planFor(AdItem ad) {
    final s = settings;
    final own = ad.format == AdFormat.preConnect && ad.waitMode != 'inherit';
    final mode = ad.format != AdFormat.preConnect
        ? (ad.isRewarded ? 'must_watch' : (ad.skippable ? 'skippable' : 'must_watch'))
        : (own ? ad.waitMode : s.preConnectMode);
    final skip = own ? ad.skipAfterSec : s.preConnectSkipAfterSec;
    final bg = switch (ad.connectInBackground) {
      'yes' => true,
      'no' => false,
      _ => s.preConnectConnectInBackground,
    };
    return PreConnectPlan(
      ad: ad,
      mode: mode,
      skipAfterSec: skip,
      // «اگر تبلیغ آماده نشد → اتصال ممنوع» فقط وقتی معنا دارد که اتصال بعد از تبلیغ شروع شود
      connectInBackground: s.fallback == 'block' ? false : bg,
      maxWaitSec: ad.isRewarded ? max(s.preConnectMaxWaitSec, 120) : s.preConnectMaxWaitSec,
    );
  }
}
