import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/ads/ad_flow.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/widgets/ad_slot.dart';
import 'package:yamyam/ads/widgets/reward_center.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/models/vpn_status.dart';
import 'package:yamyam/platform/desktop_platform.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/screen/gold_page.dart';
import 'package:yamyam/widgets/remote_tap.dart';
import 'package:yamyam/state/app_controller.dart';
import 'package:yamyam/state/app_scope.dart';
import 'package:yamyam/widgets/account_panel.dart';
import 'package:yamyam/widgets/popups.dart';
import 'package:yamyam/widgets/server_picker_sheet.dart';
import 'package:yamyam/widgets/slide_power.dart';
import 'package:yamyam/widgets/settings_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  VpnStatus _status = VpnStatus.disconnected;

  late final AnimationController _enter; // ورود مرحله‌ای صفحه
  late final AnimationController _ambient; // حرکت آهسته‌ی پس‌زمینه
  final ValueNotifier<double> _slideP = ValueNotifier(0); // پیشرفت کشیدن دستگیره
  final ScrollController _scroll = ScrollController();

  // ---------- منطق اپ (کانفیگ پنل، سرورها، کلاینت، VPN) ----------
  late AppController _c;
  bool _bound = false;
  bool _flowRunning = false;
  StreamSubscription<String>? _noticeSub;

  // ---------- تبلیغات ----------
  bool _adBusy = false; // یک جریان تبلیغاتی (اتصال/قطع) در حال اجراست
  bool _launchAdDone = false; // پاپ‌آپ ورود فقط یک‌بار در هر اجرا
  DateTime? _pausedAt;
  Timer? _postConnectTimer;

  /// مدت اتصال از هسته‌ی VPN
  Duration get _elapsed => Duration(seconds: _c.vlessStatus?.duration ?? 0);

  // ---------- رنگ‌ها (سبک iOS، هم‌سو با اسپلش) ----------
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _dark ? Colors.black : const Color(0xFFF2F2F7);
  Color get _card => _dark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get _label => _dark ? Colors.white : const Color(0xFF1C1C1E);
  Color get _secondary => const Color(0xFF8E8E93);
  Color get _separator =>
      _dark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);

  static const _blue = Color(0xFF0A84FF);
  static const _cyan = Color(0xFF5AC8FA);
  static const _green = Color(0xFF34C759);
  static const _mint = Color(0xFF30D158);
  // رنگ‌های گرادیان دکمه (آخرین حالت فعال حفظ می‌شود تا موقع قطع، نرم محو شود)
  Color _gA = _cyan;
  Color _gB = _blue;

  /// کاربر طلایی با «تم طلایی» روشن
  bool get _gold => _c.goldTheme;
  Color get _connectedColor => _gold ? UiPalette.gold : _green;
  (Color, Color) get _connectedGradient =>
      _gold ? (UiPalette.goldLight, UiPalette.gold) : (_mint, _green);

  void _setGrad((Color, Color) g) {
    _gA = g.$1;
    _gB = g.$2;
  }

  /// رنگ شاخص پس‌زمینه (حتی در حالت قطع رنگی است تا صفحه جان داشته باشد)
  Color get _accent => switch (_status) {
        VpnStatus.disconnected => _gold ? UiPalette.gold : _blue,
        VpnStatus.connecting => _gold ? UiPalette.gold : _blue,
        VpnStatus.connected => _connectedColor,
      };

  Color get _tint => switch (_status) {
        VpnStatus.disconnected => _secondary,
        VpnStatus.connecting => _gold ? UiPalette.gold : _blue,
        VpnStatus.connected => _connectedColor,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bound) return;
    _bound = true;
    _c = AppScope.of(context, listen: false);
    _c.addListener(_sync);
    _noticeSub = _c.notices.listen(_showNotice);

    // اگر سرویس VPN از قبل متصل بوده، ظاهر را هم‌سو کن
    _status = _c.vpnStatus;
    if (_status == VpnStatus.connected) _setGrad(_connectedGradient);

    // بعد از آماده شدن کنترلر: پاپ‌آپ‌ها (آپدیت، سرور، پیام)
    _c.start().then((_) {
      if (mounted) _runLaunchFlow();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _c.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state != AppLifecycleState.resumed) return;
    _maybeAppOpenAd();
    // فقط اگر داده کهنه است درخواست بزن (آمار ۶۰ ثانیه، کانفیگ+تبلیغات ۴۵ ثانیه)
    _c.refreshStatsIfStale();
    _c.refreshConfigIfStale(maxAge: const Duration(seconds: 45)).then((_) {
      if (mounted) _runLaunchFlow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noticeSub?.cancel();
    _postConnectTimer?.cancel();
    if (_bound) _c.removeListener(_sync);
    _enter.dispose();
    _ambient.dispose();
    _slideP.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- منطق ----------

  /// ترتیب پاپ‌آپ‌ها: تعمیر → آپدیت اجباری → انتخاب سرور (بار اول) → پیام مدیر → آپدیت اختیاری
  Future<void> _runLaunchFlow() async {
    if (_flowRunning) return;
    _flowRunning = true;
    try {
      await _c.waitForConfig();
      if (!mounted || _c.maintenance) return;

      if (_c.updateForced) {
        await showUpdateDialog(context, _c);
        return;
      }
      if (!_c.hasSelectedServer) {
        await showServerPicker(context, firstTime: true);
        if (!mounted) return;
      }
      final msg = _c.pendingMessage;
      if (msg != null) {
        await showAdminMessage(context, _c, msg);
        if (!mounted) return;
      }
      if (_c.shouldPromptUpdate) await showUpdateDialog(context, _c);
      if (!mounted) return;

      // پاپ‌آپ تبلیغاتی ورود (بعد از همه‌ی پیام‌های سیستمی، فقط یک‌بار)
      if (!_launchAdDone && _c.hasSelectedServer) {
        _launchAdDone = true;
        await AdFlow.showInterruptive(context, _c, AdPlacement.launchPopup);
      }
    } finally {
      _flowRunning = false;
    }
  }

  /// برگشت از پس‌زمینه → تبلیغ App Open (نه بعد از مرورگر/پنجره‌ی مجوز، نه وسط اتصال)
  void _maybeAppOpenAd() {
    final p = _pausedAt;
    _pausedAt = null;
    if (p == null || _adBusy || _flowRunning) return;
    if (_c.vpnStatus == VpnStatus.connecting) return;
    if (!_c.ads.shouldShowAppOpen(DateTime.now().difference(p))) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AdFlow.showAppOpen(context, _c);
    });
  }

  /// چند ثانیه بعد از اتصال موفق: تبلیغ «بعد از اتصال» (اگر تعریف شده باشد)
  void _schedulePostConnectAd() {
    _postConnectTimer?.cancel();
    _postConnectTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _adBusy || _c.vpnStatus != VpnStatus.connected) return;
      if (!_c.appInForeground) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      AdFlow.showInterruptive(context, _c, AdPlacement.postConnect);
    });
  }

  void _showNotice(String message) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 4),
        content: Text(message, style: const TextStyle(height: 1.5)),
      ),
    );
  }

  /// هر تغییر کنترلر: وضعیت VPN را با انیمیشن‌ها هماهنگ کن و UI را بروز کن
  void _sync() {
    if (!mounted) return;
    final next = _c.vpnStatus;
    if (next != _status) {
      _applyStatus(next);
    } else {
      setState(() {
        // پلن عوض شد (مثلاً طلایی فعال شد) → رنگ دکمه‌ی متصل هم‌گام شود
        if (_status == VpnStatus.connected) _setGrad(_connectedGradient);
      });
    }
  }

  void _applyStatus(VpnStatus next) {
    setState(() {
      _status = next;
      if (next == VpnStatus.connecting) {
        _setGrad(_gold ? (UiPalette.goldLight, UiPalette.goldDeep) : (_cyan, _blue));
      } else if (next == VpnStatus.connected) {
        _setGrad(_connectedGradient);
      }
    });
    switch (next) {
      case VpnStatus.connecting:
        break;
      case VpnStatus.connected:
        HapticFeedback.lightImpact();
        _schedulePostConnectAd();
      case VpnStatus.disconnected:
        _postConnectTimer?.cancel();
    }
  }

  /// اتصال/قطع/لغو. تا پایان کل جریان (تبلیغ + اتصال) منتظر می‌ماند تا دستگیره درست جا بیفتد.
  Future<void> _toggle() async {
    HapticFeedback.mediumImpact();
    final st = _c.vpnStatus;
    // لغو اتصالِ در جریان همیشه ممکن است
    if (st == VpnStatus.connecting) {
      await _c.toggleConnection();
      return;
    }
    if (_adBusy) return;
    _adBusy = true;
    try {
      // اتصال: در صورت فعال بودن، تبلیغ پیش از اتصال؛ قطع: تبلیغ هنگام قطع
      await (st == VpnStatus.disconnected
          ? AdFlow.connectWithAds(context, _c)
          : AdFlow.disconnectWithAds(context, _c));
    } finally {
      _adBusy = false;
    }
  }

  /// اسکرول نرم به بخش‌های پایین (با لمس نشانگر «پایین‌تر»)
  void _scrollToDetails(double heroHeight) {
    if (!_scroll.hasClients) return;
    HapticFeedback.selectionClick();
    final target = (heroHeight * 0.7).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
    );
  }

  String _fa(String s) {
    const en = '0123456789';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(en[i], fa[i]);
    }
    return s;
  }

  String get _timeText {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = two(_elapsed.inHours);
    final m = two(_elapsed.inMinutes.remainder(60));
    final s = two(_elapsed.inSeconds.remainder(60));
    return _fa('$h:$m:$s');
  }

  String get _statusText => switch (_status) {
        VpnStatus.disconnected => 'متصل نیستید',
        VpnStatus.connecting => 'در حال اتصال…',
        VpnStatus.connected => 'متصل شدید',
      };

  String get _hintText => switch (_status) {
        VpnStatus.disconnected => TvPlatform.isTv
            ? 'برای اتصال، دکمه‌ی پایین را با ریموت انتخاب کنید'
            : isDesktopPlatform(context)
                ? 'با یک کلیک، امن شوید'
                : 'با یک کشیدن، امن شوید',
        VpnStatus.connecting => 'لطفاً کمی صبر کنید',
        VpnStatus.connected => 'اتصال شما امن است',
      };

  // ---------- ورود مرحله‌ای ----------
  Widget _in(Widget child, double a, double b, {double dy = 16}) {
    return AnimatedBuilder(
      animation: _enter,
      child: child,
      builder: (_, c) {
        final p = Curves.easeOutCubic
            .transform(((_enter.value - a) / (b - a)).clamp(0.0, 1.0));
        return Opacity(
          opacity: p,
          child: Transform.translate(offset: Offset(0, dy * (1 - p)), child: c),
        );
      },
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        // نوار تبلیغاتی چسبان پایین (فقط اگر تبلیغی باشد فضا می‌گیرد)
        bottomNavigationBar: const AdSlot(
          placement: AdPlacement.homeBottom,
          sticky: true,
          showRemove: true,
          padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
        ),
        body: SizedBox.expand(
          child: Stack(
            children: [
              _backdrop(),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // بخش اول: هدر، تبلیغات، وضعیت، دکمه، پلن و انتخاب سرور.
                    // کمی کوتاه‌تر از صفحه است تا لبه‌ی بالای بخش دوم پایین صفحه
                    // دیده شود و کاربر بفهمد می‌شود اسکرول کرد.
                    const peek = 76.0;
                    final heroMin = (box.maxHeight - peek).clamp(420.0, 4000.0);
                    return SingleChildScrollView(
                      controller: _scroll,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: TvPlatform.isTv ? 720 : double.infinity,
                          ),
                          child: Column(
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(minHeight: heroMin),
                                child: IntrinsicHeight(child: _hero(box.maxHeight)),
                              ),
                              _details(),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // آیکون شناور تبلیغاتی
              PositionedDirectional(
                start: 8,
                top: MediaQuery.sizeOf(context).height * 0.30,
                child: const FloatingAdIcon(),
              ),
              if (_c.maintenance)
                MaintenanceView(
                  message: _c.maintenanceMessage.isEmpty
                      ? 'سرویس در حال بروزرسانی است. لطفاً کمی بعد تلاش کنید.'
                      : _c.maintenanceMessage,
                  onRetry: () => _c.refreshConfig().then((_) {
                    if (mounted) _runLaunchFlow();
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// بخش اول: هدر، وضعیت و دکمه‌ی کشیدنی (به اندازه‌ی ارتفاع صفحه)
  Widget _hero(double viewportHeight) {
    return Column(
      children: [
        _in(_header(), 0.0, 0.45, dy: -10),
        const AdSlot(
          placement: AdPlacement.homeTop,
          padding: EdgeInsets.only(top: 12),
        ),
        const Spacer(flex: 3),
        _in(_statusBlock(), 0.10, 0.55),
        const SizedBox(height: 20),
        _in(_slider(), 0.22, 0.70, dy: 22),
        const Spacer(flex: 3),
        const AdSlot(
          placement: AdPlacement.homeMiddle,
          padding: EdgeInsets.only(bottom: 12),
        ),
        _in(_planBanner(), 0.30, 0.80, dy: 24),
        _in(_serverCard(), 0.35, 0.85, dy: 28),
        _in(_scrollHint(viewportHeight), 0.45, 0.95, dy: 10),
      ],
    );
  }

  /// نشانگر «پایین‌تر بروید» (با اسکرول کم‌رنگ می‌شود)
  Widget _scrollHint(double heroHeight) {
    return ListenableBuilder(
      listenable: _scroll,
      builder: (_, child) {
        final off = _scroll.hasClients ? _scroll.offset : 0.0;
        final o = (1 - off / 90).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: o < 0.2,
          child: Opacity(opacity: o, child: child),
        );
      },
      child: _Pressable(
        onTap: () => _scrollToDetails(heroHeight),
        pressedScale: 0.94,
        child: Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'اشتراک و سرعت اینترنت',
                style: TextStyle(fontSize: 12.5, color: _secondary),
              ),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 22, color: _secondary),
            ],
          ),
        ),
      ),
    );
  }

  /// بخش دوم: وضعیت اشتراک، جایزه و سرعت (با اسکرول دیده می‌شود)
  Widget _details() {
    return Column(
      children: [
        const SizedBox(height: 6),
        _detailCards(),
        const SizedBox(height: 32),
      ],
    );
  }

  /// هاله‌ی بسیار ملایم پشت دکمه که با وضعیت تغییر رنگ می‌دهد
  Widget _backdrop() {
    final level = switch (_status) {
      VpnStatus.disconnected => 0.0,
      VpnStatus.connecting => 0.5,
      VpnStatus.connected => 1.0,
    };
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: _accent),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
          builder: (_, c, __) => TweenAnimationBuilder<double>(
            tween: Tween(end: level),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            builder: (_, lv, __) => AnimatedBuilder(
              animation: Listenable.merge([_ambient, _slideP]),
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: _BackdropPainter(
                  t: _ambient.value,
                  level: lv,
                  drag: _slideP.value,
                  tint: c ?? _secondary,
                  dark: _dark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final brand = _gold
        ? UiPalette.gold
        : (_status == VpnStatus.connected ? _green : _blue);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: brand),
            duration: const Duration(milliseconds: 600),
            builder: (_, c, __) => Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Y', style: TextStyle(color: c)),
                  const TextSpan(text: 'am '),
                  TextSpan(text: 'Y', style: TextStyle(color: c)),
                  const TextSpan(text: 'am'),
                ],
              ),
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: _label,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _planChip(),
          const Spacer(),
          _CircleIconButton(
            icon: Icons.settings_outlined,
            color: _label,
            background: _card,
            onTap: () => showSettingsSheet(context),
          ),
        ],
      ),
    );
  }

  // ---------- پلن ----------
  /// نشان پلن کنار نام برنامه: طلایی (با روز باقی‌مانده) یا رایگان. با لمس، صفحه‌ی پلن طلایی باز می‌شود.
  Widget _planChip() {
    if (!_c.plansEnabled || !_c.plans.ui.showPlanChip) return const SizedBox.shrink();
    final gold = _c.isGold;
    if (!gold && !_c.plans.canPurchase) return const SizedBox.shrink();
    final accent = parseHexColor(_c.plans.gold.accentHex);
    final label = gold
        ? '${_c.plans.gold.title} · ${faDigits(_c.goldDaysLeft)} روز'
        : _c.plans.free.title;
    return Flexible(
      child: _Pressable(
        onTap: () => openGoldPage(context),
        pressedScale: 0.94,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: gold
                ? LinearGradient(colors: [UiPalette.goldLight, accent])
                : null,
            color: gold ? null : _card,
            borderRadius: BorderRadius.circular(20),
            border: gold ? null : Border.all(color: _separator),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                gold ? Icons.workspace_premium_rounded : Icons.bolt_rounded,
                size: 15,
                color: gold ? const Color(0xFF3A2A00) : accent,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: gold ? const Color(0xFF3A2A00) : _label,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// کارت ترویجی/هشدار تمدید بالای کارت پایین.
  Widget _planBanner() {
    final c = _c;
    if (!c.plansEnabled || !c.plans.canPurchase) return const SizedBox.shrink();
    final ui = c.plans.ui;
    final accent = parseHexColor(c.plans.gold.accentHex);
    String? title, text, action;
    if (c.isGold) {
      if (!c.goldExpiringSoon) return const SizedBox.shrink();
      title = PlanUi.fmt(ui.expiringTitle, 'اشتراک {plan} رو به پایان است',
          plan: c.plans.gold.title, days: c.goldDaysLeft);
      text = PlanUi.fmt(ui.expiringText, '{days} روز باقی‌مانده؛ همین حالا تمدید کنید.',
          plan: c.plans.gold.title, days: c.goldDaysLeft);
      action = PlanUi.fmt(ui.renewCta, 'تمدید', plan: c.plans.gold.title);
    } else if (c.goldExpired) {
      title = PlanUi.fmt(ui.expiredTitle, 'اشتراک {plan} شما تمام شده است', plan: c.plans.gold.title);
      text = PlanUi.fmt(ui.expiredText, 'برای بازگشت حجم و امکانات ویژه، تمدید کنید.',
          plan: c.plans.gold.title);
      action = PlanUi.fmt(ui.renewCta, 'تمدید', plan: c.plans.gold.title);
    } else if (c.showUpsell) {
      title = ui.upsellTitle.isEmpty ? 'پلن ${c.plans.gold.title} را امتحان کنید' : ui.upsellTitle;
      text = ui.upsellText;
      action = PlanUi.fmt(ui.upsellCta, 'مشاهده', plan: c.plans.gold.title);
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _Pressable(
        onTap: () => openGoldPage(context),
        pressedScale: 0.98,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: _dark ? 0.30 : 0.22),
                accent.withValues(alpha: _dark ? 0.14 : 0.08),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.workspace_premium_rounded, color: accent, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _label)),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(text, style: TextStyle(fontSize: 12.5, color: _secondary, height: 1.5)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(16)),
                child: Text(action,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF2B1F00))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- وضعیت ----------
  Widget _switcher(ValueKey<String> current, Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, anim) {
        final incoming = c.key == current;
        final slide = Tween<Offset>(
          begin: Offset(0, incoming ? 0.3 : -0.3),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: slide, child: c),
        );
      },
      child: child,
    );
  }

  Widget _statusBlock() {
    final connected = _status == VpnStatus.connected;
    final titleKey = ValueKey<String>(_statusText);
    final subKey =
        connected ? const ValueKey<String>('timer') : ValueKey<String>(_hintText);

    return Column(
      children: [
        _switcher(
          titleKey,
          Text(
            _statusText,
            key: titleKey,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: connected ? _connectedColor : _label,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _switcher(
          subKey,
          connected
              ? Row(
                  key: subKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 15, color: _green),
                    const SizedBox(width: 6),
                    Text(
                      _timeText,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        color: _secondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                )
              : Text(
                  _hintText,
                  key: subKey,
                  style: TextStyle(fontSize: 14, color: _secondary),
                ),
        ),
      ],
    );
  }

  /// کشیدنِ دستگیره: راه روشن و خاموش کردن.
  Widget _slider() {
    final connecting = _status == VpnStatus.connecting;
    final (a, b) = connecting ? (_gA, _gB) : _connectedGradient;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SlidePower(
          status: _status,
          colorA: a,
          colorB: b,
          dark: _dark,
          autofocus: true,
          progress: _slideP,
          onToggle: _toggle,
        ),
      ),
    );
  }

  // ---------- کارت‌های پایین ----------
  /// سطح یکدست کارت‌ها (گوشه‌ی گرد، سایه‌ی ملایم، حاشیه‌ی طلایی برای کاربر طلایی)
  Widget _surface({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_dark ? 0 : 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        // کمی شفاف تا هاله‌های پس‌زمینه از پشت کارت‌ها دیده شوند (حس شیشه)
        color: _card.withValues(alpha: _dark ? 0.78 : 0.82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: _gold
              ? BorderSide(color: UiPalette.gold.withValues(alpha: 0.45), width: 1.1)
              : BorderSide(
                  color: _dark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.black.withValues(alpha: 0.035),
                  width: 0.8,
                ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  /// انتخاب سرور (بخش اول)
  Widget _serverCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _surface(child: _serverRow()),
    );
  }

  /// کارت‌های بخش دوم
  Widget _detailCards() {
    final s = _c.selectedServer;
    final connected = _status == VpnStatus.connected;
    final down = connected ? _c.downBps : 0.0;
    final up = connected ? _c.upBps : 0.0;

    return Column(
      children: [
        if (s != null) ...[
          _surface(
            child: Column(
              children: [
                // وضعیت اشتراک: فعال/غیرفعال، مصرف، زمان باقی‌مانده، مصرف این اتصال
                AccountPanel(controller: _c),
                // «ویدیو ببین، جایزه بگیر» (فقط اگر تبلیغ پاداش‌دار هست)
                RewardCenterRow(controller: _c),
              ],
            ),
          ),
        ],
        if (s != null) const SizedBox(height: 14),
        // سرعت لحظه‌ای
        _surface(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                _stat(Icons.arrow_downward_rounded, 'دانلود', down, _blue),
                Container(width: 0.5, height: 36, color: _separator),
                _stat(Icons.arrow_upward_rounded, 'آپلود', up, _green),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _serverRow() {
    final s = _c.selectedServer;
    final connected = _status == VpnStatus.connected;
    final canPick = _status == VpnStatus.disconnected && _c.provisioningServerId == null;
    final subtitle = s == null
        ? 'برای شروع یک سرور انتخاب کنید'
        : (s.country.isEmpty ? 'سرور انتخاب‌شده' : s.country);
    return InkWell(
      onTap: canPick ? _pickServer : null,
      canRequestFocus: canPick,
      focusColor: _blue.withOpacity(0.12),
      highlightColor: _label.withOpacity(0.05),
      splashColor: _label.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _label.withOpacity(_dark ? 0.08 : 0.05),
              ),
              child: Text(s?.flag ?? '🌐', style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s?.title ?? 'انتخاب سرور',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: _label),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: _secondary),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: connected
                  ? Container(
                      key: const ValueKey('chip'),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _connectedColor.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'فعال',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _connectedColor,
                        ),
                      ),
                    )
                  : AnimatedOpacity(
                      key: const ValueKey('chev'),
                      opacity: canPick ? 1 : 0.25,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(Icons.chevron_left_rounded, color: _secondary.withOpacity(0.8)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String title, double bytesPerSecond, Color color) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(title, style: TextStyle(fontSize: 13, color: _secondary)),
            ],
          ),
          const SizedBox(height: 4),
          // حرکت کوتاه بین دو نمونه؛ سرعت هر ثانیه به‌روز می‌شود و نباید عقب بماند
          TweenAnimationBuilder<double>(
            tween: Tween(end: bytesPerSecond),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            builder: (_, v, __) {
              final p = speedParts(v);
              return Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: p.value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: _label,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  TextSpan(
                    text: '  ${p.unit}',
                    style: TextStyle(fontSize: 12, color: _secondary),
                  ),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------- انتخاب سرور ----------
  Future<void> _pickServer() async {
    HapticFeedback.selectionClick();
    await showServerPicker(context);
  }
}

/// لمس با فنر واقعی: هنگام فشردن کوچک می‌شود و با کمی بازگشت نرم برمی‌گردد
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool autofocus;
  const _Pressable({
    required this.child,
    required this.onTap,
    this.pressedScale = 0.95,
    this.autofocus = false,
  });

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable>
    with SingleTickerProviderStateMixin {
  static const _spring =
      SpringDescription(mass: 1, stiffness: 520, damping: 26);
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 1);

  void _to(double target) {
    _c.animateWith(SpringSimulation(_spring, _c.value, target, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RemoteTap(
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      circular: true,
      onTapDown: () => _to(widget.pressedScale),
      onTapUp: () => _to(1),
      onTapCancel: () => _to(1),
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => Transform.scale(scale: _c.value, child: child),
      ),
    );
  }
}

/// پس‌زمینه‌ی زنده: گرادیان پایه، سه هاله‌ی نرم که آهسته شناورند،
/// و موج‌های حلقه‌ای که بعد از اتصال از مرکز پخش می‌شوند.
class _BackdropPainter extends CustomPainter {
  final double t; // ۰..۱ چرخه‌ی ۲۰ ثانیه‌ای
  final double level; // ۰ قطع، ۰٫۵ در حال اتصال، ۱ متصل
  final double drag; // ۰..۱ پیشرفت کشیدن دستگیره
  final Color tint;
  final bool dark;

  _BackdropPainter({
    required this.t,
    required this.level,
    required this.drag,
    required this.tint,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // پایه
    final top = dark ? const Color(0xFF0C0C10) : const Color(0xFFF8F8FC);
    final bottom = dark ? Colors.black : const Color(0xFFECECF3);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect),
    );

    final act = (level * 2).clamp(0.0, 1.0);
    final a = (dark ? 0.09 : 0.07) + (dark ? 0.06 : 0.045) * act + 0.04 * drag;
    final ang = t * 2 * math.pi;

    void orb(Offset c, double r, Color col, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [col.withValues(alpha: alpha), col.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final hsl = HSLColor.fromColor(tint);
    final warm = hsl.withHue((hsl.hue + 38) % 360).toColor();

    orb(Offset(w * (0.18 + 0.08 * math.sin(ang)), h * (0.10 + 0.04 * math.cos(ang))),
        w * 0.85, tint, a);
    orb(Offset(w * (0.88 + 0.06 * math.cos(ang + 1)), h * (0.62 + 0.05 * math.sin(ang + 2))),
        w * 0.75, warm, a * 0.55);
    orb(Offset(w * 0.5, h * (0.40 + 0.015 * math.sin(ang * 2))), w * 0.95, tint, a * 0.7);

    // حلقه‌های تزئینی ثابت دور دکمه (همیشه دیده می‌شوند)
    final rc = Offset(w / 2, h * 0.40);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(
        rc,
        w * (0.22 + 0.2 * i),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = (dark ? Colors.white : tint).withValues(alpha: dark ? 0.035 : 0.05),
      );
    }

    // موج‌های حلقه‌ای بعد از اتصال
    final rf = ((level - 0.5) * 2).clamp(0.0, 1.0);
    if (rf > 0) {
      final c = Offset(w / 2, h * 0.40);
      for (var i = 0; i < 3; i++) {
        final p = (t * 5 + i / 3) % 1.0;
        final r = 70 + (w * 0.95) * Curves.easeOutCubic.transform(p);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = tint.withValues(alpha: (1 - p) * (dark ? 0.08 : 0.06) * rf),
        );
      }
    }

    // تیرگی لبه‌ها (فقط تم تاریک)
    if (dark) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(0, 0.05),
            radius: 1.15,
            colors: [Color(0x00000000), Color(0x59000000)],
            stops: [0.55, 1.0],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.t != t ||
      old.level != level ||
      old.drag != drag ||
      old.tint != tint ||
      old.dark != dark;
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color color, background;
  final VoidCallback onTap;
  const _CircleIconButton({
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}