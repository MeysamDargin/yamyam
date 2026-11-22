import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/ads/ad_flow.dart';
import 'package:yamyam/screen/home.dart';
import 'package:yamyam/state/app_scope.dart';
import 'package:yamyam/widgets/remote_tap.dart';

/// اسپلش «Yam Yam» — هم‌سبک با وب‌سایت (بلاب‌های زنده، چیپ‌های شناور، نوار متحرک، فنر)
///
/// پس‌زمینه همیشه سفید است.
///
/// داستان انیمیشن:
///  ۱) بلاب سبز با فنر باز می‌شود و مدام شکل عوض می‌کند، بلاب زرد داخلش می‌نشیند
///  ۲) حروف YAM YAM با فنر و چرخش بالا می‌پرند
///  ۳) سه چیپ (رمزنگاری / سرعت / نامحدود) پرتاب می‌شوند و شناورند، نوار مارکی از پایین می‌آید
///  ۴) همه‌چیز جمع می‌شود و محو می‌شود (پس‌زمینه سفید می‌ماند)
///  ۵) لوگو وسط صفحه با فنر ظاهر می‌شود + موج رنگی
///  ۶) شعار با ماسک نرم آشکار می‌شود
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  // ⚠️ مسیر لوگو — این را با مسیر عکس خودتان عوض کنید و در pubspec.yaml اضافه کنید
  static const _logoAsset = 'assets/images/logo.png';

  static const _tagline = 'اینترنت آزاد، پایدار و امن';
  static const _marquee = ['رایگان', 'پرسرعت', 'پایدار', 'بدون قطعی', 'بدون محدودیت'];
  static const _total = Duration(milliseconds: 5200);

  // پالت وب‌سایت
  static const _ink = Color(0xFF12241F);
  static const _yel = Color(0xFFFFD23F);
  static const _yelInk = Color(0xFF3A2C00);
  static const _grn = Color(0xFF1F5C4A);
  static const _cor = Color(0xFFFF7A59);
  static const _mute = Color(0xFF5B6B63);

  // کلیدفریم‌های مورف بلاب: [۴ شعاع افقی tl,tr,br,bl] + [۴ شعاع عمودی]
  static const _kf = [
    [58.0, 42.0, 61.0, 39.0, 45.0, 55.0, 45.0, 55.0],
    [40.0, 60.0, 45.0, 55.0, 60.0, 40.0, 60.0, 40.0],
    [62.0, 38.0, 38.0, 62.0, 38.0, 62.0, 52.0, 48.0],
  ];

  late final AnimationController _c;
  final _fired = <int>{};
  bool _navigated = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total)
      ..addListener(_haptics)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          Future.delayed(const Duration(milliseconds: 400), _goHome);
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _haptics() {
    final t = _c.value;
    if (t >= 0.04 && _fired.add(0)) HapticFeedback.lightImpact();
    if (t >= 0.20 && _fired.add(1)) HapticFeedback.selectionClick();
    if (t >= 0.38 && _fired.add(2)) HapticFeedback.selectionClick();
    if (t >= 0.74 && _fired.add(3)) HapticFeedback.mediumImpact();
  }

  /// تبلیغ اسپلش (اگر تعریف شده) و بعد صفحه‌ی اصلی.
  Future<void> _goHome() async {
    if (_navigated || _leaving || !mounted) return;
    _leaving = true;
    try {
      final c = AppScope.of(context, listen: false);
      // تبلیغات فقط از پاسخ تازه‌ی پنل می‌آیند (بدون کش)؛ اگر پنل کند بود بدون تبلیغ ادامه بده
      await c.adsReady.timeout(const Duration(milliseconds: 2000), onTimeout: () {});
      if (mounted) await AdFlow.showSplash(context, c);
    } catch (_) {
      // تبلیغ هیچ‌وقت نباید ورود به اپ را خراب کند
    }
    if (!mounted) return;
    _enterHome();
  }

  void _enterHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (_, __, ___) => const HomePage(),
        transitionsBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 1.05, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  // ---------- ابزارهای انیمیشن ----------
  double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  /// فنر میرای واقعی (۰ → ۱ با اندکی بیش‌پرش)
  double _spring(double x, {double zeta = 0.5, double freq = 2.0}) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    final w = 2 * math.pi * freq;
    final wd = w * math.sqrt(1 - zeta * zeta);
    final e = math.exp(-zeta * w * x);
    return 1 - e * (math.cos(wd * x) + (zeta * w / wd) * math.sin(wd * x));
  }

  /// شعاع‌های بیضوی بلاب (مثل border-radius چندمقداری CSS)
  BorderRadius _blob(double phase, double w) {
    final p = phase % 3;
    final i = p.floor();
    final f = Curves.easeInOut.transform(p - i);
    final a = _kf[i];
    final b = _kf[(i + 1) % 3];
    double v(int k) => a[k] + (b[k] - a[k]) * f;
    Radius r(int h, int vv) =>
        Radius.elliptical(w * v(h) / 100, w * v(vv) / 100);
    return BorderRadius.only(
      topLeft: r(0, 4),
      topRight: r(1, 5),
      bottomRight: r(2, 6),
      bottomLeft: r(3, 7),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = math.min(size.width * 0.8, 340.0);

    return RemoteTap(
      onTap: _goHome,
      autofocus: true,
      ring: false,
      child: Scaffold(
        backgroundColor: Colors.white, // همیشه سفید
        body: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            return SizedBox.expand(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: SizedBox(
                        width: s,
                        height: s,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            _blobs(t, s),
                            _face(t, s),
                            _chips(t, s),
                            _logoReveal(t, s),
                            _taglineView(t, s),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _strip(t, size),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------- بلاب سبز + زرد ----------
  Widget _blobs(double t, double s) {
    final pop = _spring(_seg(t, 0.0, 0.28), zeta: 0.45, freq: 1.6);
    final exit = Curves.easeInBack.transform(_seg(t, 0.60, 0.74));
    final scale = (pop * (1 - exit)).clamp(0.0, 2.0);
    if (scale <= 0.001) return const SizedBox.shrink();

    final innerPop = _spring(_seg(t, 0.08, 0.34), zeta: 0.5, freq: 1.5);
    final outerR = _blob(t * 3, s);
    final innerR = _blob(3 - t * 3, s);
    final rot = math.sin(t * 2 * math.pi * 1.2) * 0.06;

    return Transform.scale(
      scale: scale,
      child: Transform.rotate(
        angle: rot,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: s * 0.88,
              height: s * 0.88,
              decoration: BoxDecoration(color: _grn, borderRadius: outerR),
            ),
            Transform.scale(
              scale: innerPop,
              child: Container(
                width: s * 0.62,
                height: s * 0.62,
                decoration: BoxDecoration(color: _yel, borderRadius: innerR),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- متن YAM YAM داخل بلاب ----------
  Widget _face(double t, double s) {
    final exit = 1 - Curves.easeIn.transform(_seg(t, 0.58, 0.68));
    if (exit <= 0) return const SizedBox.shrink();

    final small = Curves.easeOut.transform(_seg(t, 0.44, 0.54));

    return Opacity(
      opacity: exit,
      child: Transform.scale(
        scale: 0.8 + 0.2 * exit,
        child: Transform.rotate(
          angle: -0.105,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) _letter(i, 'YAM'[i], t, s),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      _letter(i + 3, 'YAM'[i], t, s),
                  ],
                ),
                Opacity(
                  opacity: small,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'FREE VPN',
                      style: TextStyle(
                        fontSize: s * 0.052,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                        color: _yelInk,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _letter(int i, String ch, double t, double s) {
    final start = 0.18 + i * 0.03;
    final x = _seg(t, start, start + 0.28);
    final sp = _spring(x, zeta: 0.4, freq: 1.7);
    final dir = i.isEven ? 1.0 : -1.0;

    final idle = Curves.easeInOut.transform(_seg(t, 0.42, 0.52));
    final wave = -3.0 * idle * math.sin(2 * math.pi * (t * 4.0 - i * 0.14));

    final dy = 44 * (1 - sp) + wave;
    final rot = dir * 0.4 * (1 - sp);
    final opacity = Curves.easeOut.transform(_seg(x, 0, 0.3));

    return Opacity(
      opacity: opacity,
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.translationValues(0, dy, 0)
          ..rotateZ(rot)
          ..scale(0.7 + 0.3 * sp, 0.45 + 0.55 * sp),
        child: Text(
          ch,
          style: TextStyle(
            fontSize: s * 0.2,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            color: _yelInk,
          ),
        ),
      ),
    );
  }

  // ---------- چیپ‌های شناور ----------
  Widget _chips(double t, double s) {
    final exit = (1 - Curves.easeInBack.transform(_seg(t, 0.56, 0.66)))
        .clamp(0.0, 2.0);
    if (exit <= 0.001) return const SizedBox.shrink();

    Widget chip(String text, Color bg, Color fg, bool border, double start,
        double phase, double rot0) {
      final sp = _spring(_seg(t, start, start + 0.2), zeta: 0.42, freq: 1.7);
      if (sp <= 0) return const SizedBox.shrink();
      final bob = -9 * math.sin(2 * math.pi * (t * 4.2 + phase));
      return Transform.translate(
        offset: Offset(0, bob),
        child: Transform.rotate(
          angle: rot0 * (1 - sp) + 0.035 * math.sin(2 * math.pi * (t * 4.2 + phase)),
          child: Transform.scale(
            scale: sp * exit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: border ? Border.all(color: _ink, width: 2) : null,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: s * 0.02,
            right: -s * 0.06,
            child: chip('🔒 رمزنگاری کامل', Colors.white, _ink, true, 0.34, 0.0, 0.5),
          ),
          Positioned(
            bottom: s * 0.14,
            left: -s * 0.08,
            child: chip('⚡ اتصال در ۲ ثانیه', _cor, Colors.white, false, 0.40, 0.4, -0.5),
          ),
          Positioned(
            bottom: -s * 0.02,
            right: s * 0.1,
            child: chip('∞ حجم نامحدود', _yel, _yelInk, false, 0.46, 0.7, 0.4),
          ),
        ],
      ),
    );
  }

  // ---------- نوار متحرک ----------
  Widget _strip(double t, Size size) {
    final inP = Curves.easeOutBack.transform(_seg(t, 0.26, 0.44));
    final outP = Curves.easeInCubic.transform(_seg(t, 0.56, 0.68));
    if (inP <= 0 || outP >= 1) return const SizedBox.shrink();

    const slot = 130.0;
    final loop = slot * _marquee.length;
    final shift = (t * 5200 / 1000 * 70) % loop; // ۷۰ پیکسل بر ثانیه
    final dy = (1 - inP) * 220 + outP * 260;

    return Positioned(
      left: -30,
      right: -30,
      bottom: size.height * 0.11,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Transform.rotate(
          angle: -0.021,
          child: Container(
            color: _ink,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: ClipRect(
              child: SizedBox(
                height: 30,
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: Transform.translate(
                    offset: Offset(shift - loop, 0),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var r = 0; r < 8; r++)
                            for (var i = 0; i < _marquee.length; i++)
                              SizedBox(
                                width: slot,
                                child: Center(
                                  child: Text(
                                    _marquee[i],
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: i.isOdd ? _yel : const Color(0xFFFBF5E6),
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- لوگوی پایانی وسط صفحه ----------
  Widget _logoReveal(double t, double s) {
    final p = _seg(t, 0.72, 0.94);
    if (p <= 0) return const SizedBox.shrink();

    final sp = _spring(p, zeta: 0.5, freq: 1.5);
    final fade = Curves.easeOut.transform(_seg(p, 0, 0.3));
    final logo = s * 0.5;

    Widget ring(double a, double b, Color color, double alpha) {
      final q = _seg(t, a, b);
      if (q <= 0 || q >= 1) return const SizedBox.shrink();
      final d = logo + 260 * Curves.easeOutCubic.transform(q);
      return OverflowBox(
        maxWidth: 900,
        maxHeight: 900,
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity((1 - q) * alpha),
              width: 2.4 * (1 - q) + 0.5,
            ),
          ),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        ring(0.72, 0.96, _yel, 0.9),
        ring(0.78, 1.0, _grn, 0.5),
        ring(0.84, 1.0, _cor, 0.4),
        Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: sp,
            child: Transform.rotate(
              angle: -0.14 * (1 - sp),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(logo * 0.24),
                child: Image.asset(
                  _logoAsset,
                  width: logo,
                  height: logo,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: logo,
                    height: logo,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: _yel,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(99),
                        topRight: Radius.circular(99),
                        bottomRight: Radius.circular(99),
                        bottomLeft: Radius.circular(99),
                      ),
                    ),
                    child: const Text(
                      'Y',
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        color: _yelInk,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- شعار با ماسک نرم ----------
  Widget _taglineView(double t, double s) {
    final r = Curves.easeInOutCubic.transform(_seg(t, 0.80, 0.97));
    final fade = Curves.easeOut.transform(_seg(t, 0.80, 0.88));
    if (fade <= 0) return const SizedBox.shrink();
    final a = (r * 1.4 - 0.4).clamp(0.0, 1.0);
    final b = (r * 1.4).clamp(0.0, 1.0);

    return Positioned(
      left: -60,
      right: -60,
      bottom: -s * 0.02,
      child: Center(
        child: Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - fade)),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: const [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                  Colors.transparent,
                ],
                stops: [0, a, b, 1],
              ).createShader(rect),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: const Text(
                  _tagline,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _mute,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}