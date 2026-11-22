import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart'
    show VlessConnectionState, VlessStatus;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yamyam/ads/ad_ledger.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ad_text.dart';
import 'package:yamyam/ads/ads_manager.dart';
import 'package:yamyam/api/api.dart';
import 'package:yamyam/api/endpoint.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/models/client_account.dart';
import 'package:yamyam/models/client_stats.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/models/vpn_status.dart';
import 'package:yamyam/platform/client_id.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/services/app_exception.dart';
import 'package:yamyam/services/panel_service.dart';
import 'package:yamyam/services/storage_service.dart';
import 'package:yamyam/services/vpn_service.dart';
import 'package:yamyam/services/xui_service.dart';

enum ConfigStatus { loading, ready, error }

class _Cancelled implements Exception {
  const _Cancelled();
}

/// مغز اپ: کانفیگ پنل، سرورها، کلاینت‌ها، اتصال VPN و مصرف.
class AppController extends ChangeNotifier {
  AppController({
    required this.storage,
    PanelService? panel,
    VpnService? vpn,
    AdsManager? ads,
  })  : _panel = panel ?? PanelService(),
        _vpn = vpn ?? VpnService(),
        _adsOverride = ads;

  final StorageService storage;
  final PanelService _panel;
  final VpnService _vpn;
  final AdsManager? _adsOverride;

  /// سیستم تبلیغات (کانفیگ از پنل، انتخاب، آمار، کش رسانه)
  late final AdsManager ads = _adsOverride ??
      AdsManager(
        kv: storage,
        appState: () => (
          serverId: _selectedServerId,
          vpnConnected: vpnStatus == VpnStatus.connected,
          versionCode: buildNumber,
        ),
        eventsEndpoint: buildApiUri(apiServerBaseUrl, Endpoint.panelAdsEvents),
      );
  Future<void> _adsInit = Future.value();
  final Completer<void> _adsReady = Completer<void>();

  /// آماده شدن تبلیغات (دفتر محلی + کانفیگ کش‌شده اعمال شد)؛ اسپلش برای تبلیغ خودش منتظر این می‌ماند.
  Future<void> get adsReady => _adsReady.future;

  // ---------- اطلاعات اپ ----------
  String versionName = '';
  int buildNumber = 0;

  // ---------- کانفیگ پنل ----------
  AppConfig? config;
  ConfigStatus configStatus = ConfigStatus.loading;
  String? configError;
  bool configFromCache = false;
  Future<void>? _refreshing;

  // ---------- سرور / کلاینت ----------
  int? _selectedServerId;
  int? _provisioningServerId;
  ClientStats? _stats;
  String? statsError;

  // ---------- مصرف همین نشست (بایت) ----------
  // از شمارنده‌های هسته؛ هیچ ترافیک اضافه‌ای ایجاد نمی‌کند.
  int? sessionBytes;

  /// زمان برقراری اتصال فعلی (برای نمایش مدت اتصال)
  DateTime? connectedAt;

  /// اپ جلوی چشم کاربر است؟ (پولینگ فقط در این حالت)
  bool appInForeground = true;

  // ---------- سرعت لحظه‌ای (بایت بر ثانیه) ----------
  // از شمارنده‌های «تجمعی» هسته و زمان واقعی بین دو نمونه محاسبه می‌شود؛
  // مقدار آماده‌ی افزونه، فاصله‌ی زمانی نامنظم بین نمونه‌ها را در نظر نمی‌گیرد.
  double downBps = 0;
  double upBps = 0;
  int _lastUp = 0;
  int _lastDown = 0;
  DateTime? _lastSample;

  // ---------- VPN ----------
  VpnStatus vpnStatus = VpnStatus.disconnected;
  VlessStatus? vlessStatus;
  Completer<void>? _connectWaiter;
  bool _sawPluginConnecting = false;
  bool _cancelled = false;

  StreamSubscription<VlessStatus>? _statusSub;
  Timer? _timer;
  final _notices = StreamController<String>.broadcast();

  /// پیام‌های کوتاه برای نمایش (SnackBar).
  Stream<String> get notices => _notices.stream;

  // ===================================================================== //
  // lifecycle
  // ===================================================================== //
  Future<void>? _started;

  /// یک‌بار راه‌اندازی (idempotent). چندبار صدا زدنش مشکلی ندارد.
  Future<void> start() => _started ??= _init();

  Future<void> _init() async {
    // سیستم تبلیغات (فقط خواندن‌های محلی؛ سریع)
    _adsInit = ads.init();

    final info = await PackageInfo.fromPlatform();
    versionName = info.version;
    buildNumber = int.tryParse(info.buildNumber) ?? 0;

    _selectedServerId = storage.selectedServerId;

    final cached = storage.cachedConfig;
    if (cached != null) {
      try {
        config = AppConfig.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        configFromCache = true;
        configStatus = ConfigStatus.ready;
      } catch (_) {}
    }

    _loadCachedPlan();

    // شبکه را همین حالا و موازی با راه‌اندازی VPN شروع کن (نه بعد از آن):
    //  - آمار اشتراک با سرور/توکنِ کش‌شده فوراً گرفته می‌شود و منتظر کانفیگ پنل نمی‌ماند؛
    //  - کانفیگ تازه‌ی پنل هم موازی می‌آید.
    if (config != null) unawaited(refreshStats());
    _startUsagePoll();
    unawaited(refreshConfig());

    // تبلیغات عمداً از کش خوانده نمی‌شوند: فقط از آخرین پاسخِ «تازه»ی پنل (همین نشست) اعمال
    // می‌شوند تا تبلیغِ حذف/غیرفعال‌شده در پنل هرگز نمایش داده نشود. (سرورها از کش می‌آیند)

    _statusSub = _vpn.statusStream.listen(_onVlessStatus);
    try {
      await _vpn.init(packageName: info.packageName);
    } catch (e) {
      debugPrint('VPN init failed: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _planTimer?.cancel();
    _statusSub?.cancel();
    _notices.close();
    _vpn.dispose();
    ads.dispose();
    super.dispose();
  }

  void _notice(String m) {
    if (m.isNotEmpty && !_notices.isClosed) _notices.add(m);
  }

  /// پیام کوتاه برای کاربر (SnackBar) از بیرون کنترلر
  void announce(String m) => _notice(m);

  /// کانفیگ تبلیغات بعد از آماده شدن init تبلیغات اعمال می‌شود.
  Future<void> _applyAds(AppConfig c) {
    final cfg = c.ads;
    return _adsInit.then((_) {
      ads.configure(cfg);
      // اگر جوایز حجم/روز در انتظار بود و حالا اکانت داریم
      if (ads.ledger.pending.isNotEmpty) unawaited(applyPendingRewards());
    });
  }

  void _markAdsReady() {
    if (!_adsReady.isCompleted) _adsReady.complete();
  }

  /// کانفیگ تبلیغات را قبل از یک تصمیم مهم (مثلاً تبلیغ پیش از اتصال) تازه می‌کند؛
  /// فقط اگر از [maxAge] قدیمی‌تر باشد و حداکثر تا [wait] صبر می‌کند (کندی شبکه مانع کار کاربر نشود).
  Future<void> ensureFreshAds({
    Duration maxAge = const Duration(seconds: 45),
    Duration wait = const Duration(seconds: 2),
  }) async {
    if (!ads.enabled) return;
    try {
      await refreshConfigIfStale(maxAge: maxAge).timeout(wait, onTimeout: () {});
    } catch (_) {}
  }

  /// نسخه‌ی بدون بلوک `ads` از پاسخ خام پنل (تبلیغات هرگز روی دیسک کش نمی‌شوند).
  static String _stripAds(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return jsonEncode(m..remove('ads'));
    } catch (_) {}
    return raw;
  }

  // ===================================================================== //
  // config
  // ===================================================================== //
  Future<void> refreshConfig() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  DateTime? _lastConfigAt;

  /// فقط اگر کانفیگ کهنه شده (پیش‌فرض ۱۰ دقیقه) دوباره می‌گیرد؛ برای برگشت به اپ.
  Future<void> refreshConfigIfStale({
    Duration maxAge = const Duration(minutes: 10),
  }) {
    final t = _lastConfigAt;
    if (t != null && DateTime.now().difference(t) < maxAge) {
      return _refreshing ?? Future.value();
    }
    return refreshConfig();
  }

  /// منتظر پایان دریافت کانفیگ (اگر در جریان باشد).
  Future<void> waitForConfig() => _refreshing ?? Future.value();

  Future<void> _doRefresh() async {
    if (config == null) {
      configStatus = ConfigStatus.loading;
      notifyListeners();
    }
    try {
      final r = await _panel.fetchConfig();
      config = r.config;
      configFromCache = false;
      _lastConfigAt = DateTime.now();
      configError = null;
      configStatus = ConfigStatus.ready;
      unawaited(storage.saveConfig(_stripAds(r.raw)));
      // اعمال تبلیغات تازه (جایگزین کامل قبلی؛ حذف‌شده‌ها همین لحظه از اسلات‌ها می‌روند)
      unawaited(_applyAds(r.config).whenComplete(_markAdsReady));
      _reconcileSelection();
      _onConfigForPlans();
      // اگر هنوز آمار نداریم (مثلاً کش خالی بود)، حالا بگیر
      if (_stats == null && _lastStatsAt == null) unawaited(refreshStats());
    } on AppException catch (e) {
      _configFailed(e.message);
      _markAdsReady();
    } catch (_) {
      _configFailed('خطای ناشناخته در دریافت تنظیمات');
      _markAdsReady();
    }
    notifyListeners();
  }

  void _configFailed(String msg) {
    configError = msg;
    configStatus = config != null ? ConfigStatus.ready : ConfigStatus.error;
  }

  /// اگر مدیر سرور انتخاب‌شده را حذف/غیرفعال کرده، انتخاب را پاک کن.
  void _reconcileSelection() {
    final id = _selectedServerId;
    if (id != null &&
        config!.serverById(id) == null &&
        vpnStatus == VpnStatus.disconnected) {
      _selectedServerId = null;
      _stats = null;
      storage.setSelectedServerId(null);
    }
  }

  bool get maintenance => config?.maintenance.enabled ?? false;
  String get maintenanceMessage => config?.maintenance.message ?? '';
  List<VpnServer> get servers => config?.servers ?? const [];

  // ---------- آپدیت و پیام ----------
  UpdateInfo? get update => config?.update;
  bool get updateNeeded => update?.needsUpdate(buildNumber) ?? false;
  bool get updateForced => update?.isForced(buildNumber) ?? false;

  /// آپدیت اختیاری فقط یک‌بار برای هر نسخه نمایش داده می‌شود.
  bool get shouldPromptUpdate =>
      updateNeeded &&
      (updateForced || storage.dismissedUpdateCode != update!.versionCode);

  Future<void> dismissUpdate() async {
    final u = update;
    if (u != null) await storage.setDismissedUpdateCode(u.versionCode);
  }

  PopupMessage? get pendingMessage {
    final m = config?.message;
    if (m == null || (m.title.isEmpty && m.body.isEmpty)) return null;
    return m.id != storage.seenMessageId ? m : null;
  }

  Future<void> markMessageSeen(PopupMessage m) => storage.setSeenMessageId(m.id);

  // ===================================================================== //
  // server selection & client provisioning
  // ===================================================================== //
  VpnServer? get selectedServer => config?.serverById(_selectedServerId);
  bool get hasSelectedServer => selectedServer != null;
  int? get provisioningServerId => _provisioningServerId;
  ClientAccount? get account {
    final s = selectedServer;
    return s == null ? null : storage.account(s.id);
  }

  ClientStats? get stats => _stats;

  // کلاینت HTTP پایدار برای هر سرور (اتصال TLS دوباره استفاده می‌شود)
  final Map<int, XuiApi> _apis = {};

  XuiApi _apiFor(VpnServer s) {
    final cur = _apis[s.id];
    if (cur != null && cur.matches(s)) return cur;
    cur?.close();
    return _apis[s.id] = XuiApi(s);
  }

  /// انتخاب سرور؛ اگر برای این کاربر روی آن سرور کلاینتی نیست، ساخته می‌شود.
  /// در صورت خطا [AppException] پرتاب می‌شود (UI نمایش می‌دهد).
  Future<void> selectServer(VpnServer server) async {
    if (_provisioningServerId != null) return;
    _provisioningServerId = server.id;
    notifyListeners();
    ClientStats? fresh;
    try {
      // پلن کاربر را بدانیم تا روی سرور «فقط طلایی» کلاینتِ بی‌جا ساخته نشود
      await _ensurePlanKnown();
      final spec = specFor(server);
      if (spec != null && spec.blocked) {
        throw AppException(_lockedMessage);
      }
      final (_, s) = await _ensureAccount(server);
      fresh = s;
      if (_selectedServerId != server.id) {
        _stats = null;
        statsError = null;
      }
      _selectedServerId = server.id;
      if (s != null) _setStats(s);
      await storage.setSelectedServerId(server.id);
    } finally {
      _provisioningServerId = null;
      notifyListeners();
    }
    if (fresh == null) unawaited(refreshStats());
  }

  /// شناسه‌ی کلاینت در پنل. گوشی `yy-`، اندروید تی‌وی `yytv-`، ویندوز `yywin-`.
  String get _emailBase {
    final id = storage.deviceId.replaceAll('-', '').substring(0, 10);
    return '${clientIdPrefix()}-$id';
  }

  /// حساب ذخیره‌شده‌ی معتبر (اگر مدیر سرور/اینباند را عوض کرده باشد، پاک می‌شود).
  Future<ClientAccount?> _storedAccount(VpnServer server) async {
    final acc = storage.account(server.id);
    if (acc != null &&
        (acc.baseUrl != server.baseUrl || acc.inboundId != server.inboundId)) {
      await storage.removeAccount(server.id);
      return null;
    }
    return acc;
  }

  /// حساب را تضمین می‌کند. اگر حساب از قبل بود، آمار تازه‌اش هم برمی‌گردد.
  Future<(ClientAccount, ClientStats?)> _ensureAccount(VpnServer server) async {
    if (!server.canManageClients) {
      throw const AppException(
        'مدیر اجازه‌ی ساخت اکانت از طریق اپ را برای این سرور نداده است.',
      );
    }
    final api = _apiFor(server);
    final acc = await _storedAccount(server);

    if (acc != null) {
      try {
        final s = await api.getStats(acc.email);
        if (_selectedServerId == server.id) _setStats(s);
        return (acc, s);
      } on XuiException catch (e) {
        if (!e.apiError) rethrow; // قطعی شبکه/توکن؛ ساخت مجدد معنا ندارد
        await storage.removeAccount(server.id); // مدیر حذفش کرده → دوباره بساز
      }
    }

    final created = await _apiFor(server).createClient(
      email: _emailBase,
      defaults: config?.clientDefaults ?? const ClientDefaults(),
      spec: specFor(server),
    );
    await storage.saveAccount(created);
    // پنل پلن کاربر را روی کلاینتِ تازه می‌نشاند (ریست روزانه، سقف دوره‌ای و ...)
    ClientStats? stats;
    if (plansEnabled) {
      try {
        await refreshPlan(serverIds: [server.id])
            .timeout(const Duration(seconds: 12));
      } catch (_) {}
      try {
        stats = await api.getStats(created.email);
      } catch (_) {}
    }
    return (created, stats);
  }

  // ===================================================================== //
  // پلن رایگان / طلایی
  // ===================================================================== //
  UserPlan _plan = UserPlan.free;
  bool _planKnown = false;
  bool _planPushed = false; // سهمیهٔ این نشست یک‌بار روی کلاینت‌ها نشسته؟
  DateTime? _lastPlanAt;
  Future<void>? _planRun;
  Timer? _planTimer;
  String? planError;

  PlansInfo get plans => config?.plans ?? PlansInfo.off;

  /// سیستم پلن‌ها در پنل روشن است؟ (خاموش = رفتار قبلیِ اپ)
  bool get plansEnabled => plans.enabled;

  /// شناسه‌ی کاربر در پنل (همان ایمیل کلاینت‌ها: `yy-…`، `yytv-…` یا `yywin-…`)
  String get userId => _emailBase;

  UserPlan get plan => _plan;

  bool get isGold =>
      plansEnabled &&
      _plan.gold &&
      (_plan.expiresMs <= 0 || DateTime.now().millisecondsSinceEpoch < _plan.expiresMs);

  /// ظاهر ویژه‌ی کاربر طلایی
  bool get goldTheme => isGold && plans.ui.goldTheme;

  /// روز باقی‌مانده‌ی اشتراک طلایی (از ساعت دستگاه؛ بدون نیاز به شبکه)
  int get goldDaysLeft {
    final e = _plan.expiresAt;
    if (e == null) return 0;
    final d = e.difference(DateTime.now());
    return d.isNegative ? 0 : (d.inMinutes / 1440).ceil();
  }

  bool get goldExpiringSoon =>
      isGold && plans.ui.expiryWarningDays > 0 && goldDaysLeft <= plans.ui.expiryWarningDays;

  /// اشتراک طلایی قبلاً داشته و تمام شده است؟
  bool get goldExpired => plansEnabled && !isGold && _plan.expired;

  /// کارت ترویجی پلن طلایی برای کاربر رایگان
  bool get showUpsell =>
      plansEnabled && !isGold && plans.ui.upsellBanner && plans.canPurchase;

  ServerSpec? specFor(VpnServer s) => plansEnabled ? _plan.servers[s.id] : null;

  /// سرورِ «فقط طلایی» برای این کاربر قفل است؟
  bool isLocked(VpnServer s) => specFor(s)?.blocked ?? false;

  bool get hasOpenOrder => _plan.hasOpenOrder;

  void _loadCachedPlan() {
    final raw = storage.cachedPlan;
    if (raw == null) return;
    try {
      _plan = UserPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _planKnown = true;
      _applyAdsPolicy();
    } catch (_) {}
  }

  void _applyAdsPolicy() {
    final off = isGold && plans.gold.hideAds;
    ads.setPlanPolicy(adFree: off, rewardCenter: plans.gold.showRewardCenter);
  }

  void _onConfigForPlans() {
    if (!plansEnabled) {
      if (_planKnown || _plan.gold) {
        _plan = UserPlan.free;
        _planKnown = false;
        _planPushed = false;
        unawaited(storage.clearCachedPlan());
      }
      _planTimer?.cancel();
      _planTimer = null;
      _applyAdsPolicy();
      return;
    }
    _applyAdsPolicy();
    final t = _lastPlanAt;
    if (t == null || DateTime.now().difference(t) > const Duration(seconds: 60)) {
      unawaited(refreshPlan());
    }
  }

  void _planResumed() {
    if (!plansEnabled) return;
    final t = _lastPlanAt;
    if (t == null || DateTime.now().difference(t) > const Duration(minutes: 2)) {
      unawaited(refreshPlan());
    }
  }

  /// پلن را یک‌بار می‌دانیم (از کش یا شبکه)؛ حداکثر چند ثانیه صبر می‌کند.
  Future<void> _ensurePlanKnown() async {
    if (!plansEnabled || _planKnown) return;
    try {
      await refreshPlan(sync: false).timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  /// وضعیت پلن را از پنل می‌گیرد. [sync] = هم‌زمان پلن را روی کلاینت‌های موجود
  /// (همه‌ی سرورها یا [serverIds]) اعمال می‌کند.
  Future<void> refreshPlan({bool sync = true, List<int>? serverIds}) async {
    final prev = _planRun;
    if (prev != null && serverIds == null) return prev;
    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }
    final run = _doRefreshPlan(sync: sync, serverIds: serverIds);
    _planRun = run;
    try {
      await run;
    } finally {
      if (identical(_planRun, run)) _planRun = null;
    }
  }

  Future<void> _doRefreshPlan({required bool sync, List<int>? serverIds}) async {
    if (!plansEnabled) return;
    try {
      var r = sync
          ? await _panel.syncPlan(userId, serverIds: serverIds, version: buildNumber)
          : await _panel.fetchPlan(userId, version: buildNumber);
      // خرید تازه یا هر تغییر پلن: سهمیه را همین حالا روی کلاینت‌های همین کاربر بنشان.
      // وگرنه اپ همان سقف رایگان قبلی را از XUI نشان می‌دهد، چون نظرسنجیِ سفارش فقط وضعیت را می‌خواند.
      final planChanged =
          _plan.gold != r.plan.gold || (_planKnown && !_sameSpecs(_plan, r.plan));
      // اولین بار در هر اجرا، و هر بار که پلن عوض شد (مثلاً تایید خرید): سهمیه را
      // روی کلاینت‌های همین کاربر بنشان. وگرنه اپ همان سقف رایگان قبلی را نشان می‌دهد.
      if (!sync && (planChanged || !_planPushed)) {
        r = await _panel.syncPlan(userId, serverIds: serverIds, version: buildNumber);
        sync = true;
      }
      if (sync) _planPushed = true;
      planError = null;
      _lastPlanAt = DateTime.now();
      _applyPlan(r.plan, r.raw, refreshQuota: sync || planChanged);
    } on AppException catch (e) {
      planError = e.message;
    } catch (e) {
      planError = 'خطای ناشناخته در دریافت پلن';
      debugPrint('plan refresh error: $e');
    }
    notifyListeners();
  }

  void _applyPlan(UserPlan next, String raw, {bool refreshQuota = false}) {
    final old = _plan;
    final known = _planKnown;
    _plan = next;
    _planKnown = true;
    unawaited(storage.saveCachedPlan(raw));

    // نتیجه‌ی سفارش‌هایی که قبلاً باز بودند
    final oldOpen = {for (final o in old.orders.where((o) => o.open)) o.id};
    for (final o in next.orders) {
      if (!oldOpen.contains(o.id)) continue;
      if (o.approved) {
        final t = plans.payment.approvedText;
        _notice(t.isEmpty ? 'پرداخت تایید شد و پلن طلایی شما فعال است. 🎉' : t);
      } else if (o.status == 'rejected') {
        _notice(o.rejectReason.isEmpty
            ? 'سفارش شما رد شد.'
            : 'سفارش شما رد شد: ${o.rejectReason}');
      }
    }
    if (known && old.gold && !next.gold && next.expired) {
      _notice('اشتراک پلن طلایی شما به پایان رسید.');
    }

    _applyAdsPolicy();
    _managePlanPolling();

    // پلن/سهمیه عوض شده → مصرف و محدودیت‌ها را تازه کن
    final specsChanged = known && !_sameSpecs(old, next);
    if ((refreshQuota || specsChanged || old.gold != next.gold) && selectedServer != null) {
      unawaited(refreshStats());
    }
  }

  static bool _sameSpecs(UserPlan a, UserPlan b) {
    if (a.servers.length != b.servers.length) return false;
    for (final e in a.servers.entries) {
      final o = b.servers[e.key];
      final x = e.value;
      if (o == null ||
          o.mode != x.mode ||
          o.totalBytes != x.totalBytes ||
          o.reset != x.reset ||
          o.enabled != x.enabled ||
          o.capBytes != x.capBytes) {
        return false;
      }
    }
    return true;
  }

  /// تا وقتی سفارش بازی هست، هر ۳۰ ثانیه (فقط در پیش‌زمینه) نتیجه را بپرس.
  void _managePlanPolling() {
    if (_plan.hasOpenOrder && plansEnabled) {
      _planTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
        if (appInForeground) unawaited(refreshPlan(sync: false));
      });
    } else {
      _planTimer?.cancel();
      _planTimer = null;
    }
  }

  // ---------- خرید ----------

  /// ثبت سفارش (+ ارسال تصویر رسید اگر داده شده). اگر سفارش ثبت شد ولی ارسال تصویر
  /// نشد، [uploadError] پر می‌شود و کاربر می‌تواند دوباره بفرستد.
  Future<({PlanOrder order, String? uploadError})> submitOrder({
    required GoldPackage package,
    String trackingCode = '',
    String payerName = '',
    String payerCard = '',
    String note = '',
    Uint8List? receipt,
  }) async {
    final t = await _panel.createOrder(
      uid: userId,
      packageId: package.id,
      trackingCode: trackingCode,
      payerName: payerName,
      payerCard: payerCard,
      note: note,
      version: buildNumber,
    );
    await storage.saveOrderToken(t.order.id, t.token);
    var order = t.order;
    String? uploadError;
    if (receipt != null) {
      try {
        order = await _panel.uploadReceipt(order.id, t.token, receipt);
      } on AppException catch (e) {
        uploadError = e.message;
      }
    }
    await refreshPlan(sync: false);
    return (order: order, uploadError: uploadError);
  }

  /// ارسال (یا جایگزینی) تصویر رسید یک سفارش باز.
  Future<PlanOrder> sendReceipt(PlanOrder order, Uint8List bytes) async {
    final token = storage.orderToken(order.id);
    if (token == null) {
      throw const AppException('این سفارش روی این دستگاه ثبت نشده است.');
    }
    final o = await _panel.uploadReceipt(order.id, token, bytes);
    await refreshPlan(sync: false);
    return o;
  }

  Future<void> cancelOrder(PlanOrder order) async {
    final token = storage.orderToken(order.id);
    if (token == null) {
      throw const AppException('این سفارش روی این دستگاه ثبت نشده است.');
    }
    await _panel.cancelOrder(order.id, token);
    await refreshPlan(sync: false);
  }

  bool canManageOrder(PlanOrder o) => storage.orderToken(o.id) != null;

  // ===================================================================== //
  // stats (مصرف، انقضا، فعال/غیرفعال)
  // ===================================================================== //
  void _setStats(ClientStats s) {
    _stats = s;
    statsError = null;
    _lastStatsAt = DateTime.now();
  }

  DateTime? _lastStatsAt;

  Future<void>? _statsRun;

  /// هم‌زمان فقط یک درخواست آمار در جریان است.
  Future<void> refreshStats() =>
      _statsRun ??= _doRefreshStats().whenComplete(() => _statsRun = null);

  Future<void> _doRefreshStats() async {
    final server = selectedServer;
    if (server == null || !server.canManageClients) return;
    final acc = storage.account(server.id);
    if (acc == null) return;
    try {
      final s = await _apiFor(server).getStats(acc.email);
      if (server.id != _selectedServerId) return;
      _setStats(s);
      if (ads.ledger.pending.isNotEmpty) unawaited(applyPendingRewards());
      if (vpnStatus == VpnStatus.connected && !s.canConnect) {
        _notice(_blockedMessage(s.state));
        await disconnect();
      }
    } on XuiException catch (e) {
      if (server.id != _selectedServerId) return;
      if (e.apiError) {
        _stats = null;
        statsError = 'اکانت شما روی سرور پیدا نشد؛ هنگام اتصال دوباره ساخته می‌شود.';
        await storage.removeAccount(server.id);
        if (vpnStatus == VpnStatus.connected) {
          _notice(statsError!);
          await disconnect();
        }
      } else {
        statsError = e.message; // آمار قبلی حفظ می‌شود
      }
    }
    notifyListeners();
  }

  /// فقط اگر آمار کهنه است (پیش‌فرض ۶۰ ثانیه) دوباره می‌گیرد.
  Future<void> refreshStatsIfStale({
    Duration maxAge = const Duration(seconds: 60),
  }) {
    final t = _lastStatsAt;
    if (t != null && DateTime.now().difference(t) < maxAge) return Future.value();
    return refreshStats();
  }

  String get _lockedMessage => PlanUi.fmt(
      plans.ui.lockedServerText, 'این سرور فقط برای کاربران {plan} است.',
      plan: plans.gold.title.isEmpty ? 'طلایی' : plans.gold.title);

  String _blockedMessage(AccountState s) {
    final server = selectedServer;
    final spec = server == null ? null : specFor(server);
    if (spec != null) {
      switch (s) {
        case AccountState.disabled:
          if (spec.blocked) return _lockedMessage;
          if (spec.capBytes > 0) return 'سقف حجم اشتراک شما تمام شده است.';
        case AccountState.depleted:
          if (spec.dailyReset) {
            return 'سهمیه‌ی امروز شما تمام شد؛ فردا خودکار تمدید می‌شود.';
          }
        case AccountState.expired:
        case AccountState.active:
          break;
      }
    }
    return switch (s) {
      AccountState.disabled => 'اکانت شما توسط مدیر غیرفعال شده است.',
      AccountState.expired => 'مدت اشتراک شما به پایان رسیده است.',
      AccountState.depleted => 'حجم اشتراک شما تمام شده است.',
      AccountState.active => '',
    };
  }

  /// اپ به پس‌زمینه/پیش‌زمینه رفت. در پس‌زمینه هیچ درخواست دوره‌ای انجام نمی‌شود.
  void setForeground(bool v) {
    if (appInForeground == v) return;
    appInForeground = v;
    ads.setForeground(v);
    if (v) {
      unawaited(refreshStatsIfStale());
      _planResumed();
      _startUsagePoll();
    } else {
      _stopPolling();
    }
  }

  /// هر یک دقیقه سهمیه‌ی واقعی (مصرف‌شده و باقی‌مانده) از ۳X-UI خوانده می‌شود،
  /// وصل یا قطع. فقط وقتی اپ جلو است؛ در پس‌زمینه تایمر خاموش می‌شود.
  static const _pollEvery = Duration(minutes: 1);

  void _startUsagePoll() {
    if (!appInForeground || _timer != null) return;
    _timer = Timer.periodic(_pollEvery, (_) {
      if (appInForeground) unawaited(refreshStats());
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  // ===================================================================== //
  // connection
  // ===================================================================== //
  void _setVpn(VpnStatus s) {
    if (vpnStatus == s) return;
    vpnStatus = s;
    if (s != VpnStatus.connected) _resetSpeed();
    _startUsagePoll();
    notifyListeners();
  }

  void _resetSpeed() {
    downBps = 0;
    upBps = 0;
    _lastSample = null;
    _lastUp = 0;
    _lastDown = 0;
  }

  /// سرعت = اختلاف شمارنده‌های تجمعی ÷ زمان واقعی بین دو نمونه (با هموارسازی ملایم).
  void _updateSpeed(VlessStatus s) {
    final now = DateTime.now();
    final last = _lastSample;
    final up = s.upload, down = s.download;
    sessionBytes = up + down;
    if (last != null) {
      final dt = now.difference(last).inMilliseconds / 1000;
      if (dt < 0.25) return; // رویدادهای تکراریِ خیلی نزدیک
      if (up >= _lastUp && down >= _lastDown) {
        const alpha = 0.6; // ۱ = بدون هموارسازی
        upBps = alpha * ((up - _lastUp) / dt) + (1 - alpha) * upBps;
        downBps = alpha * ((down - _lastDown) / dt) + (1 - alpha) * downBps;
      } else {
        // شمارنده‌ها صفر شده‌اند (راه‌اندازی مجدد هسته)
        upBps = 0;
        downBps = 0;
      }
    }
    _lastSample = now;
    _lastUp = up;
    _lastDown = down;
  }

  void _onVlessStatus(VlessStatus s) {
    vlessStatus = s;
    switch (s.connectionState) {
      case VlessConnectionState.connected:
        _setVpn(VpnStatus.connected);
        _updateSpeed(s);
        final w = _connectWaiter;
        if (w != null && !w.isCompleted) w.complete();
      case VlessConnectionState.connecting:
        _sawPluginConnecting = true;
        if (vpnStatus == VpnStatus.disconnected) _setVpn(VpnStatus.connecting);
      case VlessConnectionState.disconnecting:
      case VlessConnectionState.disconnected:
        final w = _connectWaiter;
        if (w != null && !w.isCompleted) {
          // وسط فرایند اتصال: فقط اگر هسته شروع کرده بود و دوباره قطع شد خطاست
          if (_sawPluginConnecting) {
            w.completeError(const AppException('اتصال برقرار نشد.'));
          }
        } else {
          _setVpn(VpnStatus.disconnected);
        }
      case VlessConnectionState.unknown:
        break;
    }
    notifyListeners();
  }

  void _guard() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<void> toggleConnection() =>
      vpnStatus == VpnStatus.disconnected ? connect() : disconnect();

  /// اتصال سریع:
  ///  • اگر لینک کلاینت از قبل در Hive هست، VPN **بدون هیچ درخواست شبکه‌ای**
  ///    بلافاصله شروع می‌شود و وضعیت اکانت هم‌زمان در پس‌زمینه چک می‌شود؛
  ///  • وگرنه آمار و لینک هم‌زمان (موازی) گرفته می‌شوند؛
  ///  • مجوز VPN از همان ابتدا موازی با بقیه‌ی کارها درخواست می‌شود؛
  ///  • اگر لینک کش‌شده کار نکرد، لینک تازه گرفته و یک‌بار دوباره تلاش می‌شود.
  Future<void> connect() async {
    if (vpnStatus != VpnStatus.disconnected) return;
    if (maintenance) {
      _notice(maintenanceMessage.isEmpty ? 'سرویس در حال تعمیر است.' : maintenanceMessage);
      return;
    }
    final server = selectedServer;
    if (server == null) {
      _notice('ابتدا یک سرور انتخاب کنید.');
      return;
    }
    if (isLocked(server)) {
      _notice(_lockedMessage);
      return;
    }

    _cancelled = false;
    sessionBytes = null;
    _setVpn(VpnStatus.connecting);
    // پنجره‌ی مجوز VPN اپ را موقتاً به پس‌زمینه می‌برد؛ برگشت از آن «App Open» حساب نشود
    ads.markExternalLaunch();
    final permission = _vpn.requestPermission()..ignore();
    try {
      final acc = await _storedAccount(server);
      _guard();
      var link = acc?.link;
      final fromCache = link != null;
      if (fromCache) {
        if (server.canManageClients) unawaited(_verifyInBackground(server, acc!));
      } else {
        link = await _provision(server);
      }
      _guard();

      if (!await permission) {
        throw const AppException('برای اتصال باید مجوز VPN را بدهید.');
      }
      _guard();

      try {
        await _startAndWait(server, link);
      } on AppException {
        if (_cancelled || !fromCache) rethrow;
        // شاید لینک کش‌شده کهنه است (مدیر اینباند را تغییر داده)
        final fresh = await _freshLink(server);
        if (fresh == null || fresh == link || _cancelled) rethrow;
        await _safeStop();
        _guard();
        await _startAndWait(server, fresh);
      }
      _guard();
      _setVpn(VpnStatus.connected);
    } on _Cancelled {
      await _safeStop();
      _setVpn(VpnStatus.disconnected);
    } on AppException catch (e) {
      await _safeStop();
      _setVpn(VpnStatus.disconnected);
      _notice(e.message);
    } catch (e) {
      await _safeStop();
      _setVpn(VpnStatus.disconnected);
      _notice('اتصال ناموفق بود.');
      debugPrint('connect error: $e');
    } finally {
      _connectWaiter = null;
    }
  }

  Future<void> _startAndWait(VpnServer server, String link) async {
    _sawPluginConnecting = false;
    final waiter = _connectWaiter = Completer<void>();
    await _vpn.start(remark: server.title, link: link);
    await waiter.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw const AppException('اتصال برقرار نشد (timeout).'),
    );
  }

  /// بار اول (یا بعد از پاک شدن کش): حساب را بساز/بگیر، آمار و لینک را موازی بگیر.
  Future<String> _provision(VpnServer server) async {
    final (acc, known) = await _ensureAccount(server);
    _guard();
    final api = _apiFor(server);
    final r = await Future.wait<Object>([
      known != null ? Future.value(known) : api.getStats(acc.email),
      api.getLinks(acc.email),
    ]);
    final stats = r[0] as ClientStats;
    final links = (r[1] as List).cast<String>();
    _setStats(stats);
    notifyListeners();
    if (!stats.canConnect) throw AppException(_blockedMessage(stats.state));

    final link = _pickLink(links);
    if (link == null) {
      throw const AppException('لینک اتصال برای اکانت شما پیدا نشد. با مدیر تماس بگیرید.');
    }
    await storage.saveAccount(acc.withLink(link));
    return link;
  }

  String? _pickLink(List<String> links) {
    for (final l in links) {
      if (l.startsWith('vless://')) return l;
    }
    return links.isNotEmpty && links.first.isNotEmpty ? links.first : null;
  }

  /// لینک تازه از پنل (null اگر نشد). در صورت موفقیت در Hive ذخیره می‌شود.
  Future<String?> _freshLink(VpnServer server) async {
    try {
      final acc = storage.account(server.id);
      if (acc == null) return null;
      final link = _pickLink(await _apiFor(server).getLinks(acc.email));
      if (link != null) await storage.saveAccount(acc.withLink(link));
      return link;
    } catch (_) {
      return null;
    }
  }

  /// هم‌زمان با راه‌اندازی VPN: اکانت هنوز مجاز است؟ خطای شبکه نادیده گرفته می‌شود.
  Future<void> _verifyInBackground(VpnServer server, ClientAccount acc) async {
    final ClientStats s;
    try {
      s = await _apiFor(server).getStats(acc.email);
    } on XuiException catch (e) {
      if (!e.apiError) return;
      // کلاینت از پنل حذف شده → کش را پاک کن؛ اتصال بعدی دوباره می‌سازد
      await storage.removeAccount(server.id);
      _stats = null;
      if (vpnStatus != VpnStatus.disconnected) {
        _notice('اکانت شما روی سرور پیدا نشد؛ دوباره متصل شوید تا ساخته شود.');
        await disconnect();
      }
      notifyListeners();
      return;
    } catch (_) {
      return;
    }
    if (_selectedServerId != server.id) return;
    _setStats(s);
    if (!s.canConnect && vpnStatus != VpnStatus.disconnected) {
      _notice(_blockedMessage(s.state));
      await disconnect();
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    _cancelled = true;
    final w = _connectWaiter;
    if (w != null && !w.isCompleted) w.completeError(const _Cancelled());
    await _safeStop();
    _setVpn(VpnStatus.disconnected);
  }

  Future<void> _safeStop() async {
    try {
      await _vpn.stop();
    } catch (_) {}
  }

  // ===================================================================== //
  // جایزه‌ی تبلیغات
  // ===================================================================== //
  bool _applyingRewards = false;

  /// جایزه‌ی یک تبلیغ پاداش‌دار را می‌دهد:
  ///  • سکه / «بدون تبلیغ»: محلی؛
  ///  • حجم / روز: روی اکانت 3X-UI اعمال می‌شود (اگر الان نشد، در صف می‌ماند و بعداً اعمال می‌شود).
  Future<void> claimAdReward(AdItem ad, String placement) async {
    if (!ad.hasReward) return;
    ads.recordReward(ad, placement);
    final label = rewardLabel(ad);
    switch (ad.rewardType) {
      case 'coins':
        ads.ledger.addCoins(ad.rewardAmount.round());
        ads.changed();
        _notice('🎉 $label به حساب شما اضافه شد.');
      case 'no_ads_minutes':
        ads.ledger.grantNoAds(ad.rewardAmount.round());
        ads.changed();
        _notice('🎉 $label فعال شد.');
      case 'traffic_mb' || 'days':
        ads.ledger.addPending(PendingReward(ad.rewardType, ad.rewardAmount));
        await applyPendingRewards(announce: true);
    }
  }

  /// جوایز حجم/روزِ در انتظار را یکی‌یکی روی اکانت اعمال می‌کند.
  Future<void> applyPendingRewards({bool announce = false}) async {
    if (_applyingRewards) return;
    _applyingRewards = true;
    try {
      for (;;) {
        final list = ads.ledger.pending;
        if (list.isEmpty) break;
        final server = selectedServer;
        final acc = account;
        if (server == null || acc == null || !server.canManageClients) {
          if (announce) _notice('جایزه ثبت شد و پس از ساخت اکانت روی اشتراک شما اعمال می‌شود.');
          break;
        }
        final r = list.first;
        final label = rewardText(r.type, r.amount);
        try {
          final res = await _apiFor(server).adjustClient(
            acc.email,
            addBytes: r.type == 'traffic_mb' ? (r.amount * 1024 * 1024).round() : 0,
            addDays: r.type == 'days' ? r.amount.ceil() : 0,
          );
          ads.ledger.setPending(list.skip(1).toList());
          final skip = res.skipReason;
          _notice(skip == null
              ? '🎉 $label به اشتراک شما اضافه شد.'
              : skip.contains('unlimited')
                  ? 'اشتراک شما محدودیتی ندارد؛ نیازی به افزودن $label نیست.'
                  : 'اعمال جایزه ممکن نشد ($skip).');
          unawaited(refreshStats());
        } on XuiException catch (e) {
          if (!e.apiError) break; // شبکه: بعداً دوباره
          ads.ledger.setPending(list.skip(1).toList());
          _notice('اعمال جایزه ناموفق بود: ${e.message}');
        }
      }
    } finally {
      _applyingRewards = false;
    }
  }
}
