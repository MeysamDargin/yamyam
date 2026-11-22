/// جریان‌های تبلیغاتی سطح اپ: تبلیغ پیش از اتصال VPN، هنگام قطع، بعد از اتصال،
/// پاپ‌آپ ورود، App Open، اسپلش و ویدیوی جایزه.
library;

import 'package:flutter/material.dart';
import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/ads/ads_manager.dart';
import 'package:yamyam/ads/network_adapters.dart';
import 'package:yamyam/ads/widgets/fullscreen_ad.dart';
import 'package:yamyam/models/vpn_status.dart';
import 'package:yamyam/state/app_controller.dart';

abstract final class AdFlow {
  static const _interruptFormats = {AdFormat.interstitial, AdFormat.popup, AdFormat.html};

  // ===================================================================== //
  // نمایش یک تبلیغ (تمام‌صفحه / پاپ‌آپ / شبکه‌ی ثالث)
  // ===================================================================== //
  static Future<AdRunResult> present(
    BuildContext context,
    AdsManager ads,
    AdItem ad,
    String placement, {
    FullscreenAdSpec? spec,
  }) {
    if (ad.isNetwork) return _showNetwork(context, ads, ad, placement);
    if (ad.format == AdFormat.popup || ad.format == AdFormat.html) {
      return showAdPopup(context, ads, ad, placement);
    }
    return showFullscreenAd(
      context,
      ads,
      spec ?? FullscreenAdSpec.forAd(ad, placement, ads.settings),
    );
  }

  static Future<AdRunResult> _showNetwork(
    BuildContext context,
    AdsManager ads,
    AdItem ad,
    String placement,
  ) async {
    final adapter = AdNetworks.of(ad.network);
    final unit = ads.unitIdFor(ad);
    if (adapter == null || unit == null) {
      ads.markFailed(ad, placement);
      return AdRunResult.failure;
    }
    ads.interruptiveActive = true;
    try {
      final r = await adapter.showFullscreen(context, ad, unit);
      if (!r.shown) {
        ads.markFailed(ad, placement);
        return AdRunResult.failure;
      }
      ads.recordImpression(ad, placement);
      if (r.completed) ads.recordEvent(ad, 'complete', placement);
      if (r.clicked) ads.recordClick(ad, placement);
      return AdRunResult(
        shown: true,
        completed: r.completed,
        clicked: r.clicked,
        rewardEarned: ad.isRewarded && r.completed,
      );
    } catch (_) {
      ads.markFailed(ad, placement);
      return AdRunResult.failure;
    } finally {
      ads.interruptiveActive = false;
    }
  }

  // ===================================================================== //
  // دکمه‌ی اتصال
  // ===================================================================== //
  /// کاربر دکمه‌ی اتصال را زد. اگر تبلیغ پیش از اتصال فعال و مجاز باشد نشان داده
  /// می‌شود (طبق حالت پنل: قابل رد / تا آخر / زمان‌دار) و VPN هم‌زمان یا بعد از آن وصل می‌شود.
  static Future<void> connectWithAds(BuildContext context, AppController c) async {
    final ads = c.ads;
    if (c.maintenance || !c.hasSelectedServer) return c.connect();

    // تبلیغِ حذف/تغییرکرده در پنل نباید نمایش داده شود: اگر کانفیگ قدیمی است اول تازه‌اش کن
    await c.ensureFreshAds();
    if (!context.mounted) return c.connect();

    var plan = ads.planPreConnect();
    if (plan == null) return c.connect();

    Future<void>? connecting;
    var connectDone = false;
    void startConnect() {
      connecting ??= c.connect().whenComplete(() => connectDone = true);
    }

    final link = PreConnectLink(
      listenable: c,
      statusText: () {
        if (connecting == null) return '';
        return switch (c.vpnStatus) {
          VpnStatus.connected => '✓ اتصال VPN برقرار شد',
          VpnStatus.connecting => 'در حال اتصال به VPN…',
          VpnStatus.disconnected => connectDone ? 'اتصال برقرار نشد' : 'در حال آماده‌سازی…',
        };
      },
      failed: () => connecting != null && connectDone && c.vpnStatus == VpnStatus.disconnected,
    );

    final tried = <int>{};
    AdRunResult? last;
    while (plan != null) {
      tried.add(plan.ad.id);
      if (plan.connectInBackground) startConnect();
      if (!context.mounted) break;
      last = await present(
        context,
        ads,
        plan.ad,
        AdPlacement.preConnect,
        spec: FullscreenAdSpec.preConnect(plan, link: link),
      );
      if (!last.failed) break;
      // شکست در بارگذاری → طبق تنظیم پنل
      if (ads.settings.fallback == 'next_ad' && tried.length < 3) {
        plan = ads.planPreConnect(exclude: tried, countAttempt: false);
        continue;
      }
      plan = null;
    }

    final failedToLoad = last == null || last.failed;
    if (failedToLoad && ads.settings.fallback == 'block' && connecting == null) {
      // اتصال هنوز شروع نشده (در حالت block همیشه بعد از تبلیغ شروع می‌شود)
      c.announce('برای اتصال باید تبلیغ نمایش داده شود. اینترنت را بررسی کنید و دوباره تلاش کنید.');
      return;
    }

    startConnect();
    await connecting;

    final res = last;
    final ad = tried.isEmpty ? null : _byId(ads, tried.last);
    if (res != null && res.rewardEarned && ad != null && ad.hasReward) {
      await c.claimAdReward(ad, AdPlacement.preConnect);
    }
  }

  static AdItem? _byId(AdsManager ads, int id) {
    for (final a in ads.config.items) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// قطع اتصال توسط کاربر؛ بعد از آن (در صورت وجود) تبلیغ «هنگام قطع» نشان داده می‌شود.
  static Future<void> disconnectWithAds(BuildContext context, AppController c) async {
    final wasConnected = c.vpnStatus == VpnStatus.connected;
    await c.disconnect();
    if (!wasConnected || !context.mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!context.mounted || c.vpnStatus != VpnStatus.disconnected) return;
    await showInterruptive(context, c, AdPlacement.onDisconnect);
  }

  // ===================================================================== //
  // پاپ‌آپ / تمام‌صفحه در جایگاه‌های غیرفوری
  // ===================================================================== //
  /// launch_popup / post_connect / on_disconnect. فقط تبلیغ‌هایی که رسانه‌شان آماده است
  /// (تا کاربر منتظر دانلود نماند).
  static Future<AdRunResult?> showInterruptive(
    BuildContext context,
    AppController c,
    String placement,
  ) async {
    final ads = c.ads;
    await c.ensureFreshAds();
    if (!context.mounted) return null;
    final ad = ads.pick(placement, formats: _interruptFormats, requireCached: true);
    if (ad == null) return null;
    return present(context, ads, ad, placement);
  }

  /// بازگشت از پس‌زمینه
  static Future<void> showAppOpen(BuildContext context, AppController c) async {
    final ads = c.ads;
    await c.ensureFreshAds();
    if (!context.mounted) return;
    final ad = ads.pick(
      AdPlacement.appOpen,
      formats: const {AdFormat.appOpen},
      requireCached: true,
    );
    if (ad == null) return;
    final r = await present(context, ads, ad, AdPlacement.appOpen);
    if (r.shown) ads.ledger.markAppOpenShown();
  }

  /// روی اسپلش؛ true یعنی تبلیغی نشان داده شد.
  static Future<bool> showSplash(BuildContext context, AppController c) async {
    final ads = c.ads;
    final ad = ads.pick(
      AdPlacement.splash,
      formats: const {AdFormat.splash},
      requireCached: true,
    );
    if (ad == null) return false;
    final r = await present(context, ads, ad, AdPlacement.splash);
    return r.shown;
  }

  // ===================================================================== //
  // مرکز جایزه
  // ===================================================================== //
  static const rewardedFormats = {AdFormat.rewardedVideo, AdFormat.rewardedInterstitial};

  static bool rewardAvailable(AppController c) =>
      c.ads.available(AdPlacement.rewardCenter, formats: rewardedFormats);

  /// «ویدیو ببین و جایزه بگیر»
  static Future<void> watchForReward(BuildContext context, AppController c) async {
    final ads = c.ads;
    final ad = ads.pick(AdPlacement.rewardCenter, formats: rewardedFormats);
    if (ad == null) {
      c.announce('در حال حاضر ویدیویی برای نمایش وجود ندارد. کمی بعد دوباره سر بزنید.');
      return;
    }
    final needsAccount = ad.rewardType == 'traffic_mb' || ad.rewardType == 'days';
    if (needsAccount && c.account == null) {
      c.announce('ابتدا یک سرور انتخاب و یک‌بار متصل شوید تا جایزه روی اشتراکتان اعمال شود.');
      return;
    }
    final r = await present(context, ads, ad, AdPlacement.rewardCenter);
    if (r.failed) {
      c.announce('ویدیو بارگذاری نشد. اینترنت را بررسی کنید و دوباره تلاش کنید.');
    } else if (r.rewardEarned && ad.hasReward) {
      await c.claimAdReward(ad, AdPlacement.rewardCenter);
    }
  }
}
