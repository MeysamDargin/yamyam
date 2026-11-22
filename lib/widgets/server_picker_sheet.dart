import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yamyam/ads/ad_actions.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ad_text.dart';
import 'package:yamyam/ads/widgets/ad_slot.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/screen/gold_page.dart';
import 'package:yamyam/services/app_exception.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/state/app_controller.dart';
import 'package:yamyam/state/app_scope.dart';

/// پاپ‌آپ انتخاب سرور.
///
/// [firstTime] = بار اول ورود: بدون امکان بستن تا کاربر یک سرور انتخاب کند.
/// با انتخاب سرور، در صورت نبودن کلاینت برای این کاربر، روی 3X-UI ساخته و در
/// Hive ذخیره می‌شود. true یعنی سرور انتخاب شد.
Future<bool> showServerPicker(
  BuildContext context, {
  bool firstTime = false,
}) async {
  final ui = context.ui;
  final res = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: ui.bg,
    isScrollControlled: true,
    isDismissible: !firstTime,
    enableDrag: !firstTime,
    showDragHandle: !firstTime,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => PopScope(
      canPop: !firstTime,
      child: _ServerPicker(firstTime: firstTime),
    ),
  );
  return res ?? false;
}

class _ServerPicker extends StatefulWidget {
  final bool firstTime;
  const _ServerPicker({required this.firstTime});

  @override
  State<_ServerPicker> createState() => _ServerPickerState();
}

class _ServerPickerState extends State<_ServerPicker> {
  String? _error;
  bool _started = false;

  // تبلیغ‌های بین آیتم‌ها (سرور اسپانسری / بومی)؛ یک‌بار برای عمر این شیت انتخاب می‌شوند
  List<AdItem> _inline = const [];
  final Set<int> _impressed = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final c = AppScope.of(context, listen: false);
    if (c.servers.isEmpty) c.refreshConfig();
    if (!widget.firstTime) {
      _inline = c.ads.pickMany(
        AdPlacement.serverListInline,
        formats: const {AdFormat.native, AdFormat.sponsoredServer},
        max: 2,
      );
    }
  }

  Future<void> _select(AppController c, VpnServer s) async {
    if (c.provisioningServerId != null) return;
    HapticFeedback.selectionClick();
    setState(() => _error = null);
    // سرور «فقط طلایی» برای کاربر رایگان: پیشنهاد ارتقا
    if (c.isLocked(s)) {
      if (c.plans.ui.upsellOnLockedServer && c.plans.canPurchase) {
        final nav = Navigator.of(context);
        final host = nav.context;
        nav.pop(false);
        if (host.mounted) await openGoldPage(host);
      } else {
        setState(() => _error = PlanUi.fmt(
            c.plans.ui.lockedServerText, 'این سرور فقط برای کاربران {plan} است.',
            plan: c.plans.gold.title));
      }
      return;
    }
    try {
      await c.selectServer(s);
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'خطای ناشناخته. دوباره تلاش کنید.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final c = AppScope.of(context);
    final servers = c.servers;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, widget.firstTime ? 28 : 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.firstTime ? 'خوش آمدید 👋' : 'انتخاب سرور',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: ui.label,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.firstTime
                  ? 'یک سرور انتخاب کنید. اکانت شما به‌صورت خودکار روی آن ساخته می‌شود.'
                  : 'با انتخاب هر سرور، اکانت شما در صورت نیاز روی آن ساخته می‌شود.',
              style: TextStyle(fontSize: 14, color: ui.secondary, height: 1.6),
            ),
            const SizedBox(height: 16),
            if (!widget.firstTime)
              const AdSlot(
                placement: AdPlacement.serverListTop,
                padding: EdgeInsets.only(bottom: 14),
              ),
            Flexible(child: _body(c, servers)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBox(message: _error!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _body(AppController c, List<VpnServer> servers) {
    final ui = context.ui;

    if (servers.isEmpty) {
      if (c.configStatus == ConfigStatus.loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: ui.secondary),
            const SizedBox(height: 12),
            Text(
              c.configError ?? 'سروری برای نمایش وجود ندارد.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ui.secondary, height: 1.6),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: c.refreshConfig,
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    // سرورها + تبلیغ‌های بین آیتم‌ها (بعد از اولی و بعد از چهارمی)
    final items = <Object>[...servers];
    for (var i = 0; i < _inline.length; i++) {
      items.insert((i == 0 ? 1 : 4).clamp(0, items.length), _inline[i]);
    }

    return Material(
      color: ui.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 0.5,
          indent: 64,
          color: ui.separator,
        ),
        itemBuilder: (_, i) {
          final item = items[i];
          if (item is AdItem) {
            return InlineAdTile(
              key: ValueKey('ad${item.id}'),
              ad: item,
              label: adBadge(item, c.ads.settings),
              onShown: () {
                if (_impressed.add(item.id)) {
                  c.ads.recordImpression(item, AdPlacement.serverListInline);
                }
              },
              onTap: () => openAd(context, item, AdPlacement.serverListInline),
            );
          }
          final s = item as VpnServer;
          return _ServerTile(
            server: s,
            planLine: serverPlanLine(c, s),
            locked: c.isLocked(s),
            selected: s.id == c.selectedServer?.id,
            loading: c.provisioningServerId == s.id,
            enabled: c.provisioningServerId == null,
            autofocus: TvPlatform.isTv && i == 0,
            onTap: () => _select(c, s),
          );
        },
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  final VpnServer server;
  final String? planLine;
  final bool locked;
  final bool selected, loading, enabled;
  final bool autofocus;
  final VoidCallback onTap;

  const _ServerTile({
    required this.server,
    this.planLine,
    this.locked = false,
    required this.selected,
    required this.loading,
    required this.enabled,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return ListTile(
      onTap: enabled ? onTap : null,
      autofocus: autofocus && enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Text(server.flag, style: const TextStyle(fontSize: 30)),
      title: Text(
        server.title,
        style: TextStyle(fontWeight: FontWeight.w600, color: ui.label),
      ),
      subtitle: Text(
        loading
            ? 'در حال ساخت اکانت شما…'
            : [
                if (server.country.isNotEmpty) server.country,
                if (planLine != null) planLine!,
              ].join(' · ').ifEmpty('آماده‌ی اتصال'),
        style: TextStyle(color: locked ? UiPalette.amber : ui.secondary),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : locked
              ? const Icon(Icons.lock_rounded, color: UiPalette.amber)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((server.plan?.badge ?? '').isNotEmpty)
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: UiPalette.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          server.plan!.badge,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700, color: UiPalette.blue),
                        ),
                      ),
                    if (selected) const Icon(Icons.check_rounded, color: UiPalette.blue),
                  ],
                ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UiPalette.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: UiPalette.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: UiPalette.red, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

extension _EmptyFallback on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// خلاصه‌ی پلن کاربر روی یک سرور برای لیست سرورها (null اگر پلن‌ها خاموش‌اند).
String? serverPlanLine(AppController c, VpnServer s) {
  if (!c.plansEnabled) return null;
  final spec = c.specFor(s);
  if (spec != null) {
    if (spec.blocked) {
      return PlanUi.fmt(c.plans.ui.lockedBadgeText, 'فقط {plan}', plan: c.plans.gold.title);
    }
    final dailyUnit = spec.dailyReset ? ' در روز' : '';
    final amount = spec.unlimited ? 'نامحدود' : '${gbText(spec.totalGb)}$dailyUnit';
    return spec.gold ? '${c.plans.gold.title} · $amount' : amount;
  }
  final p = s.plan;
  if (p == null) return null;
  if (p.goldOnly) {
    return PlanUi.fmt(c.plans.ui.lockedBadgeText, 'فقط {plan}', plan: c.plans.gold.title);
  }
  return p.freeUnlimited ? 'نامحدود' : '${gbText(p.freeDailyGb)} در روز';
}
