/// مدل‌های بلوک `ads` در پاسخ `GET /api/v1/config` پنل (خروجی `ads.public_block`).
library;

import 'dart:ui' show Color;

int _int(dynamic v, [int d = 0]) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
double _double(dynamic v, [double d = 0]) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? d;
String _str(dynamic v) => (v ?? '').toString();
bool _bool(dynamic v, [bool d = false]) =>
    v == null ? d : (v == true || v == 1 || v == 'true');
List<String> _strList(dynamic v) =>
    v is List ? v.map(_str).where((e) => e.isNotEmpty).toList() : const [];
List<int> _intList(dynamic v) => v is List ? v.map((e) => _int(e, -1)).toList() : const [];

// ======================================================================= //
// ثابت‌ها (هم‌نام با تعریف‌های پنل)
// ======================================================================= //
abstract final class AdPlacement {
  static const homeTop = 'home_top';
  static const homeMiddle = 'home_middle';
  static const homeBottom = 'home_bottom';
  static const serverListTop = 'server_list_top';
  static const serverListInline = 'server_list_inline';
  static const settings = 'settings';
  static const splash = 'splash';
  static const appOpen = 'app_open';
  static const preConnect = 'pre_connect';
  static const postConnect = 'post_connect';
  static const onDisconnect = 'on_disconnect';
  static const launchPopup = 'launch_popup';
  static const floating = 'floating';
  static const rewardCenter = 'reward_center';

  /// جایگاه‌های «تمام‌صفحه/پاپ‌آپ» که با ریتم سراسری محدود می‌شوند.
  static const interruptive = {
    splash,
    appOpen,
    preConnect,
    postConnect,
    onDisconnect,
    launchPopup,
  };
}

abstract final class AdFormat {
  static const banner = 'banner';
  static const bannerLarge = 'banner_large';
  static const bannerAdaptive = 'banner_adaptive';
  static const mrec = 'mrec';
  static const videoBanner = 'video_banner';
  static const native = 'native';
  static const text = 'text';
  static const sponsoredServer = 'sponsored_server';
  static const interstitial = 'interstitial';
  static const rewardedVideo = 'rewarded_video';
  static const rewardedInterstitial = 'rewarded_interstitial';
  static const appOpen = 'app_open';
  static const preConnect = 'pre_connect';
  static const splash = 'splash';
  static const popup = 'popup';
  static const html = 'html';
  static const floatingIcon = 'floating_icon';

  /// بنرهای مستطیلی (تصویر/ویدیو/HTML)
  static const bannerKinds = {banner, bannerLarge, bannerAdaptive, mrec, videoBanner};

  /// قالب‌هایی که داخل یک «اسلات» صفحه نشان داده می‌شوند.
  static const slotFormats = {...bannerKinds, native, text, html};

  static const fullscreenKinds = {
    interstitial,
    rewardedVideo,
    rewardedInterstitial,
    appOpen,
    preConnect,
    splash,
  };

  static const rewarded = {rewardedVideo, rewardedInterstitial};

  static bool isFullscreen(String f) => fullscreenKinds.contains(f);
  static bool isRewarded(String f) => rewarded.contains(f);

  /// نسبت عرض به ارتفاع پیش‌فرض (هم‌سو با پنل)
  static double ratio(String f) => switch (f) {
        banner => 6.4,
        bannerLarge => 3.2,
        bannerAdaptive => 4.0,
        mrec => 300 / 250,
        videoBanner => 16 / 9,
        html => 3.0,
        _ => 3.0,
      };
}

// ======================================================================= //
// تنظیمات سراسری
// ======================================================================= //
class AdsSettings {
  final bool enabled;
  final bool testMode;
  final int utcOffsetMinutes;
  final Set<String> disabledPlacements;
  final String adLabel;
  final String removeAdsText;
  final String removeAdsUrl;

  final int graceMinutesAfterInstall;
  final int maxAdsPerDay;
  final int minGapFullscreenSec;
  final int maxFullscreenPerSession;
  final int appOpenCooldownSec;
  final int bannerRefreshSec;
  final int closeDelayDefaultSec;

  final bool preConnectEnabled;
  final String preConnectMode; // skippable | must_watch | timed
  final int preConnectSkipAfterSec;
  final int preConnectMaxWaitSec;
  final bool preConnectConnectInBackground;
  final int preConnectEveryNConnects;
  final bool preConnectSkipForRewardedUsers;
  final String fallback; // connect_anyway | next_ad | block

  final bool videoWifiOnly;
  final bool preloadMedia;
  final int maxMediaMbCellular;
  final int eventsFlushSec;

  const AdsSettings({
    this.enabled = false,
    this.testMode = false,
    this.utcOffsetMinutes = 210,
    this.disabledPlacements = const {},
    this.adLabel = 'تبلیغ',
    this.removeAdsText = '',
    this.removeAdsUrl = '',
    this.graceMinutesAfterInstall = 0,
    this.maxAdsPerDay = 0,
    this.minGapFullscreenSec = 120,
    this.maxFullscreenPerSession = 3,
    this.appOpenCooldownSec = 240,
    this.bannerRefreshSec = 60,
    this.closeDelayDefaultSec = 3,
    this.preConnectEnabled = false,
    this.preConnectMode = 'skippable',
    this.preConnectSkipAfterSec = 5,
    this.preConnectMaxWaitSec = 15,
    this.preConnectConnectInBackground = true,
    this.preConnectEveryNConnects = 1,
    this.preConnectSkipForRewardedUsers = true,
    this.fallback = 'connect_anyway',
    this.videoWifiOnly = true,
    this.preloadMedia = true,
    this.maxMediaMbCellular = 2,
    this.eventsFlushSec = 120,
  });

  factory AdsSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const AdsSettings();
    const d = AdsSettings();
    final label = _str(j['ad_label']);
    return AdsSettings(
      enabled: _bool(j['enabled']),
      testMode: _bool(j['test_mode']),
      utcOffsetMinutes: _int(j['utc_offset_minutes'], d.utcOffsetMinutes),
      disabledPlacements: _strList(j['disabled_placements']).toSet(),
      adLabel: label.isEmpty ? d.adLabel : label,
      removeAdsText: _str(j['remove_ads_text']),
      removeAdsUrl: _str(j['remove_ads_url']),
      graceMinutesAfterInstall: _int(j['grace_minutes_after_install']),
      maxAdsPerDay: _int(j['max_ads_per_day']),
      minGapFullscreenSec: _int(j['min_gap_fullscreen_sec'], d.minGapFullscreenSec),
      maxFullscreenPerSession:
          _int(j['max_fullscreen_per_session'], d.maxFullscreenPerSession),
      appOpenCooldownSec: _int(j['app_open_cooldown_sec'], d.appOpenCooldownSec),
      bannerRefreshSec: _int(j['banner_refresh_sec'], d.bannerRefreshSec),
      closeDelayDefaultSec:
          _int(j['close_delay_default_sec'], d.closeDelayDefaultSec),
      preConnectEnabled: _bool(j['pre_connect_enabled']),
      preConnectMode: _oneOf(j['pre_connect_mode'],
          const {'skippable', 'must_watch', 'timed'}, d.preConnectMode),
      preConnectSkipAfterSec:
          _int(j['pre_connect_skip_after_sec'], d.preConnectSkipAfterSec),
      preConnectMaxWaitSec:
          _int(j['pre_connect_max_wait_sec'], d.preConnectMaxWaitSec),
      preConnectConnectInBackground:
          _bool(j['pre_connect_connect_in_background'], true),
      preConnectEveryNConnects:
          _int(j['pre_connect_every_n_connects'], 1).clamp(1, 1000),
      preConnectSkipForRewardedUsers:
          _bool(j['pre_connect_skip_for_rewarded_users'], true),
      fallback: _oneOf(j['fallback'],
          const {'connect_anyway', 'next_ad', 'block'}, d.fallback),
      videoWifiOnly: _bool(j['video_wifi_only'], true),
      preloadMedia: _bool(j['preload_media'], true),
      maxMediaMbCellular: _int(j['max_media_mb_cellular'], d.maxMediaMbCellular),
      eventsFlushSec: _int(j['events_flush_sec'], d.eventsFlushSec).clamp(15, 3600),
    );
  }

  static String _oneOf(dynamic v, Set<String> ok, String d) {
    final s = _str(v);
    return ok.contains(s) ? s : d;
  }
}

// ======================================================================= //
// شبکه‌های تبلیغاتی
// ======================================================================= //
class NetworkCreds {
  final String appId;
  final String secret;
  final Map<String, String> units;
  final Map<String, String> testUnits;
  const NetworkCreds({
    this.appId = '',
    this.secret = '',
    this.units = const {},
    this.testUnits = const {},
  });

  factory NetworkCreds.fromJson(Map<String, dynamic>? j) => NetworkCreds(
        appId: _str(j?['app_id']),
        secret: _str(j?['secret']),
        units: _strMap(j?['units']),
        testUnits: _strMap(j?['test_units']),
      );

  static Map<String, String> _strMap(dynamic v) => v is Map
      ? {for (final e in v.entries) _str(e.key): _str(e.value)}
      : const {};
}

// ======================================================================= //
// یک تبلیغ
// ======================================================================= //
class AdItem {
  final int id;
  final String format;
  final List<String> placements;

  /// custom | network
  final String source;
  final String network;
  final String networkUnitId;

  final String mediaType; // image | video | html | none
  final String mediaUrl;
  final String posterUrl;
  final String iconUrl;
  final String html;
  final String headline;
  final String body;
  final String ctaText;
  final String sponsorName;
  final String badgeText;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? accentColor;
  final String clickAction; // open_url | in_app | telegram | store | none
  final String clickUrl;

  final int durationSec;
  final bool skippable;
  final int skipAfterSec;
  final int requiredWatchSec;
  final bool closeButton;
  final int closeDelaySec;
  final bool autoplay;
  final bool muted;
  final bool loop;
  final bool showCountdown;
  final String waitMode; // inherit | skippable | must_watch | timed
  final String connectInBackground; // inherit | yes | no

  final String rewardType; // none | traffic_mb | days | no_ads_minutes | coins
  final double rewardAmount;
  final int rewardDailyLimit;

  final int freqPerSession;
  final int freqPerDay;
  final int freqTotal;
  final int minIntervalSec;

  final List<String> platforms;
  final int minVersionCode;
  final int maxVersionCode;
  final List<int> serverIds;
  final String userType; // all | new | returning
  final int newUserDays;
  final List<String> languages;
  final bool wifiOnly;
  final String connectionState; // any | connected | disconnected
  final List<int> daysOfWeek; // ۰=شنبه … ۶=جمعه
  final int hourFrom;
  final int hourTo;
  final int? startTs;
  final int? endTs;

  final int priority;
  final int weight;
  final String impressionPixelUrl;
  final String clickPixelUrl;

  const AdItem({
    required this.id,
    required this.format,
    this.placements = const [],
    this.source = 'custom',
    this.network = '',
    this.networkUnitId = '',
    this.mediaType = 'none',
    this.mediaUrl = '',
    this.posterUrl = '',
    this.iconUrl = '',
    this.html = '',
    this.headline = '',
    this.body = '',
    this.ctaText = '',
    this.sponsorName = '',
    this.badgeText = '',
    this.backgroundColor,
    this.textColor,
    this.accentColor,
    this.clickAction = 'open_url',
    this.clickUrl = '',
    this.durationSec = 0,
    this.skippable = true,
    this.skipAfterSec = 5,
    this.requiredWatchSec = 0,
    this.closeButton = true,
    this.closeDelaySec = 3,
    this.autoplay = true,
    this.muted = true,
    this.loop = false,
    this.showCountdown = true,
    this.waitMode = 'inherit',
    this.connectInBackground = 'inherit',
    this.rewardType = 'none',
    this.rewardAmount = 0,
    this.rewardDailyLimit = 0,
    this.freqPerSession = 0,
    this.freqPerDay = 0,
    this.freqTotal = 0,
    this.minIntervalSec = 0,
    this.platforms = const ['android', 'ios'],
    this.minVersionCode = 0,
    this.maxVersionCode = 0,
    this.serverIds = const [],
    this.userType = 'all',
    this.newUserDays = 3,
    this.languages = const [],
    this.wifiOnly = false,
    this.connectionState = 'any',
    this.daysOfWeek = const [],
    this.hourFrom = 0,
    this.hourTo = 24,
    this.startTs,
    this.endTs,
    this.priority = 0,
    this.weight = 10,
    this.impressionPixelUrl = '',
    this.clickPixelUrl = '',
  });

  static Color? _color(dynamic v) {
    final s = _str(v).trim();
    final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(s);
    if (m == null) return null;
    return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }

  static int? _ts(dynamic v) => v is num ? v.toInt() : null;

  factory AdItem.fromJson(Map<String, dynamic> j) {
    const d = AdItem(id: 0, format: '');
    return AdItem(
      id: _int(j['id']),
      format: _str(j['format']),
      placements: _strList(j['placements']),
      source: _str(j['source']) == 'network' ? 'network' : 'custom',
      network: _str(j['network']),
      networkUnitId: _str(j['network_unit_id']),
      mediaType: _str(j['media_type']).isEmpty ? 'none' : _str(j['media_type']),
      mediaUrl: _str(j['media_url']),
      posterUrl: _str(j['poster_url']),
      iconUrl: _str(j['icon_url']),
      html: _str(j['html']),
      headline: _str(j['headline']),
      body: _str(j['body']),
      ctaText: _str(j['cta_text']),
      sponsorName: _str(j['sponsor_name']),
      badgeText: _str(j['badge_text']),
      backgroundColor: _color(j['background_color']),
      textColor: _color(j['text_color']),
      accentColor: _color(j['accent_color']),
      clickAction:
          _str(j['click_action']).isEmpty ? d.clickAction : _str(j['click_action']),
      clickUrl: _str(j['click_url']),
      durationSec: _int(j['duration_sec']),
      skippable: _bool(j['skippable'], true),
      skipAfterSec: _int(j['skip_after_sec'], d.skipAfterSec),
      requiredWatchSec: _int(j['required_watch_sec']),
      closeButton: _bool(j['close_button'], true),
      closeDelaySec: _int(j['close_delay_sec'], d.closeDelaySec),
      autoplay: _bool(j['autoplay'], true),
      muted: _bool(j['muted'], true),
      loop: _bool(j['loop']),
      showCountdown: _bool(j['show_countdown'], true),
      waitMode: _str(j['wait_mode']).isEmpty ? 'inherit' : _str(j['wait_mode']),
      connectInBackground: _str(j['connect_in_background']).isEmpty
          ? 'inherit'
          : _str(j['connect_in_background']),
      rewardType: _str(j['reward_type']).isEmpty ? 'none' : _str(j['reward_type']),
      rewardAmount: _double(j['reward_amount']),
      rewardDailyLimit: _int(j['reward_daily_limit']),
      freqPerSession: _int(j['freq_per_session']),
      freqPerDay: _int(j['freq_per_day']),
      freqTotal: _int(j['freq_total']),
      minIntervalSec: _int(j['min_interval_sec']),
      platforms:
          j['platforms'] == null ? d.platforms : _strList(j['platforms']),
      minVersionCode: _int(j['min_version_code']),
      maxVersionCode: _int(j['max_version_code']),
      serverIds: _intList(j['server_ids']),
      userType: _str(j['user_type']).isEmpty ? 'all' : _str(j['user_type']),
      newUserDays: _int(j['new_user_days'], d.newUserDays),
      languages: _strList(j['languages']).map((e) => e.toLowerCase()).toList(),
      wifiOnly: _bool(j['wifi_only']),
      connectionState: _str(j['connection_state']).isEmpty
          ? 'any'
          : _str(j['connection_state']),
      daysOfWeek: _intList(j['days_of_week']),
      hourFrom: _int(j['hour_from']),
      hourTo: _int(j['hour_to'], 24),
      startTs: _ts(j['start_ts']),
      endTs: _ts(j['end_ts']),
      priority: _int(j['priority']),
      weight: _int(j['weight'], d.weight).clamp(1, 100),
      impressionPixelUrl: _str(j['impression_pixel_url']),
      clickPixelUrl: _str(j['click_pixel_url']),
    );
  }

  // ---------- مشتقات ----------
  bool get isNetwork => source == 'network';
  bool get isRewarded => AdFormat.isRewarded(format);
  bool get isFullscreen => AdFormat.isFullscreen(format);
  bool get hasReward => isRewarded && rewardType != 'none' && rewardAmount > 0;
  bool get isVideo => mediaType == 'video' && mediaUrl.isNotEmpty;
  bool get isImage => mediaType == 'image' && mediaUrl.isNotEmpty;
  bool get isHtml => mediaType == 'html' && html.trim().isNotEmpty;
  bool get clickable => clickAction != 'none' && clickUrl.isNotEmpty;

  /// همه‌ی آدرس‌های رسانه‌ای که باید دانلود/کش شوند.
  List<String> get mediaUrls => [
        if (mediaType != 'html' && mediaUrl.isNotEmpty) mediaUrl,
        if (posterUrl.isNotEmpty) posterUrl,
        if (iconUrl.isNotEmpty) iconUrl,
      ];

  bool hasPlacement(String p) => placements.contains(p);

  /// اثر انگشتِ «ظاهر و رفتار کلیک»؛ اگر عوض شود یعنی مدیر تبلیغ را ویرایش کرده است.
  String get signature => [
        format,
        mediaType,
        mediaUrl,
        posterUrl,
        iconUrl,
        html.hashCode,
        headline,
        body,
        ctaText,
        sponsorName,
        badgeText,
        backgroundColor?.toARGB32(),
        textColor?.toARGB32(),
        accentColor?.toARGB32(),
        clickAction,
        clickUrl,
        network,
        networkUnitId,
      ].join('|');

  @override
  String toString() => 'AdItem#$id($format)';
}

// ======================================================================= //
// کل بلوک
// ======================================================================= //
class AdsConfig {
  final bool enabled;
  final AdsSettings settings;

  /// ترتیب تلاش منابع: `custom` یا نام شبکه
  final List<String> waterfall;
  final Map<String, NetworkCreds> networks;
  final List<AdItem> items;

  const AdsConfig({
    this.enabled = false,
    this.settings = const AdsSettings(),
    this.waterfall = const ['custom'],
    this.networks = const {},
    this.items = const [],
  });

  static const off = AdsConfig();

  factory AdsConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null || j['enabled'] != true) return AdsConfig.off;
    final nets = <String, NetworkCreds>{};
    final rawNets = j['networks'];
    if (rawNets is Map) {
      for (final e in rawNets.entries) {
        if (e.value is Map) {
          nets['${e.key}'] =
              NetworkCreds.fromJson((e.value as Map).cast<String, dynamic>());
        }
      }
    }
    final items = <AdItem>[];
    final rawItems = j['items'];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is! Map) continue;
        try {
          final a = AdItem.fromJson(e.cast<String, dynamic>());
          if (a.id > 0 && a.format.isNotEmpty && a.placements.isNotEmpty) items.add(a);
        } catch (_) {/* تبلیغ خراب نادیده گرفته می‌شود */}
      }
    }
    final wf = _strList(j['waterfall']);
    return AdsConfig(
      enabled: true,
      settings: AdsSettings.fromJson(
          j['settings'] is Map ? (j['settings'] as Map).cast<String, dynamic>() : null),
      waterfall: wf.isEmpty ? const ['custom'] : wf,
      networks: nets,
      items: items,
    );
  }
}
