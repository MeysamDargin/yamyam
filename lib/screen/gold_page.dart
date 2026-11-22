import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/screen/payment_page.dart';
import 'package:yamyam/services/app_exception.dart';
import 'package:yamyam/state/app_controller.dart';
import 'package:yamyam/state/app_scope.dart';
import 'package:yamyam/widgets/open_url.dart';
import 'package:yamyam/widgets/remote_tap.dart';

/// صفحه‌ی اختصاصی پلن طلایی: متن تبلیغاتی، بسته‌ها، شرایط، آموزش و وضعیت سفارش‌ها.
Future<void> openGoldPage(BuildContext context) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const GoldPage()));

String orderStatusText(PlanOrder o) => switch (o.status) {
      'awaiting_receipt' => 'منتظر ارسال رسید',
      'pending' => 'در حال بررسی',
      'approved' => 'تایید شد',
      'rejected' => 'رد شد',
      'cancelled' => 'لغو شد',
      'expired' => 'منقضی شد',
      _ => o.status,
    };

Color orderStatusColor(PlanOrder o) => switch (o.status) {
      'approved' => UiPalette.green,
      'rejected' => UiPalette.red,
      'pending' || 'awaiting_receipt' => UiPalette.amber,
      _ => const Color(0xFF8E8E93),
    };

class GoldPage extends StatefulWidget {
  const GoldPage({super.key});

  @override
  State<GoldPage> createState() => _GoldPageState();
}

class _GoldPageState extends State<GoldPage> {
  int? _selected;
  bool _termsOpen = false;
  bool _started = false;
  String? _busyOrder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final c = AppScope.of(context, listen: false);
    // وضعیت تازه‌ی پلن/سفارش‌ها هر بار که صفحه باز می‌شود
    c.refreshConfigIfStale(maxAge: const Duration(minutes: 2));
    c.refreshPlan(sync: false);
  }

  GoldPackage? _pick(AppController c) {
    final list = c.plans.gold.packages;
    if (list.isEmpty) return null;
    for (final p in list) {
      if (p.id == _selected) return p;
    }
    for (final p in list) {
      if (p.popular) return p;
    }
    return list.first;
  }

  Future<void> _continue(AppController c, GoldPackage p) async {
    final open = c.plan.openOrder;
    if (open != null) {
      _toast('شما یک سفارش در حال بررسی دارید. ابتدا آن را تکمیل یا لغو کنید.');
      return;
    }
    if (!c.plans.payment.hasCard) {
      _toast('اطلاعات پرداخت هنوز تنظیم نشده است. با پشتیبانی تماس بگیرید.');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PaymentPage(package: p)),
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _cancel(AppController c, PlanOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لغو سفارش'),
        content: Text('سفارش #${faDigits(o.id)} لغو شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله، لغو شود')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyOrder = '${o.id}');
    try {
      await c.cancelOrder(o);
      _toast('سفارش لغو شد.');
    } on AppException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busyOrder = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final ui = context.ui;
    final g = c.plans.gold;
    final accent = parseHexColor(g.accentHex);
    final pkg = _pick(c);

    return Scaffold(
      backgroundColor: ui.bg,
      appBar: AppBar(
        backgroundColor: ui.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(g.title, style: TextStyle(color: ui.label, fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: ui.label),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _hero(c, accent),
                const SizedBox(height: 14),
                if (c.isGold) ...[_status(c, accent), const SizedBox(height: 14)],
                if (c.goldExpired) ...[
                  _info(context, 'اشتراک قبلی شما به پایان رسیده است؛ برای ادامه یک بسته انتخاب کنید.',
                      Icons.info_outline_rounded, UiPalette.amber),
                  const SizedBox(height: 14),
                ],
                for (final o in c.plan.orders.where((o) => o.open)) ...[
                  _openOrder(c, o),
                  const SizedBox(height: 14),
                ],
                if (!c.plans.canPurchase)
                  _info(context, 'در حال حاضر بسته‌ای برای خرید موجود نیست.', Icons.hourglass_empty_rounded,
                      ui.secondary)
                else ...[
                  _sectionTitle(c.isGold ? 'تمدید / تغییر بسته' : 'انتخاب بسته'),
                  const SizedBox(height: 8),
                  for (final p in g.packages) ...[
                    _packageCard(c, p, accent, selected: p.id == pkg?.id),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  _cta(c, pkg, accent),
                ],
                if (g.tutorial.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _sectionTitle('آموزش خرید'),
                  const SizedBox(height: 8),
                  _tutorial(g, accent),
                ],
                if (g.terms.trim().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _terms(g),
                ],
                if (g.supportText.isNotEmpty || (c.config?.support.isEmpty == false)) ...[
                  const SizedBox(height: 18),
                  _support(c, g),
                ],
                if (c.plan.orders.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _sectionTitle('سفارش‌های من'),
                  const SizedBox(height: 8),
                  _history(c),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- hero
  Widget _hero(AppController c, Color accent) {
    final g = c.plans.gold;
    final light = Color.lerp(accent, Colors.white, 0.55)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [light, accent],
        ),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: Color(0xFF3A2A00), size: 30),
              const SizedBox(width: 8),
              Text(g.title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF3A2A00))),
              const Spacer(),
              if (g.badgeText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A2A00),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(g.badgeText,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: light)),
                ),
            ],
          ),
          if (g.promoTitle.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(g.promoTitle,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2B1F00), height: 1.5)),
          ] else if (g.tagline.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(g.tagline, style: const TextStyle(fontSize: 16, color: Color(0xFF2B1F00), height: 1.5)),
          ],
          if (g.promoText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(g.promoText,
                style: const TextStyle(fontSize: 14, color: Color(0xFF3A2A00), height: 1.8)),
          ],
          if (g.features.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final f in g.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF3A2A00)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF2B1F00), height: 1.5)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- active status
  Widget _status(AppController c, Color accent) {
    final ui = context.ui;
    final p = c.plan;
    final days = c.goldDaysLeft;
    final total = p.startedMs > 0 && p.expiresMs > p.startedMs
        ? (p.expiresMs - p.startedMs) / 86400000
        : 0.0;
    final frac = total > 0 ? (days / total).clamp(0.0, 1.0) : 1.0;
    final e = p.expiresAt;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(context).copyWith(border: Border.all(color: accent.withValues(alpha: 0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.verified_rounded, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('اشتراک شما فعال است${p.packageTitle.isEmpty ? '' : ' — ${p.packageTitle}'}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: ui.label)),
            ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              color: c.goldExpiringSoon ? UiPalette.orange : accent,
              backgroundColor: ui.separator,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${faDigits(days)} روز باقی‌مانده${e == null ? '' : ' · تا ${_date(e)}'}',
            style: TextStyle(color: c.goldExpiringSoon ? UiPalette.orange : ui.secondary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(p.dailyGb > 0 ? 'روزانه ${gbText(p.dailyGb)}' : 'بدون سقف روزانه'),
            _chip(p.totalGb > 0
                ? '${p.totalPeriod == 'monthly' ? 'ماهانه' : 'کل اشتراک'} ${gbText(p.totalGb)}'
                : 'حجم کل نامحدود'),
          ]),
        ],
      ),
    );
  }

  String _date(DateTime d) => faDigits('${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}');

  Widget _chip(String t) {
    final ui = context.ui;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: ui.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 12, color: ui.secondary)),
    );
  }

  // ---------------------------------------------------------------- open order
  Widget _openOrder(AppController c, PlanOrder o) {
    final ui = context.ui;
    final mine = c.canManageOrder(o);
    final busy = _busyOrder == '${o.id}';
    final pay = c.plans.payment;
    final msg = o.needsReceipt
        ? 'برای تکمیل سفارش، رسید پرداخت را ارسال کنید.'
        : (pay.pendingText.isEmpty ? 'رسید شما دریافت شد و در حال بررسی است.' : pay.pendingText);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(context).copyWith(border: Border.all(color: UiPalette.amber.withValues(alpha: 0.6))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.hourglass_top_rounded, color: UiPalette.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text('سفارش #${faDigits(o.id)} — ${o.packageTitle}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ui.label)),
            ),
            Text('${formatMoney(o.amount)} ${pay.currency}', style: TextStyle(color: ui.secondary, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          Text(msg, style: TextStyle(color: ui.secondary, height: 1.7, fontSize: 13.5)),
          const SizedBox(height: 12),
          if (busy)
            const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
          else if (mine)
            Row(children: [
              if (c.plans.payment.wantsImage && !TvPlatform.isTv)
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => PaymentPage(existing: o)),
                    ),
                    child: Text(o.hasReceipt ? 'جایگزینی رسید' : 'ارسال رسید'),
                  ),
                ),
              if (c.plans.payment.wantsImage && !TvPlatform.isTv) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _cancel(c, o),
                  child: const Text('لغو سفارش'),
                ),
              ),
            ])
          else
            Text('این سفارش از دستگاه دیگری ثبت شده است.', style: TextStyle(color: ui.secondary, fontSize: 12)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- packages
  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(t, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.ui.label)),
      );

  Widget _packageCard(AppController c, GoldPackage p, Color accent, {required bool selected}) {
    final ui = context.ui;
    final cur = c.plans.payment.currency;
    final scope = p.servers.isEmpty
        ? 'همه‌ی سرورها'
        : p.servers.map((id) => c.config?.serverById(id)?.title ?? '').where((t) => t.isNotEmpty).join('، ');
    return RemoteTap(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selected = p.id);
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ui.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : ui.separator, width: selected ? 2 : 1),
          boxShadow: selected
              ? [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6))]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? accent : ui.secondary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: ui.label)),
              ),
              if (p.popular) _tag('محبوب‌ترین', accent),
              if (p.badge.isNotEmpty) ...[const SizedBox(width: 6), _tag(p.badge, UiPalette.green)],
            ]),
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.description, style: TextStyle(color: ui.secondary, fontSize: 13, height: 1.6)),
            ],
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(p.price),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: selected ? accent : ui.label)),
              const SizedBox(width: 6),
              Text(cur, style: TextStyle(color: ui.secondary, fontSize: 13)),
              if (p.hasDiscount) ...[
                const SizedBox(width: 10),
                Text(formatMoney(p.oldPrice),
                    style: TextStyle(
                        color: ui.secondary, fontSize: 13, decoration: TextDecoration.lineThrough)),
              ],
              const Spacer(),
              Text('${faDigits(p.durationDays)} روز', style: TextStyle(color: ui.label, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(p.dailyUnlimited ? 'بدون سقف روزانه' : 'روزانه ${gbText(p.dailyGb)}'),
              _chip(p.totalUnlimited
                  ? 'حجم کل نامحدود'
                  : '${p.totalPeriod == 'monthly' ? 'ماهانه' : 'کل اشتراک'} ${gbText(p.totalGb)}'),
              if (p.limitIp > 0) _chip('${faDigits(p.limitIp)} دستگاه هم‌زمان'),
              _chip(scope.isEmpty ? 'همه‌ی سرورها' : scope),
            ]),
            for (final f in p.features)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(Icons.check_rounded, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(child: Text(f, style: TextStyle(fontSize: 13, color: ui.label))),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String t, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _cta(AppController c, GoldPackage? p, Color accent) {
    final g = c.plans.gold;
    return SizedBox(
      height: 54,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF2B1F00),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontFamily: kAppFont, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        onPressed: p == null ? null : () => _continue(c, p),
        child: Text(c.isGold ? 'تمدید با ${p?.title ?? ''}' : g.ctaText),
      ),
    );
  }

  // ---------------------------------------------------------------- tutorial / terms / support
  Widget _tutorial(GoldInfo g, Color accent) {
    final ui = context.ui;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(context),
      child: Column(
        children: [
          for (var i = 0; i < g.tutorial.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == g.tutorial.length - 1 ? 0 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: Text(faDigits(i + 1),
                        style: TextStyle(fontWeight: FontWeight.w800, color: accent, fontSize: 13)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(g.tutorial[i], style: TextStyle(color: ui.label, height: 1.7, fontSize: 14)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _terms(GoldInfo g) {
    final ui = context.ui;
    return Container(
      decoration: cardDecoration(context),
      child: Column(
        children: [
          RemoteTap(
            onTap: () => setState(() => _termsOpen = !_termsOpen),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.gavel_rounded, color: ui.secondary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('شرایط و قوانین',
                      style: TextStyle(fontWeight: FontWeight.w700, color: ui.label, fontSize: 15)),
                ),
                Icon(_termsOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: ui.secondary),
              ]),
            ),
          ),
          if (_termsOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(g.terms, style: TextStyle(color: ui.secondary, height: 1.9, fontSize: 13.5)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _support(AppController c, GoldInfo g) {
    final ui = context.ui;
    final s = c.config?.support;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (g.supportText.isNotEmpty)
            Text(g.supportText, style: TextStyle(color: ui.secondary, height: 1.7, fontSize: 13.5)),
          if (s != null && s.telegram.isNotEmpty) ...[
            if (g.supportText.isNotEmpty) const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => openUrl(telegramUrl(s.telegram)),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text('پشتیبانی تلگرام ${s.telegram}'),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- history
  Widget _history(AppController c) {
    final ui = context.ui;
    final list = c.plan.orders;
    return Container(
      decoration: cardDecoration(context),
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${list[i].packageTitle} · ${formatMoney(list[i].amount)} ${c.plans.payment.currency}',
                        style: TextStyle(color: ui.label, fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('سفارش #${faDigits(list[i].id)}'
                        '${list[i].rejectReason.isEmpty ? '' : ' · ${list[i].rejectReason}'}',
                        style: TextStyle(color: ui.secondary, fontSize: 12)),
                  ]),
                ),
                _tag(orderStatusText(list[i]), orderStatusColor(list[i])),
              ]),
            ),
            if (i != list.length - 1) Divider(height: 1, thickness: 0.5, indent: 16, color: ui.separator),
          ],
        ],
      ),
    );
  }

  Widget _info(BuildContext context, String text, IconData icon, Color color) {
    final ui = context.ui;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: ui.label, height: 1.6, fontSize: 13.5))),
      ]),
    );
  }
}
