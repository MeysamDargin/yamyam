import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/platform/tv_platform.dart';

/// لمس و دکمه‌ی انتخاب ریموت اندروید تی‌وی را یکی می‌کند.
class RemoteTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool circular;
  final bool ring;
  final BorderRadius borderRadius;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;
  final VoidCallback? onTapCancel;

  const RemoteTap({
    super.key,
    required this.child,
    required this.onTap,
    this.autofocus = false,
    this.circular = false,
    this.ring = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
  });

  @override
  State<RemoteTap> createState() => _RemoteTapState();
}

class _RemoteTapState extends State<RemoteTap> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.skipTraversal = widget.onTap == null;
    _node.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(RemoteTap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _node.skipTraversal = widget.onTap == null;
    if (widget.onTap == null && _node.hasFocus) _node.unfocus();
  }

  @override
  void dispose() {
    _node.removeListener(_rebuild);
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onTap == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final select = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space;
    if (!select) return KeyEventResult.ignored;
    widget.onTap!();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final showRing = widget.ring && TvPlatform.isTv && _node.hasFocus && widget.onTap != null;
    return Actions(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus && widget.onTap != null && TvPlatform.isTv,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onTapDown == null ? null : (_) => widget.onTapDown!(),
          onTapUp: widget.onTapUp == null ? null : (_) => widget.onTapUp!(),
          onTapCancel: widget.onTapCancel,
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child,
              if (showRing)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius: widget.circular ? null : widget.borderRadius,
                        border: Border.all(color: const Color(0xFF0A84FF), width: 3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
