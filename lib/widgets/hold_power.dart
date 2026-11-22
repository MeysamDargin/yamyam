import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/models/vpn_status.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/widgets/remote_tap.dart';

/// روشن/خاموش کردن با «نگه‌داشتن»: انگشت را روی گوی نگه دارید تا حلقه پر شود.
///
/// - خاموش: نگه‌داشتن کوتاه (~۰٫۸۵ث) → اتصال
/// - روشن: نگه‌داشتن کمی طولانی‌تر (~۱٫۱۵ث) → قطع (اشتباهی سخت‌تر است)
/// - در حال اتصال: لمس = لغو
/// - تی‌وی / دسترسی‌پذیری: انتخاب ریموت مستقیم تغییر می‌دهد
/// - لمس کوتاه روی گوشی فقط یک تکان راهنما می‌دهد
class HoldPower extends StatefulWidget {
  final VpnStatus status;
  final Color colorA, colorB, connectedColor;
  final bool dark, gold;
  final AnimationController spin, burst, breathe;
  final Future<void> Function() onToggle;
  final bool autofocus;

  /// ۰..۱ پیشرفت نگه‌داشتن (برای هماهنگی با پس‌زمینه‌ی صفحه)
  final ValueNotifier<double>? progress;

  const HoldPower({
    super.key,
    required this.status,
    required this.colorA,
    required this.colorB,
    required this.connectedColor,
    required this.dark,
    required this.spin,
    required this.burst,
    required this.breathe,
    required this.onToggle,
    this.gold = false,
    this.progress,
    this.autofocus = false,
  });

  @override
  State<HoldPower> createState() => _HoldPowerState();
}

class _HoldPowerState extends State<HoldPower> with TickerProviderStateMixin {
  static const _spring = SpringDescription(mass: 1, stiffness: 380, damping: 28);

  late final AnimationController _hold =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  late final AnimationController _wiggle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);

  bool _pressing = false;
  bool _busy = false;
  int _tick = 0;
  int _pointer = 0;
  Timer? _arm; // تأخیر کوتاه تا لمس سریع، شارژ نشود

  bool get _connected => widget.status == VpnStatus.connected;
  bool get _connecting => widget.status == VpnStatus.connecting;
  bool get _active => widget.status != VpnStatus.disconnected;

  Duration get _holdDuration =>
      _connected ? const Duration(milliseconds: 1150) : const Duration(milliseconds: 850);

  @override
  void initState() {
    super.initState();
    _hold.addListener(_onHoldTick);
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed && _pressing && !_busy) _fire();
    });
  }

  @override
  void didUpdateWidget(HoldPower old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status && !_pressing) {
      _hold.value = 0;
      widget.progress?.value = 0;
    }
  }

  @override
  void dispose() {
    _arm?.cancel();
    _hold.removeListener(_onHoldTick);
    _hold.dispose();
    _wiggle.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onHoldTick() {
    final v = _hold.value.clamp(0.0, 1.0);
    widget.progress?.value = v;
    final step = (v * 4).floor();
    if (_pressing && step != _tick && step < 4) {
      _tick = step;
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _fire() async {
    if (_busy) return;
    _busy = true;
    HapticFeedback.mediumImpact();
    try {
      await widget.onToggle();
    } finally {
      _busy = false;
      if (mounted) {
        _hold.value = 0;
        widget.progress?.value = 0;
      }
    }
  }

  void _armHold() {
    if (_busy) return;
    if (_connecting) {
      HapticFeedback.selectionClick();
      _fire();
      return;
    }
    _arm?.cancel();
    // ~۱۲۰ms صبر: لمس کوتاه فقط راهنما می‌دهد، نگه‌داشتن واقعی شارژ را شروع می‌کند
    _arm = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _busy) return;
      _pressing = true;
      _tick = 0;
      _hold.duration = _holdDuration;
      _hold.forward(from: 0);
    });
  }

  void _endHold({required bool completed}) {
    final armed = _arm?.isActive == true;
    _arm?.cancel();
    _arm = null;
    if (!_pressing) {
      // انگشت زود برداشته شد → راهنمای «نگه دارید»
      if (armed && !_busy && !_connecting && !TvPlatform.isTv) {
        HapticFeedback.selectionClick();
        _wiggle.forward(from: 0);
      }
      return;
    }
    _pressing = false;
    if (!completed && _hold.value < 0.98) {
      _hold.animateWith(SpringSimulation(_spring, _hold.value, 0, -2));
    }
  }

  void _onTap() {
    if (_busy) return;
    if (_connecting || TvPlatform.isTv) {
      HapticFeedback.selectionClick();
      _fire();
      return;
    }
    // روی گوشی، راهنما از _endHold می‌آید تا با Listener دوبار نشود
  }

  String get _hint {
    if (_connecting) return 'برای لغو، لمس کنید';
    if (_connected) return 'برای قطع، نگه دارید';
    return 'برای اتصال، نگه دارید';
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.dark ? const Color(0xFF1C1C1E) : Colors.white;
    final secondary = const Color(0xFF8E8E93);
    final label = widget.dark ? Colors.white : const Color(0xFF1C1C1E);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: widget.status == VpnStatus.disconnected ? 'اتصال' : 'قطع اتصال',
          onTap: _onTap,
          child: RemoteTap(
            onTap: _onTap,
            autofocus: widget.autofocus,
            circular: true,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                if (TvPlatform.isTv) return;
                _pointer = e.pointer;
                _armHold();
              },
              onPointerUp: (e) {
                if (e.pointer != _pointer) return;
                _endHold(completed: _hold.value >= 0.98);
              },
              onPointerCancel: (e) {
                if (e.pointer != _pointer) return;
                _endHold(completed: false);
              },
              child: AnimatedBuilder(
                animation: Listenable.merge(
                    [_hold, _wiggle, _pulse, widget.spin, widget.burst, widget.breathe]),
                builder: (_, __) => _orb(card, secondary),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            _hint,
            key: ValueKey(_hint),
            style: TextStyle(
              fontFamily: kAppFont,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: secondary,
              letterSpacing: -0.1,
            ),
          ),
        ),
        // راهنمای لمس کوتاه
        AnimatedBuilder(
          animation: _wiggle,
          builder: (_, __) {
            final show = _wiggle.isAnimating || (_wiggle.value > 0 && _wiggle.value < 1);
            if (!show) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Opacity(
                opacity: (1 - (_wiggle.value - 0.5).abs() * 2).clamp(0.0, 1.0),
                child: Text(
                  'انگشت را نگه دارید',
                  style: TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: label.withValues(alpha: 0.7),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _orb(Color card, Color secondary) {
    final pre = _active ? 0.0 : _hold.value;
    final holding = _pressing || pre > 0.01;
    final disconnectHold = _connected ? _hold.value : 0.0;
    final glow = _active || holding;
    final nudge = 0.028 * math.sin(math.pi * _wiggle.value);
    final pulse = _active ? 0.0 : 0.012 * (0.5 + 0.5 * math.sin(math.pi * _pulse.value));

    return Transform.scale(
      scale: 1 + nudge + pulse + 0.04 * pre,
      child: SizedBox(
        width: 248,
        height: 248,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // هاله‌ی شارژ
            if (holding && !_active)
              Opacity(
                opacity: pre,
                child: Container(
                  width: 178 + 52 * pre,
                  height: 178 + 52 * pre,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.connectedColor.withValues(alpha: widget.dark ? 0.28 : 0.20),
                        widget.connectedColor.withValues(alpha: 0),
                      ],
                      stops: const [0.55, 1.0],
                    ),
                  ),
                ),
              ),

            // تنفس متصل
            AnimatedOpacity(
              opacity: _connected ? 1 : 0,
              duration: const Duration(milliseconds: 700),
              child: Transform.scale(
                scale: 1 + 0.045 * Curves.easeInOut.transform(widget.breathe.value),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.connectedColor.withValues(alpha: widget.dark ? 0.20 : 0.14),
                        widget.connectedColor.withValues(alpha: 0),
                      ],
                      stops: const [0.58, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // موج اتصال
            Builder(builder: (_) {
              final p = widget.burst.value;
              if (p <= 0 || p >= 1) return const SizedBox.shrink();
              final k = Curves.easeOutCubic.transform(p);
              return Container(
                width: 142 + 100 * k,
                height: 142 + 100 * k,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.connectedColor.withValues(alpha: (1 - p) * 0.42),
                    width: 2.0 * (1 - p) + 0.4,
                  ),
                ),
              );
            }),

            // اسپینر اتصال
            AnimatedOpacity(
              opacity: _connecting ? 1 : 0,
              duration: const Duration(milliseconds: 350),
              child: CustomPaint(
                size: const Size(188, 188),
                painter: _SpinnerPainter(
                  angle: widget.spin.value * 2 * math.pi,
                  color: widget.gold ? UiPalette.gold : widget.colorB,
                ),
              ),
            ),

            // حلقه‌ی شارژ نگه‌داشتن (اتصال یا قطع)
            if (holding || disconnectHold > 0.01)
              CustomPaint(
                size: const Size(186, 186),
                painter: _ChargePainter(
                  progress: _active ? disconnectHold : pre,
                  color: _active ? widget.connectedColor : widget.connectedColor,
                  track: widget.dark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
                ),
              ),

            // گوی
            Container(
              width: 142,
              height: 142,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: card,
                boxShadow: [
                  BoxShadow(
                    color: (glow ? (_active ? widget.connectedColor : widget.colorB) : Colors.black)
                        .withValues(
                            alpha: glow
                                ? (widget.dark ? 0.40 : 0.28) * (_active ? 1 : math.max(pre, 0.35))
                                : (widget.dark ? 0.0 : 0.07)),
                    blurRadius: glow ? 34 : 24,
                    offset: Offset(0, glow ? 12 : 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: _active ? 1 : pre,
                        duration: Duration(milliseconds: holding ? 40 : 420),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(widget.colorA, widget.connectedColor, _active ? 1 : pre)!,
                                Color.lerp(widget.colorB, widget.connectedColor, _active ? 1 : pre)!,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // درخشش داخلی هنگام نگه‌داشتن
                    if (holding && !_active)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.22 * pre),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    Icon(
                      Icons.power_settings_new_rounded,
                      size: 56,
                      color: Color.lerp(
                        secondary,
                        Colors.white,
                        _active ? 1.0 : Curves.easeOut.transform(pre),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double angle;
  final Color color;
  _SpinnerPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..color = color.withValues(alpha: 0.12),
    );
    const sweep = math.pi * 1.35;
    canvas.drawArc(
      rect,
      angle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
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
  bool shouldRepaint(_SpinnerPainter old) => old.angle != angle || old.color != color;
}

class _ChargePainter extends CustomPainter {
  final double progress;
  final Color color, track;
  _ChargePainter({required this.progress, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = track.withValues(alpha: 0.9),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ChargePainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
