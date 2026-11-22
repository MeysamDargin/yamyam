/// مدل‌های پاسخ `GET /api/v1/config` پنل YamYam.
library;

import 'package:yamyam/ads/ad_models.dart';
import 'package:yamyam/models/plan_models.dart';

int _int(dynamic v, [int d = 0]) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
double _double(dynamic v, [double d = 0]) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? d;
String _str(dynamic v) => (v ?? '').toString();
bool _bool(dynamic v) => v == true || v == 1 || v == 'true';

/// یک سرور 3X-UI که مدیر در پنل تعریف کرده.
class VpnServer {
  final int id;
  final String title;
  final String country;
  final String countryCode;
  final String flag;
  final String baseUrl;
  final int inboundId;
  final int priority;
  final bool verifySsl;

  /// اگر مدیر «ارسال api_token به اپ» را خاموش کرده باشد null است.
  final String? apiToken;

  /// پلن رایگان این سرور (null = سیستم پلن‌ها خاموش است)
  final ServerPlan? plan;

  const VpnServer({
    required this.id,
    required this.title,
    required this.country,
    required this.countryCode,
    required this.flag,
    required this.baseUrl,
    required this.inboundId,
    required this.priority,
    required this.verifySsl,
    required this.apiToken,
    this.plan,
  });

  bool get canManageClients => (apiToken ?? '').isNotEmpty;

  factory VpnServer.fromJson(Map<String, dynamic> j) => VpnServer(
        id: _int(j['id']),
        title: _str(j['title']),
        country: _str(j['country']),
        countryCode: _str(j['country_code']),
        flag: _str(j['flag']).isEmpty ? '🏳️' : _str(j['flag']),
        baseUrl: _str(j['base_url']).replaceAll(RegExp(r'/+$'), ''),
        inboundId: _int(j['inbound_id']),
        priority: _int(j['priority']),
        verifySsl: j['verify_ssl'] == null ? true : _bool(j['verify_ssl']),
        apiToken: j['api_token'] == null ? null : _str(j['api_token']),
        plan: ServerPlan.fromJson(j['plan']),
      );
}

class MaintenanceInfo {
  final bool enabled;
  final String message;
  const MaintenanceInfo({this.enabled = false, this.message = ''});

  factory MaintenanceInfo.fromJson(Map<String, dynamic>? j) => MaintenanceInfo(
        enabled: _bool(j?['enabled']),
        message: _str(j?['message']),
      );
}

class UpdateInfo {
  final bool available;
  final String versionName;
  final int versionCode;
  final String downloadUrl;
  final List<String> changelog;
  final bool force;
  final int minSupportedCode;

  const UpdateInfo({
    this.available = false,
    this.versionName = '',
    this.versionCode = 0,
    this.downloadUrl = '',
    this.changelog = const [],
    this.force = false,
    this.minSupportedCode = 0,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic>? j) => UpdateInfo(
        available: _bool(j?['available']),
        versionName: _str(j?['version_name']),
        versionCode: _int(j?['version_code']),
        downloadUrl: _str(j?['download_url']),
        changelog:
            ((j?['changelog'] as List?) ?? const []).map(_str).toList(),
        force: _bool(j?['force']),
        minSupportedCode: _int(j?['min_supported_code']),
      );

  /// آیا نسخه‌ی نصب‌شده (build number) از نسخه‌ی منتشرشده قدیمی‌تر است؟
  bool needsUpdate(int currentBuild) =>
      available && downloadUrl.isNotEmpty && currentBuild < versionCode;

  /// اجباری: یا مدیر اجباری کرده، یا نسخه‌ی فعلی از حداقل پشتیبانی کمتر است.
  bool isForced(int currentBuild) =>
      needsUpdate(currentBuild) &&
      (force || (minSupportedCode > 0 && currentBuild < minSupportedCode));
}

class PopupMessage {
  final int id;
  final String title;
  final String body;
  final String level; // info | success | warning | error
  final String buttonText;
  final String buttonUrl;
  final bool dismissible;

  const PopupMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.level,
    required this.buttonText,
    required this.buttonUrl,
    required this.dismissible,
  });

  bool get hasButton => buttonText.isNotEmpty && buttonUrl.isNotEmpty;

  static PopupMessage? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return PopupMessage(
      id: _int(j['id']),
      title: _str(j['title']),
      body: _str(j['body']),
      level: _str(j['level']).isEmpty ? 'info' : _str(j['level']),
      buttonText: _str(j['button_text']),
      buttonUrl: _str(j['button_url']),
      dismissible: j['dismissible'] == null ? true : _bool(j['dismissible']),
    );
  }
}

class SupportInfo {
  final String telegram;
  final String website;
  final String email;
  const SupportInfo({this.telegram = '', this.website = '', this.email = ''});

  factory SupportInfo.fromJson(Map<String, dynamic>? j) => SupportInfo(
        telegram: _str(j?['telegram']),
        website: _str(j?['website']),
        email: _str(j?['email']),
      );

  bool get isEmpty => telegram.isEmpty && website.isEmpty && email.isEmpty;
}

/// مقادیر پیش‌فرض کلاینت جدید (۰ = نامحدود).
class ClientDefaults {
  final double trafficGb;
  final int expiryDays;
  final int limitIp;
  const ClientDefaults({
    this.trafficGb = 0,
    this.expiryDays = 0,
    this.limitIp = 0,
  });

  factory ClientDefaults.fromJson(Map<String, dynamic>? j) => ClientDefaults(
        trafficGb: _double(j?['traffic_gb']),
        expiryDays: _int(j?['expiry_days']),
        limitIp: _int(j?['limit_ip']),
      );
}

class AppConfig {
  final MaintenanceInfo maintenance;
  final UpdateInfo update;
  final PopupMessage? message;
  final SupportInfo support;
  final ClientDefaults clientDefaults;
  final List<VpnServer> servers;

  /// تبلیغات (بلوک `ads` پنل)
  final AdsConfig ads;

  /// پلن‌های رایگان/طلایی (بلوک `plans`)
  final PlansInfo plans;

  const AppConfig({
    required this.maintenance,
    required this.update,
    required this.message,
    required this.support,
    required this.clientDefaults,
    required this.servers,
    this.ads = AdsConfig.off,
    this.plans = PlansInfo.off,
  });

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final servers = ((j['servers'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => VpnServer.fromJson(e.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        return p != 0 ? p : a.id.compareTo(b.id);
      });
    return AppConfig(
      maintenance: MaintenanceInfo.fromJson(_map(j['maintenance'])),
      update: UpdateInfo.fromJson(_map(j['update'])),
      message: PopupMessage.fromJson(_map(j['message'])),
      support: SupportInfo.fromJson(_map(j['support'])),
      clientDefaults: ClientDefaults.fromJson(_map(j['client_defaults'])),
      servers: servers,
      ads: AdsConfig.fromJson(_map(j['ads'])),
      plans: PlansInfo.fromJson(_map(j['plans'])),
    );
  }

  VpnServer? serverById(int? id) {
    for (final s in servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  static Map<String, dynamic>? _map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : null;
}
