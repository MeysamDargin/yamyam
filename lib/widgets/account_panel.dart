import 'package:flutter/material.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/models/client_stats.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/models/vpn_status.dart';
import 'package:yamyam/screen/gold_page.dart';
import 'package:yamyam/state/app_controller.dart';

/// وضعیت اشتراک کاربر: فعال/غیرفعال، مصرف، زمان باقی‌مانده و مصرف همین نشست.
class AccountPanel extends StatelessWidget {
  final AppController controller;
  const AccountPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final c = controller;
    final s = c.stats;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'اشتراک شما',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ui.label,
                ),
              ),
              if (c.plansEnabled) ...[
                const SizedBox(width: 8),
                _planTag(c),
              ],
              const Spacer(),
              _stateChip(context, c, s),
            ],
          ),
          const SizedBox(height: 12),
          if (s != null) ...[
            _usage(context, c, s),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _info(
                    context,
                    Icons.schedule_rounded,
                    'زمان باقی‌مانده',
                    _timeLeft(s),
                  ),
                ),
                Container(width: 0.5, height: 30, color: ui.separator),
                Expanded(child: _sessionInfo(context, c)),
              ],
            ),
            ..._planNotes(context, c, s),
          ] else
            Text(
              c.statsError ??
                  (c.account == null
                      ? 'اکانت شما هنگام اولین اتصال ساخته می‌شود.'
                      : 'در حال دریافت اطلاعات…'),
              style: TextStyle(fontSize: 13, color: ui.secondary, height: 1.6),
            ),
        ],
      ),
    );
  }

  ServerSpec? _spec(AppController c) {
    final sv = c.selectedServer;
    return sv == null ? null : c.specFor(sv);
  }

  String _usageLabel(AppController c) {
    if (!c.plansEnabled) return 'مصرف';
    return (_spec(c)?.dailyReset ?? false) ? 'مصرف امروز' : 'مصرف';
  }

  /// برچسب پلن کنار عنوان (طلایی با رنگ برند، رایگان خنثی).
  Widget _planTag(AppController c) {
    final accent = parseHexColor(c.plans.gold.accentHex);
    final gold = c.isGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (gold ? accent : UiPalette.blue).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gold) Icon(Icons.workspace_premium_rounded, size: 13, color: accent),
          if (gold) const SizedBox(width: 3),
          Text(
            gold ? c.plans.gold.title : c.plans.free.title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: gold ? accent : UiPalette.blue,
            ),
          ),
        ],
      ),
    );
  }

  /// توضیح تمدید روزانه / سقف دوره‌ای + دکمه‌ی ارتقا هنگام اتمام حجم یا قفل بودن سرور.
  List<Widget> _planNotes(BuildContext context, AppController c, ClientStats s) {
    if (!c.plansEnabled) return const [];
    final ui = context.ui;
    final spec = _spec(c);
    final notes = <String>[];
    if (spec != null && !spec.blocked) {
      if (spec.dailyReset && !spec.unlimited) {
        notes.add(c.isGold || c.plans.free.resetText.isEmpty
            ? 'حجم روزانه هر روز تمدید می‌شود.'
            : c.plans.free.resetText);
      }
      if (spec.capBytes > 0) {
        notes.add(
            'سقف ${spec.capPeriod == 'monthly' ? 'ماهانه' : 'دوره'}: ${formatBytes(spec.capBytes)}');
      }
    }
    final blocked = spec?.blocked ?? false;
    final depleted = s.state == AccountState.depleted;
    final showUpsell = !c.isGold &&
        c.plans.canPurchase &&
        ((blocked && c.plans.ui.upsellOnLockedServer) ||
            (depleted && c.plans.ui.upsellOnDepleted));
    return [
      if (blocked)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(PlanUi.fmt(c.plans.ui.lockedServerText, 'این سرور فقط برای کاربران {plan} است.', plan: c.plans.gold.title),
              style: TextStyle(fontSize: 12.5, color: UiPalette.amber, height: 1.5)),
        ),
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(n, style: TextStyle(fontSize: 12, color: ui.secondary, height: 1.5)),
        ),
      if (showUpsell)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => openGoldPage(context),
              style: FilledButton.styleFrom(
                backgroundColor: parseHexColor(c.plans.gold.accentHex),
                foregroundColor: const Color(0xFF2B1F00),
              ),
              icon: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: Text(depleted
                  ? PlanUi.fmt(c.plans.ui.depletedCta, 'افزایش حجم با {plan}', plan: c.plans.gold.title)
                  : PlanUi.fmt(c.plans.ui.upgradeCta, 'ارتقا به {plan}', plan: c.plans.gold.title)),
            ),
          ),
        ),
    ];
  }

  Widget _stateChip(BuildContext context, AppController c, ClientStats? s) {
    final ui = context.ui;
    final (text, color) = switch (s?.state) {
      AccountState.active => ('فعال', UiPalette.green),
      AccountState.disabled => ('غیرفعال', UiPalette.red),
      AccountState.expired => ('منقضی شده', UiPalette.orange),
      AccountState.depleted => ('حجم تمام شد', UiPalette.orange),
      null => (c.account == null ? 'ساخته نشده' : '…', ui.secondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _usage(BuildContext context, AppController c, ClientStats s) {
    final ui = context.ui;
    final unlimited = s.unlimitedTraffic;
    final f = s.usedFraction;
    final percent = s.usedPercent;
    final color = f >= 0.9
        ? UiPalette.red
        : f >= 0.7
            ? UiPalette.amber
            : UiPalette.blue;
    final totalText = unlimited ? 'نامحدود' : formatBytes(s.total);
    final remainText = unlimited ? 'نامحدود' : formatBytes(s.remainingBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(_usageLabel(c), style: TextStyle(fontSize: 13, color: ui.secondary)),
            const Spacer(),
            Text(
              unlimited
                  ? '${formatBytes(s.used)} · نامحدود'
                  : '${formatBytes(s.used)} از $totalText',
              style: TextStyle(fontSize: 13, color: ui.label, fontWeight: FontWeight.w500),
            ),
            if (percent != null) ...[
              const SizedBox(width: 8),
              Text(
                '${faDigits(percent)}٪',
                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
        if (!unlimited) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: f),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 7,
                color: color,
                backgroundColor: ui.separator,
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            unlimited
                ? 'باقی‌مانده: نامحدود · کل: نامحدود'
                : 'باقی‌مانده: $remainText از $totalText',
            style: TextStyle(fontSize: 12, color: ui.secondary),
          ),
        ),
      ],
    );
  }

  String _timeLeft(ClientStats s) {
    if (s.startsOnFirstUse) return '${faDigits(s.daysLeft)} روز (از اولین اتصال)';
    final d = s.daysLeft;
    if (d == null) return 'نامحدود';
    if (d <= 0) return 'پایان یافته';
    return '${faDigits(d)} روز';
  }

  /// مصرف همین اتصال (آپلود + دانلود)؛ از شمارنده‌های هسته، بدون هیچ ترافیک اضافه.
  Widget _sessionInfo(BuildContext context, AppController c) {
    final connected = c.vpnStatus == VpnStatus.connected;
    final bytes = c.sessionBytes;
    return _info(
      context,
      Icons.data_usage_rounded,
      connected ? 'مصرف این اتصال' : 'آخرین اتصال',
      bytes == null ? '—' : formatBytes(bytes),
    );
  }

  Widget _info(
    BuildContext context,
    IconData icon,
    String title,
    String value, {
    Color? valueColor,
  }) {
    final ui = context.ui;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: ui.secondary),
            const SizedBox(width: 4),
            Text(title, style: TextStyle(fontSize: 12, color: ui.secondary)),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: valueColor ?? ui.label,
          ),
        ),
      ],
    );
  }
}
