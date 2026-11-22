import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/ads/ad_flow.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/widgets/ad_slot.dart';
import 'package:yamyam/ads/widgets/reward_center.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/screen/gold_page.dart';
import 'package:yamyam/state/app_scope.dart';
import 'package:yamyam/widgets/open_url.dart';
import 'package:yamyam/widgets/popups.dart';

/// تنظیمات/اطلاعات: حساب، پشتیبانی، نسخه و بررسی آپدیت.
Future<void> showSettingsSheet(BuildContext context) {
  final ui = context.ui;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: ui.bg,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final c = AppScope.of(context);
    final acc = c.account;
    final support = c.config?.support;

    Widget group(List<Widget> children) => Material(
          color: ui.card,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Divider(height: 1, thickness: 0.5, indent: 56, color: ui.separator),
              ],
            ],
          ),
        );

    Widget tile(IconData icon, String title,
            {String? value, VoidCallback? onTap, Color? color, bool autofocus = false}) =>
        ListTile(
          autofocus: autofocus,
          onTap: onTap,
          leading: Icon(icon, color: color ?? UiPalette.blue),
          title: Text(title, style: TextStyle(color: ui.label, fontWeight: FontWeight.w500)),
          trailing: value == null
              ? null
              : Text(value,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: ui.secondary, fontSize: 13)),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تنظیمات',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ui.label)),
            const SizedBox(height: 16),
            // مرکز جایزه (فقط اگر ویدیوی پاداش‌دار در دسترس است)
            ListenableBuilder(
              listenable: c.ads,
              builder: (_, __) => !AdFlow.rewardAvailable(c)
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Material(
                        color: ui.card,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: RewardCenterRow(controller: c, divider: false),
                      ),
                    ),
            ),
            if (c.plansEnabled && (c.isGold || c.plans.canPurchase || c.plan.hasOpenOrder)) ...[
              group([
                tile(
                  Icons.workspace_premium_rounded,
                  c.isGold
                      ? 'اشتراک ${c.plans.gold.title}'
                      : (c.plan.hasOpenOrder
                          ? 'پیگیری سفارش ${c.plans.gold.title}'
                          : PlanUi.fmt(c.plans.ui.upgradeCta, 'ارتقا به {plan}',
                              plan: c.plans.gold.title)),
                  value: c.isGold ? '${faDigits(c.goldDaysLeft)} روز مانده' : null,
                  color: UiPalette.amber,
                  onTap: () async {
                    final nav = Navigator.of(context);
                    final host = nav.context;
                    nav.pop();
                    if (host.mounted) await openGoldPage(host);
                  },
                ),
              ]),
              const SizedBox(height: 16),
            ],
            if (acc != null) ...[
              group([
                tile(Icons.person_rounded, 'شناسه‌ی اکانت',
                    value: acc.email,
                    autofocus: TvPlatform.isTv,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: acc.email));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('شناسه کپی شد')),
                      );
                    }),
                if (c.selectedServer != null)
                  tile(Icons.public_rounded, 'سرور فعلی', value: c.selectedServer!.title),
              ]),
              const SizedBox(height: 16),
            ],
            if (support != null && !support.isEmpty) ...[
              group([
                if (support.telegram.isNotEmpty)
                  tile(Icons.send_rounded, 'پشتیبانی تلگرام',
                      value: support.telegram,
                      onTap: () => openUrl(telegramUrl(support.telegram))),
                if (support.website.isNotEmpty)
                  tile(Icons.language_rounded, 'وب‌سایت',
                      onTap: () => openUrl(support.website)),
                if (support.email.isNotEmpty)
                  tile(Icons.mail_rounded, 'ایمیل',
                      value: support.email,
                      onTap: () => openUrl('mailto:${support.email}')),
              ]),
              const SizedBox(height: 16),
            ],
            if (c.ads.enabled &&
                !c.isGold &&
                c.ads.settings.removeAdsText.isNotEmpty &&
                c.ads.settings.removeAdsUrl.isNotEmpty) ...[
              group([
                tile(Icons.workspace_premium_rounded, c.ads.settings.removeAdsText,
                    color: UiPalette.amber, onTap: () {
                  c.ads.markExternalLaunch();
                  openUrl(c.ads.settings.removeAdsUrl);
                }),
              ]),
              const SizedBox(height: 16),
            ],
            group([
              tile(Icons.system_update_rounded, 'بررسی بروزرسانی',
                  autofocus: TvPlatform.isTv && acc == null, onTap: () async {
                final nav = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                await c.refreshConfig();
                if (c.updateNeeded) {
                  // بستن شیت و نمایش دیالوگ روی صفحه‌ی زیرین
                  final host = nav.context;
                  nav.pop();
                  if (host.mounted) await showUpdateDialog(host, c);
                } else {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('شما از آخرین نسخه استفاده می‌کنید ✓')),
                  );
                }
              }),
              tile(Icons.info_outline_rounded, 'نسخه‌ی برنامه',
                  value: '${c.versionName} (${c.buildNumber})'),
            ]),
            // جایگاه تبلیغ در صفحه‌ی تنظیمات
            const AdSlot(
              placement: AdPlacement.settings,
              padding: EdgeInsets.only(top: 16),
            ),
          ],
        ),
      ),
    );
  }
}
