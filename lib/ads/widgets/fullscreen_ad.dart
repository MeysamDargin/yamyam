import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:yamyam/ads/ad_actions.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ad_text.dart';
import 'package:yamyam/ads/ads_manager.dart';
import 'package:yamyam/ads/widgets/ad_media.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/widgets/open_url.dart';
import 'package:yamyam/widgets/remote_tap.dart';

/// وضعیت اتصال VPN که پایین صفحه‌ی تبلیغِ پیش از اتصال نشان داده می‌شود.
class PreConnectLink {
  final Listenable listenable;
  final String Function() statusText;
  final bool Function() failed;
  const PreConnectLink({
    required this.listenable,
    required this.statusText,
    required this.failed,
  });
}

/// نتیجه‌ی نمایش یک تبلیغ تمام‌صفحه/پاپ‌آپ
class AdRunResult {
  /// واقعاً روی صفحه آمد؟ (false = شکست در بارگذاری)
  final bool shown;
  final bool completed;
  final bool skipped;
  final bool failed;
  final bool timedOut;
  final bool clicked;

  /// کاربر شرط جایزه (زمان تماشا) را پوشش داد؟
  final bool rewardEarned;
  final int watchedMs;

  const AdRunResult({
    this.shown = false,
    this.completed = false,
    this.skipped = false,
    this.failed = false,
    this.timedOut = false,
    this.clicked = false,
    this.rewardEarned = false,
    this.watchedMs = 0,
  });

  static const failure = AdRunResult(failed: true);
}

/// رفتار نمایش یک تبلیغ تمام‌صفحه؛ از فیلدهای تبلیغ و تنظیمات پنل ساخته می‌شود.
class FullscreenAdSpec {
  final AdItem ad;
  final String placement;
  final bool skippable;
  final int skipAfterSec;

  /// حداقل تماشا برای ادامه/جایزه (۰ = تا انتهای تبلیغ)
  final int requiredWatchSec;

  /// سقف مدت (۰ = طول ویدیو / پیش‌فرض تصویر)
  final int capSec;
  final bool showCountdown;
  final bool closeButton;
  final int closeDelaySec;

  /// پایان تبلیغ خودکار بسته شود؟
  final bool autoCloseOnComplete;

  /// حداکثر انتظار از لحظه‌ی باز شدن صفحه (۰ = سقف ایمنی ۱۲۰ ثانیه)
  final int maxWaitSec;
  final bool rewarded;
  final PreConnectLink? link;

  const FullscreenAdSpec({
    required this.ad,
    required this.placement,
    this.skippable = true,
    this.skipAfterSec = 5,
    this.requiredWatchSec = 0,
    this.capSec = 0,
    this.showCountdown = true,
    this.closeButton = true,
    this.closeDelaySec = 3,
    this.autoCloseOnComplete = false,
    this.maxWaitSec = 0,
    this.rewarded = false,
    this.link,
  });

  /// رفتار تبلیغ‌های معمولی (Interstitial / App Open / Splash / Rewarded)
  factory FullscreenAdSpec.forAd(AdItem ad, String placement, AdsSettings s) {
    final rewarded = ad.isRewarded;
    final auto = ad.format == AdFormat.splash ||
        ad.format == AdFormat.appOpen ||
        (ad.format == AdFormat.interstitial && !ad.isVideo && ad.durationSec > 0);
    return FullscreenAdSpec(
      ad: ad,
      placement: placement,
      skippable: rewarded ? false : ad.skippable,
      skipAfterSec: ad.skipAfterSec,
      requiredWatchSec: ad.requiredWatchSec,
      capSec: ad.durationSec,
      showCountdown: ad.showCountdown,
      closeButton: rewarded ? false : ad.closeButton,
      closeDelaySec: ad.closeDelaySec,
      autoCloseOnComplete: !rewarded && auto,
      rewarded: rewarded,
    );
  }

  /// رفتار تبلیغ پیش از اتصال VPN طبق [PreConnectPlan]
  factory FullscreenAdSpec.preConnect(PreConnectPlan plan, {PreConnectLink? link}) {
    final ad = plan.ad;
    if (ad.isRewarded) {
      return FullscreenAdSpec(
        ad: ad,
        placement: AdPlacement.preConnect,
        skippable: false,
        requiredWatchSec: ad.requiredWatchSec,
        capSec: ad.durationSec,
        showCountdown: ad.showCountdown,
        closeButton: false,
        maxWaitSec: plan.maxWaitSec,
        rewarded: true,
        link: link,
      );
    }
    final skippable = plan.mode == 'skippable';
    return FullscreenAdSpec(
      ad: ad,
      placement: AdPlacement.preConnect,
      skippable: skippable,
      skipAfterSec: plan.skipAfterSec,
      requiredWatchSec: 0,
      capSec: plan.mode == 'timed'
          ? (ad.durationSec > 0 ? ad.durationSec : plan.maxWaitSec)
          : ad.durationSec,
      showCountdown: ad.showCountdown,
      closeButton: false,
      autoCloseOnComplete: true,
      maxWaitSec: plan.maxWaitSec,
      link: link,
    );
  }
}

/// نمایش تمام‌صفحه؛ تا بسته شدن تبلیغ منتظر می‌ماند.
Future<AdRunResult> showFullscreenAd(
  BuildContext context,
  AdsManager ads,
  FullscreenAdSpec spec,
) async {
  ads.interruptiveActive = true;
  try {
    final r = await Navigator.of(context, rootNavigator: true).push<AdRunResult>(
      PageRouteBuilder<AdRunResult>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _FullscreenAdPage(spec: spec),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
    return r ?? const AdRunResult(skipped: true);
  } finally {
    ads.interruptiveActive = false;
  }
}

class _FullscreenAdPage extends StatefulWidget {
  final FullscreenAdSpec spec;
  const _FullscreenAdPage({required this.spec});

  @override
  State<_FullscreenAdPage> createState() => _FullscreenAdPageState();
}

class _FullscreenAdPageState extends State<_FullscreenAdPage> with WidgetsBindingObserver {
  FullscreenAdSpec get spec => widget.spec;
  AdItem get ad => spec.ad;

  late final AdsManager _ads;
  VideoPlayerController? _vc;
  final _hud = ValueNotifier<int>(0);
  Timer? _tickT, _maxT, _loadT;

  bool _shown = false;
  bool _completed = false;
  bool _closed = false;
  bool _paused = false;
  bool _clicked = false;
  int _watched = 0; // ms
  int _target = 6000; // ms
  DateTime _last = DateTime.now();

  int get _required {
    final r = spec.requiredWatchSec * 1000;
    return r > 0 ? math.min(r, _target) : _target;
  }

  bool get _rewardEarned => spec.rewarded && _shown && _watched >= _required;
  bool get _linkFailed => spec.link?.failed() ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ads = adsOf(context);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _tickT = Timer.periodic(const Duration(milliseconds: 200), (_) => _onTick());
    _maxT = Timer(
      Duration(seconds: spec.maxWaitSec > 0 ? spec.maxWaitSec : (spec.skippable ? 600 : 120)),
      () => _finish(timedOut: true),
    );
    // شامل دانلود رسانه‌ی کش‌نشده (مثلاً ویدیوی چند مگابایتی در اولین نمایش)
    _loadT = Timer(const Duration(seconds: 20), () {
      if (!_shown) _fail();
    });

    if (ad.isVideo) {
      _openVideo();
    } else if (!ad.isImage && !ad.isHtml) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fail());
    }
  }

  Future<void> _openVideo() async {
    final c = await openAdVideo(_ads, ad.mediaUrl, muted: ad.muted, loop: ad.loop);
    if (c == null) {
      _fail();
      return;
    }
    if (!mounted || _closed) {
      c.dispose();
      return;
    }
    final dur = c.value.duration.inMilliseconds;
    final cap = spec.capSec * 1000;
    _target = math.max(1000, cap > 0 ? (ad.loop ? cap : math.min(cap, dur)) : dur);
    setState(() => _vc = c);
    _begin();
  }

  /// رسانه روی صفحه آمد
  void _begin() {
    if (_shown || _closed || !mounted) return;
    _shown = true;
    _loadT?.cancel();
    _last = DateTime.now();
    if (!ad.isVideo) {
      final cap = spec.capSec * 1000;
      _target = cap > 0 ? cap : 6000;
    }
    _ads.recordImpression(ad, spec.placement);
    _ads.recordEvent(ad, 'start', spec.placement);
    if (_vc != null && ad.autoplay) _vc!.play();
    setState(() {}); // اسپینر برداشته شود و کلیک فعال شود
    _hud.value++;
  }

  void _fail() {
    if (_closed) return;
    _ads.markFailed(ad, spec.placement);
    _finish(failed: true);
  }

  void _onTick() {
    if (_closed) return;
    final now = DateTime.now();
    if (_shown && !_paused && !(_completed && !ad.loop)) {
      _watched += now.difference(_last).inMilliseconds;
    }
    _last = now;
    if (_shown && !_completed && _watched >= _target) _complete();
    _hud.value++;
  }

  void _complete() {
    _completed = true;
    _ads.recordEvent(ad, 'complete', spec.placement);
    if (!ad.loop) _vc?.pause();
    if (spec.autoCloseOnComplete) {
      _finish();
    } else if (!spec.rewarded) {
      HapticFeedback.selectionClick();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    _paused = !resumed;
    _last = DateTime.now();
    if (resumed) {
      if (_shown && !(_completed && !ad.loop) && ad.autoplay) _vc?.play();
    } else {
      _vc?.pause();
    }
  }

  /// بستن؛ [skipped] = کاربر قبل از پایان رد کرد
  void _finish({bool skipped = false, bool failed = false, bool timedOut = false}) {
    if (_closed) return;
    _closed = true;
    _tickT?.cancel();
    _maxT?.cancel();
    _loadT?.cancel();
    if (_shown) {
      _ads.recordEvent(ad, skipped && !_completed ? 'skip' : 'close', spec.placement);
    }
    final result = AdRunResult(
      shown: _shown,
      completed: _completed,
      skipped: skipped && !_completed,
      failed: failed,
      timedOut: timedOut,
      clicked: _clicked,
      rewardEarned: _rewardEarned,
      watchedMs: _watched,
    );
    if (mounted) Navigator.of(context).pop(result);
  }

  // ---------- قواعد دکمه‌ها ----------
  bool get _canSkip => spec.skippable && _watched >= spec.skipAfterSec * 1000;
  bool get _canContinue =>
      !spec.skippable && spec.requiredWatchSec > 0 && _watched >= _required;
  bool get _canLeave =>
      _completed || _canSkip || _canContinue || _linkFailed || !_shown;
  bool get _showClose =>
      _shown &&
      ((spec.closeButton && spec.skippable && _watched >= spec.closeDelaySec * 1000) ||
          (_completed && !spec.autoCloseOnComplete));

  void _leave() => _finish(skipped: !_completed);

  Future<void> _onBack() async {
    if (_canLeave) {
      _leave();
      return;
    }
    if (!spec.rewarded) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خروج از تبلیغ؟'),
        content: const Text('اگر الان خارج شوید جایزه را دریافت نمی‌کنید.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ادامه‌ی تماشا')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج')),
        ],
      ),
    );
    if (ok == true) _finish(skipped: true);
  }

  Future<void> _click() async {
    _clicked = true;
    await openAd(context, ad, spec.placement);
  }

  void _onHtmlLink(String url) {
    _clicked = true;
    _ads.recordClick(ad, spec.placement);
    openUrl(url);
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _tickT?.cancel();
    _maxT?.cancel();
    _loadT?.cancel();
    _vc?.dispose();
    _hud.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  // ===================================================================== //
  // UI
  // ===================================================================== //
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: ad.backgroundColor ?? Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _media()),
            // سایه‌ی بالا/پایین برای خوانایی
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                      stops: [0, 0.22, 0.6, 1],
                    ),
                  ),
                ),
              ),
            ),
            if (!_shown)
              const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.6)),
            SafeArea(
              child: ValueListenableBuilder<int>(
                valueListenable: _hud,
                builder: (_, __, ___) => Column(
                  children: [
                    _progressBar(),
                    _topBar(),
                    const Spacer(),
                    _bottom(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _media() {
    final Widget child;
    if (ad.isVideo) {
      final vc = _vc;
      child = Stack(
        fit: StackFit.expand,
        children: [
          if (ad.posterUrl.isNotEmpty) AdImageView(url: ad.posterUrl),
          if (vc != null) AdVideoSurface(controller: vc, cover: vc.value.aspectRatio < 1),
        ],
      );
    } else if (ad.isImage) {
      child = AdImageView(url: ad.mediaUrl, onReady: _begin, onError: _fail);
    } else if (ad.isHtml) {
      child = AdHtmlView(html: ad.html, onLink: _onHtmlLink, onReady: _begin, onError: _fail);
    } else {
      child = const SizedBox.shrink();
    }
    if (ad.isHtml) return child; // خود WebView لمس را مدیریت می‌کند
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: ad.clickable && _shown ? _click : null,
      child: child,
    );
  }

  Widget _progressBar() {
    final v = _shown && _target > 0 ? (_watched / _target).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: v,
        minHeight: 3,
        backgroundColor: Colors.white24,
        color: ad.accentColor ?? Colors.white,
      ),
    );
  }

  Widget _pill(String text, {VoidCallback? onTap, IconData? icon}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, color: Colors.white, size: 15), const SizedBox(width: 4)],
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
    return onTap == null
        ? child
        : RemoteTap(
            onTap: onTap,
            autofocus: true,
            borderRadius: BorderRadius.circular(20),
            child: child,
          );
  }

  int _secLeft(int ms) => math.max(1, (ms / 1000).ceil());

  /// متن/دکمه‌ی شمارش معکوس یا رد کردن
  Widget? _countdown() {
    if (!_shown || _completed) return null;
    if (spec.skippable) {
      final need = spec.skipAfterSec * 1000;
      if (_watched >= need) return _pill('رد کردن', icon: Icons.skip_next_rounded, onTap: _leave);
      if (!spec.showCountdown) return null;
      return _pill('رد کردن بعد از ${faDigits(_secLeft(need - _watched))} ثانیه');
    }
    if (spec.requiredWatchSec > 0) {
      if (_watched >= _required) {
        return _pill(spec.rewarded ? 'ادامه' : 'ادامه ›', onTap: _leave);
      }
      if (!spec.showCountdown) return null;
      return _pill('ادامه بعد از ${faDigits(_secLeft(_required - _watched))} ثانیه');
    }
    if (!spec.showCountdown) return null;
    return _pill('${faDigits(_secLeft(_target - _watched))} ثانیه تا پایان تبلیغ');
  }

  Widget _topBar() {
    final countdown = _countdown();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          _pill(adBadge(ad, _ads.settings)),
          const Spacer(),
          if (countdown != null) countdown,
          if (_showClose) ...[
            const SizedBox(width: 8),
            RemoteTap(
              onTap: _leave,
              autofocus: true,
              circular: true,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottom() {
    final text = ad.textColor ?? Colors.white;
    final accent = ad.accentColor ?? UiPalette.blue;
    final link = spec.link;
    final status = link?.statusText() ?? '';
    final hasText = ad.headline.isNotEmpty || ad.body.isNotEmpty;
    final showCta = ad.clickable && _shown;
    final rewardReady = spec.rewarded && _completed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (spec.rewarded && ad.hasReward)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _pill(
                  _rewardEarned ? 'جایزه آماده است: ${rewardLabel(ad)}' : 'جایزه: ${rewardLabel(ad)}',
                  icon: Icons.card_giftcard_rounded,
                ),
              ),
            ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ad.headline.isNotEmpty)
                    Text(ad.headline,
                        style: TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
                  if (ad.body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(ad.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: text.withValues(alpha: 0.9), fontSize: 14, height: 1.5)),
                    ),
                ],
              ),
            ),
          if (rewardReady)
            _button('دریافت جایزه', accent, _leave)
          else if (showCta)
            _button(ad.ctaText.isEmpty ? 'مشاهده' : ad.ctaText, accent, _click),
          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!(link?.failed() ?? false) && !status.contains('✓'))
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white70),
                    ),
                  if (!(link?.failed() ?? false) && !status.contains('✓')) const SizedBox(width: 8),
                  Text(status, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _button(String label, Color color, VoidCallback onTap) => SizedBox(
        height: 50,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );
}

// ======================================================================= //
// پاپ‌آپ تبلیغاتی (قالب‌های popup و html)
// ======================================================================= //
Future<AdRunResult> showAdPopup(
  BuildContext context,
  AdsManager ads,
  AdItem ad,
  String placement,
) async {
  ads.interruptiveActive = true;
  try {
    final r = await showDialog<AdRunResult>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => _AdPopup(ad: ad, placement: placement),
    );
    return r ?? const AdRunResult(skipped: true);
  } finally {
    ads.interruptiveActive = false;
  }
}

class _AdPopup extends StatefulWidget {
  final AdItem ad;
  final String placement;
  const _AdPopup({required this.ad, required this.placement});

  @override
  State<_AdPopup> createState() => _AdPopupState();
}

class _AdPopupState extends State<_AdPopup> {
  AdItem get ad => widget.ad;
  late final AdsManager _ads;
  Timer? _tick, _auto;
  bool _impressed = false;
  bool _closed = false;
  bool _clicked = false;
  int _elapsed = 0;

  /// بدون دکمه‌ی بستن و بدون زمان خودکار هم کاربر گیر نمی‌افتد
  int get _closeAfterMs => math.max(ad.closeDelaySec, ad.closeButton ? 0 : 3) * 1000;

  bool get _canClose => _elapsed >= _closeAfterMs;

  @override
  void initState() {
    super.initState();
    _ads = adsOf(context);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() => _elapsed += 250);
    });
    final secs = ad.durationSec > 0 ? ad.durationSec : (ad.closeButton ? 0 : 15);
    if (secs > 0) _auto = Timer(Duration(seconds: secs), () => _close(auto: true));
    // بدون رسانه: همین حالا دیده شده
    if (!ad.isImage && !ad.isHtml) _shown();
  }

  void _shown() {
    if (_impressed) return;
    _impressed = true;
    _ads.recordImpression(ad, widget.placement);
  }

  void _close({bool auto = false}) {
    if (_closed || !mounted) return;
    _closed = true;
    if (_impressed) _ads.recordEvent(ad, 'close', widget.placement);
    Navigator.of(context).pop(AdRunResult(shown: _impressed, completed: auto, clicked: _clicked));
  }

  Future<void> _click() async {
    _clicked = true;
    await openAd(context, ad, widget.placement);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final bg = ad.backgroundColor ?? ui.card;
    final fg = ad.textColor ?? ui.label;
    final accent = ad.accentColor ?? UiPalette.blue;
    final hasText = ad.headline.isNotEmpty || ad.body.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canClose) _close();
      },
      child: Dialog(
        backgroundColor: bg,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ad.isImage || ad.isHtml)
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: ad.isHtml ? 1.5 : 1.25,
                        child: ad.isHtml
                            ? AdHtmlView(
                                html: ad.html,
                                onLink: (u) {
                                  _clicked = true;
                                  _ads.recordClick(ad, widget.placement);
                                  openUrl(u);
                                },
                                onReady: _shown,
                                onError: _close,
                              )
                            : GestureDetector(
                                onTap: ad.clickable ? _click : null,
                                child: AdImageView(
                                  url: ad.mediaUrl,
                                  onReady: _shown,
                                  onError: _close,
                                ),
                              ),
                      ),
                      PositionedDirectional(
                        top: 10,
                        start: 10,
                        child: _tag(adBadge(ad, _ads.settings)),
                      ),
                      if (ad.closeButton && _canClose)
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: _closeBtn(),
                        ),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Row(
                      children: [
                        _tag(adBadge(ad, _ads.settings), dark: false),
                        const Spacer(),
                        if (ad.closeButton && _canClose) _closeBtn(dark: false),
                      ],
                    ),
                  ),
                if (hasText || ad.clickable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (ad.iconUrl.isNotEmpty && !(ad.isImage || ad.isHtml))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: AdImageView(url: ad.iconUrl, onReady: _shown),
                                ),
                              ),
                            ),
                          ),
                        if (ad.headline.isNotEmpty)
                          Text(ad.headline,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
                        if (ad.body.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(ad.body,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 14, height: 1.7)),
                          ),
                        if (ad.clickable) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _click,
                              child: Text(ad.ctaText.isEmpty ? 'مشاهده' : ad.ctaText,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            ),
                          ),
                        ],
                        if (!ad.closeButton && _canClose)
                          TextButton(
                            onPressed: _close,
                            child: Text('بستن', style: TextStyle(color: fg.withValues(alpha: 0.6))),
                          ),
                      ],
                    ),
                  )
                else if (!ad.closeButton && _canClose)
                  TextButton(onPressed: _close, child: const Text('بستن')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String t, {bool dark = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: dark ? Colors.black.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t,
            style: TextStyle(
                color: dark ? Colors.white : (ad.textColor ?? context.ui.secondary),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  Widget _closeBtn({bool dark = true}) => RemoteTap(
        onTap: _close,
        autofocus: true,
        circular: true,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: dark ? Colors.black.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.close_rounded,
              size: 19, color: dark ? Colors.white : (ad.textColor ?? context.ui.label)),
        ),
      );
}
