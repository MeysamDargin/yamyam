import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/models/vpn_status.dart';
import 'package:yamyam/platform/desktop_platform.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/widgets/remote_tap.dart';

/// اتصال و قطع با دستگیره‌ی کشویی.
///
/// - گوشی، خاموش: دستگیره در ابتدای مسیر؛ با کشیدن تا ~۸۰٪ (یا یک حرکت سریع) وصل می‌شود.
/// - گوشی، روشن: دستگیره در انتهای مسیر؛ برای قطع، به عقب کشیده می‌شود.
/// - در حال اتصال: لمس دستگیره، اتصال را لغو می‌کند.
/// - اندروید تی‌وی: دکمه‌ی انتخاب ریموت مستقیم تغییر می‌دهد.
/// - دسکتاپ (ویندوز، لینوکس، مک): یک کلیک موس دستگیره را تا انتهای مسیر می‌برد و وضعیت را عوض می‌کند.
/// - روی گوشی، لمس ساده فقط یک تکان راهنما می‌دهد تا کاربر بداند باید بکشد.
///
/// جزئیات ظاهری: مسیر شیشه‌ای با براق، رنگ جاری پشت دستگیره با هاله و برق متحرک،
/// کشیدگی دستگیره بر اساس سرعت (مثل ژله)، متن راهنمای درخشان، فلش‌های جهت‌دار،
/// حلقه‌ی چرخان هنگام اتصال و موج انفجاری بعد از اتصال موفق.
class SlidePower extends StatefulWidget {
  final VpnStatus status;
  final Color colorA, colorB;
  final bool dark;
  final String idleText, onText, busyText;

  /// ۰ = خاموش … ۱ = روشن.
  final ValueNotifier<double>? progress;

  /// وقتی حرکت کامل شد (یا لغو در حال اتصال). تا پایان جریان، دستگیره در مقصد می‌ماند.
  final Future<void> Function() onToggle;
  final bool autofocus;

  const SlidePower({
    super.key,
    required this.status,
    required this.colorA,
    required this.colorB,
    required this.dark,
    required this.onToggle,
    this.idleText = 'بکشید تا وصل شوید',
    this.onText = 'برای قطع، به عقب بکشید',
    this.busyText = 'در حال اتصال…',
    this.progress,
    this.autofocus = false,
  });

  @override
  State<SlidePower> createState() => _SlidePowerState();
}

class _SlidePowerState extends State<SlidePower> with TickerProviderStateMixin {
  static const _h = 84.0;
  static const _knob = 70.0;
  static const _pad = 7.0;
  // کمی فنری‌تر از قبل: هنگام جا افتادن کمی رد می‌شود و برمی‌گردد
  static const _spring = SpringDescription(mass: 1, stiffness: 300, damping: 24);

  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: _rest);
  late final AnimationController _wiggle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _sheen =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  late final AnimationController _burst =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  double _travel = 200;
  double _width = 300;
  bool _dragging = false;
  bool _busy = false; // حرکت کامل شده و جریان اتصال/قطع در حال اجراست
  int _tick = 0;
  double _dragVel = 0; // سرعت کشیدن (کسر مسیر بر ثانیه) برای کشیدگی دستگیره

  double get _rest => widget.status == VpnStatus.disconnected ? 0 : 1;
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => widget.progress?.value = _c.value.clamp(0.0, 1.0));
    _sheen.addListener(() => _dragVel *= 0.9);
  }

  @override
  void didUpdateWidget(SlidePower old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) {
      if (widget.status == VpnStatus.connected) _burst.forward(from: 0);
      if (!_dragging) _settle();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _wiggle.dispose();
    _sheen.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _springTo(double target, [double velocity = 0]) {
    _c.animateWith(SpringSimulation(_spring, _c.value, target, velocity));
  }

  void _settle() => _springTo(_rest);

  Future<void> _fire() async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.onToggle();
    } finally {
      _busy = false;
      if (mounted && !_dragging) _settle();
    }
  }

  // ---------- کشیدن ----------
  void _onStart(DragStartDetails d) {
    if (_busy) return;
    _dragging = true;
    _tick = 0;
    _c.stop();
    HapticFeedback.selectionClick();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final sign = _rtl ? -1.0 : 1.0;
    final dx = d.delta.dx * sign;
    final v = (_c.value + dx / _travel).clamp(0.0, 1.0);
    _c.value = v;
    _dragVel = _dragVel * 0.6 + (dx / _travel * 60) * 0.4;
    final step = (v * 4).floor();
    if (step != _tick && step < 4) {
      _tick = step;
      HapticFeedback.selectionClick();
    }
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final vel = (d.primaryVelocity ?? 0) * (_rtl ? -1 : 1) / _travel; // کسر بر ثانیه
    final wasOn = _rest == 1;
    final t = _c.value;
    // کلیک موس اغلب یکی‌دو پیکسل جابه‌جا می‌شود و به‌جای لمس، کشیدنِ کوتاه حساب می‌شود.
    final movedPx = (t - (wasOn ? 1.0 : 0.0)).abs() * _travel;
    if (isDesktopPlatform(context) && movedPx < 12) {
      HapticFeedback.mediumImpact();
      _springTo(wasOn ? 0 : 1);
      _fire();
      return;
    }
    final done = wasOn ? (t < 0.2 || (t < 0.6 && vel < -2.2)) : (t > 0.8 || (t > 0.4 && vel > 2.2));
    if (done) {
      HapticFeedback.mediumImpact();
      _springTo(wasOn ? 0 : 1, vel);
      _fire();
    } else {
      _springTo(_rest, vel);
    }
  }

  void _onCancel() {
    if (!_dragging) return;
    _dragging = false;
    _settle();
  }

  // ---------- لمس ----------
  void _onTap() {
    if (_busy) return;
    final st = widget.status;
    if (st == VpnStatus.connecting || TvPlatform.isTv || isDesktopPlatform(context)) {
      HapticFeedback.selectionClick();
      _springTo(st == VpnStatus.disconnected ? 1 : 0);
      _fire();
      return;
    }
    // گوشی: فقط راهنمایی
    HapticFeedback.selectionClick();
    _wiggle.forward(from: 0);
  }

  // ---------- ظاهر ----------
  @override
  Widget build(BuildContext context) {
    final connecting = widget.status == VpnStatus.connecting;
    const secondary = Color(0xFF8E8E93);

    return Semantics(
      button: true,
      label: widget.status == VpnStatus.disconnected ? 'اتصال' : 'قطع اتصال',
      onTap: () {
        _springTo(widget.status == VpnStatus.disconnected ? 1 : 0);
        _fire();
      },
      child: RemoteTap(
        onTap: _onTap,
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(_h / 2),
        child: MouseRegion(
          cursor: isDesktopPlatform(context) ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onStart,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            onHorizontalDragCancel: _onCancel,
            child: SizedBox(
              width: double.infinity,
              height: _h,
              child: LayoutBuilder(builder: (context, box) {
                _width = box.maxWidth;
                _travel = math.max(1, box.maxWidth - _knob - 2 * _pad);
                return AnimatedBuilder(
                  animation: Listenable.merge([_c, _wiggle, _sheen, _burst]),
                  builder: (_, __) {
                    final p = _c.value.clamp(0.0, 1.0);
                    final nudge = 0.14 * math.sin(math.pi * _wiggle.value) * (1 - p);
                    final pos = (_c.value + nudge).clamp(-0.05, 1.05);
                    final knobStart = _pad + _travel * pos;
                    return Stack(
                      clipBehavior: Clip.none,
                      fit: StackFit.expand,
                      children: [
                        _track(p),
                        _fill(knobStart, p, connecting),
                        _gloss(p),
                        _hintLayer(connecting, p, secondary),
                        _ripples(knobStart),
                        _knobWidget(knobStart, connecting, p, secondary),
                      ],
                    );
                  },
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  /// بدنه‌ی مسیر: سطح شیشه‌ای با گرادیان عمودی، لبه‌ی نازک و هاله‌ی رنگی که با پیشرفت پررنگ می‌شود.
  Widget _track(double p) {
    final dark = widget.dark;
    final top = dark ? const Color(0xFF232327) : Colors.white;
    final bottom = dark ? const Color(0xFF121214) : const Color(0xFFE6E6EE);
    final edge = dark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.07);
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ),
          borderRadius: BorderRadius.circular(_h / 2),
          border: Border.all(
            color: Color.lerp(edge, widget.colorB.withValues(alpha: 0.75), p * 0.7)!,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.colorB.withValues(alpha: (dark ? 0.55 : 0.38) * p),
              blurRadius: 40,
              spreadRadius: -6,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.55 : 0.07),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      ),
    );
  }

  /// رنگِ جاری پشت دستگیره: گرادیان، هاله‌ی نورانی در لبه‌ی پیشرو و برق متحرک.
  Widget _fill(double knobStart, double p, bool connecting) {
    final fillW = math.max(0.0, knobStart + _knob + _pad);
    final opacity = connecting ? 1.0 : (p * 5).clamp(0.0, 1.0);
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_h / 2),
        child: Opacity(
          opacity: opacity,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: fillW,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: AlignmentDirectional.centerStart,
                            end: AlignmentDirectional.centerEnd,
                            colors: [widget.colorB, widget.colorA],
                          ),
                        ),
                      ),
                    ),
                    // هاله‌ی روشن لبه‌ی پیشرو (مثل دنباله‌ی ستاره‌ی دنباله‌دار)
                    PositionedDirectional(
                      end: -10,
                      top: 0,
                      bottom: 0,
                      width: 110,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: AlignmentDirectional.centerEnd.resolve(Directionality.of(context)),
                            radius: 0.9,
                            colors: [
                              Colors.white.withValues(alpha: 0.38),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // برق متحرک روی سطح رنگ‌شده
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: _sheen.value * (fillW + 160) - 120,
                      child: Opacity(
                        opacity: connecting ? 0.7 : 0.3,
                        child: Container(
                          width: 90,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.5),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
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
    );
  }

  /// براقِ نیمه‌ی بالای مسیر (حس شیشه)
  Widget _gloss(double p) {
    final a = widget.dark ? 0.05 + 0.10 * p : 0.40 + 0.10 * p;
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_h / 2),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: _h * 0.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: a), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hintLayer(bool connecting, double p, Color secondary) {
    final on = p > 0.5;
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: on ? 24 : _knob + _pad * 2 + 6,
          end: on ? _knob + _pad * 2 + 6 : 20,
        ),
        child: Center(child: _hint(connecting, p, secondary)),
      ),
    );
  }

  /// متن با درخششِ متحرک؛ جهتِ حرکت درخشش با جهتِ کشیدن یکی است.
  Widget _shimmer(String text, Color base, Color hi, {required bool towardEnd}) {
    // «به سمت انتها» در RTL یعنی به چپ
    final leftToRight = towardEnd != _rtl;
    final s = leftToRight ? _sheen.value : 1 - _sheen.value;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment(-2 + 4 * s, 0),
        end: Alignment(-1 + 4 * s, 0),
        colors: [base, hi, base],
        stops: const [0, 0.5, 1],
      ).createShader(r),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'IRANYekan',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _hint(bool connecting, double p, Color secondary) {
    if (connecting) {
      return _fit(_shimmer(widget.busyText, Colors.white.withValues(alpha: 0.7), Colors.white,
          towardEnd: true));
    }
    final onLabel = isDesktopPlatform(context) ? 'برای قطع کلیک کنید' : widget.onText;
    final idleLabel = isDesktopPlatform(context) ? 'کلیک کنید تا وصل شوید' : widget.idleText;
    if (widget.status != VpnStatus.disconnected && p > 0.5) {
      return Opacity(
        opacity: ((p - 0.5) * 2).clamp(0.0, 1.0),
        child: _fit(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chevrons(Colors.white, forward: false),
            const SizedBox(width: 8),
            _shimmer(onLabel, Colors.white.withValues(alpha: 0.75), Colors.white,
                towardEnd: false),
          ],
        )),
      );
    }
    final fade = (1 - p * 1.8).clamp(0.0, 1.0);
    final hi = widget.dark ? Colors.white : const Color(0xFF1C1C1E);
    return Opacity(
      opacity: fade,
      child: _fit(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _shimmer(idleLabel, secondary, hi, towardEnd: true),
          const SizedBox(width: 4),
          _chevrons(secondary, forward: true),
        ],
      )),
    );
  }

  /// متن را در عرضِ باقی‌مانده جا می‌دهد تا روی مسیر باریک سرریز نکند.
  Widget _fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, child: child);

  /// سه فلش که موج‌وار پررنگ می‌شوند و جهت کشیدن را نشان می‌دهند.
  Widget _chevrons(Color color, {required bool forward}) {
    final icon = forward == _rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;
    final s = _sheen.value * 2; // موج سریع‌تر از درخشش متن
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Opacity(
            opacity: 0.2 +
                0.8 *
                    math.pow(
                      (math.sin(((forward ? s - i * 0.14 : s + i * 0.14)) * 2 * math.pi) + 1) / 2,
                      1.6,
                    ),
            // textDirection ثابت: چون chevron در RTL خودکار آینه می‌شود و جهت را برعکس می‌کرد
            child: Icon(icon, size: 18, color: color, textDirection: TextDirection.ltr),
          ),
      ],
    );
  }

  /// موج‌های پخش‌شونده از دستگیره بعد از اتصال موفق
  Widget _ripples(double knobStart) {
    final t = _burst.value;
    // مهم: همیشه Positioned برگردان؛ فرزند غیر‌Positioned صفر‌در‌صفر، کل Stack را جمع می‌کرد
    if (t <= 0 || t >= 1) return const Positioned.fill(child: SizedBox.shrink());
    Widget ring(double delay) {
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) return const SizedBox.shrink();
      final k = Curves.easeOutCubic.transform(p);
      final size = _knob + 120 * k;
      return PositionedDirectional(
        start: knobStart + _knob / 2 - size / 2,
        top: _h / 2 - size / 2,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.colorB.withValues(alpha: (1 - p) * 0.55),
                width: 3 * (1 - p) + 0.5,
              ),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: Stack(clipBehavior: Clip.none, children: [ring(0), ring(0.2)]),
    );
  }

  Widget _knobWidget(double start, bool connecting, double p, Color secondary) {
    const outer = _knob + 20.0;
    final lift = _dragging ? 3.0 : 0.0;
    // کشیدگی ژله‌ای بر اساس سرعت
    final v = _dragging ? _dragVel : _c.velocity;
    final stretch = (v.abs() * 0.035).clamp(0.0, 0.14);
    final connected = widget.status == VpnStatus.connected;

    return PositionedDirectional(
      start: start - 10,
      top: _pad - 10 - lift / 2,
      child: SizedBox(
        width: outer,
        height: outer,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // هاله‌ی نورانی زیر دستگیره
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.colorB.withValues(alpha: (widget.dark ? 0.55 : 0.40) * p),
                    widget.colorB.withValues(alpha: 0),
                  ],
                ),
              ),
              child: const SizedBox(width: outer, height: outer),
            ),
            // حلقه‌ی چرخان هنگام اتصال
            if (connecting)
              CustomPaint(
                size: const Size(outer - 2, outer - 2),
                painter: _RingPainter(
                  angle: _sheen.value * 2 * math.pi * 2,
                  color: Colors.white,
                ),
              ),
            AnimatedScale(
              scale: _dragging ? 1.07 : 1.0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(1 + stretch, 1 - stretch * 0.5, 1),
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Color(0xFFECECF1)],
                    ),
                    border: Border.all(
                      color: widget.colorB.withValues(alpha: 0.55 * p),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: widget.dark ? 0.6 : 0.17 + 0.06 * p),
                        blurRadius: 18 + 6 * p + lift * 2,
                        offset: Offset(0, 7 + lift),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: RotationTransition(
                        turns: Tween(begin: -0.15, end: 0.0).animate(anim),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                    ),
                    child: connected && p > 0.6
                        ? Icon(
                            Icons.verified_user_rounded,
                            key: const ValueKey('on'),
                            size: 31,
                            color: widget.colorB,
                          )
                        : Icon(
                            Icons.power_settings_new_rounded,
                            key: const ValueKey('off'),
                            size: 32,
                            color: Color.lerp(secondary, widget.colorB, p),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// حلقه‌ی چرخان با دُم محو (هنگام اتصال دور دستگیره می‌چرخد)
class _RingPainter extends CustomPainter {
  final double angle;
  final Color color;
  _RingPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const sweep = math.pi * 1.4;
    canvas.drawArc(
      rect,
      angle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: sweep,
          colors: [color.withValues(alpha: 0), color],
          transform: GradientRotation(angle),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.angle != angle || old.color != color;
}