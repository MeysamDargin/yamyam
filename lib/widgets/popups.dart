import 'package:flutter/material.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/state/app_controller.dart';
import 'package:yamyam/widgets/open_url.dart';

/// قالب مشترک دیالوگ‌ها: کارت گرد، آیکون رنگی، عنوان، متن و دکمه‌ها.
class _PopupFrame extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final Widget? body;
  final List<Widget> actions;

  const _PopupFrame({
    required this.icon,
    required this.accent,
    required this.title,
    required this.actions,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Dialog(
      backgroundColor: ui.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: accent),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: ui.label,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 10),
                Flexible(child: SingleChildScrollView(child: body)),
              ],
              const SizedBox(height: 20),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onTap;
  const _PrimaryButton({required this.text, required this.onTap, this.color = UiPalette.blue});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onTap,
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        ),
      );
}

class _SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SecondaryButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 44,
        child: TextButton(
          onPressed: onTap,
          child: Text(text, style: TextStyle(color: context.ui.secondary)),
        ),
      );
}

// ======================================================================= //
// آپدیت
// ======================================================================= //
Future<void> showUpdateDialog(BuildContext context, AppController c) async {
  final u = c.update!;
  final forced = c.updateForced;
  final ui = context.ui;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: !forced,
      child: _PopupFrame(
        icon: Icons.system_update_rounded,
        accent: forced ? UiPalette.orange : UiPalette.blue,
        title: forced ? 'بروزرسانی ضروری است' : 'نسخه‌ی جدید منتشر شد',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (u.versionName.isNotEmpty)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: ui.bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'نسخه ${faDigits(u.versionName)}',
                    style: TextStyle(fontSize: 13, color: ui.secondary),
                  ),
                ),
              ),
            if (forced)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'برای ادامه‌ی استفاده از برنامه باید آن را بروزرسانی کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ui.secondary, height: 1.6),
                ),
              ),
            if (u.changelog.isNotEmpty) ...[
              Text('تغییرات این نسخه',
                  style: TextStyle(fontWeight: FontWeight.w600, color: ui.label)),
              const SizedBox(height: 6),
              for (final line in u.changelog)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: UiPalette.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(line,
                            style: TextStyle(color: ui.label, height: 1.6, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
        actions: [
          _PrimaryButton(
            text: 'دانلود نسخه‌ی جدید',
            onTap: () => openUrl(u.downloadUrl),
          ),
          if (!forced)
            _SecondaryButton(
              text: 'بعداً',
              onTap: () {
                c.dismissUpdate();
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    ),
  );
}

// ======================================================================= //
// پیام مدیر
// ======================================================================= //
Future<void> showAdminMessage(
  BuildContext context,
  AppController c,
  PopupMessage m,
) async {
  final ui = context.ui;
  final (icon, accent) = switch (m.level) {
    'success' => (Icons.check_circle_rounded, UiPalette.green),
    'warning' => (Icons.warning_amber_rounded, UiPalette.amber),
    'error' => (Icons.error_rounded, UiPalette.red),
    _ => (Icons.info_rounded, UiPalette.blue),
  };
  // پیام غیرقابل‌بستن بدون دکمه، اپ را قفل می‌کند؛ پس دکمه‌ی بستن همیشه هست.
  final canClose = m.dismissible || !m.hasButton;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: canClose,
      child: _PopupFrame(
        icon: icon,
        accent: accent,
        title: m.title.isEmpty ? 'پیام' : m.title,
        body: m.body.isEmpty
            ? null
            : Text(
                m.body,
                textAlign: TextAlign.center,
                style: TextStyle(color: ui.secondary, height: 1.8, fontSize: 14.5),
              ),
        actions: [
          if (m.hasButton)
            _PrimaryButton(
              text: m.buttonText,
              color: accent,
              onTap: () async {
                await openUrl(m.buttonUrl);
                if (m.dismissible && ctx.mounted) {
                  c.markMessageSeen(m);
                  Navigator.pop(ctx);
                }
              },
            ),
          if (canClose)
            m.hasButton
                ? _SecondaryButton(
                    text: 'بستن',
                    onTap: () {
                      c.markMessageSeen(m);
                      Navigator.pop(ctx);
                    },
                  )
                : _PrimaryButton(
                    text: 'متوجه شدم',
                    color: accent,
                    onTap: () {
                      c.markMessageSeen(m);
                      Navigator.pop(ctx);
                    },
                  ),
        ],
      ),
    ),
  );
}

// ======================================================================= //
// حالت تعمیر
// ======================================================================= //
class MaintenanceView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const MaintenanceView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Positioned.fill(
      child: Material(
        color: ui.bg,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: UiPalette.amber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.build_rounded, size: 40, color: UiPalette.amber),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'سرویس در حال تعمیر است',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: ui.label,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ui.secondary, height: 1.8, fontSize: 15),
                  ),
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    onPressed: onRetry,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(UiPalette.blue),
                      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      padding: WidgetStateProperty.all(EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                      // textStyle: WidgetStateProperty.all(TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('بررسی مجدد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
