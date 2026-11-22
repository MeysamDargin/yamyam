import 'dart:async';
import 'dart:convert';

import 'package:flutter_vless/flutter_vless.dart';
import 'package:yamyam/services/app_exception.dart';

/// لایه‌ی نازک روی flutter_vless.
class VpnService {
  late final FlutterVless _vless = FlutterVless(onStatusChanged: _onStatus);
  final _controller = StreamController<VlessStatus>.broadcast();
  bool _initialized = false;

  /// وضعیت لحظه‌ای (اتصال، سرعت، مصرف نشست).
  Stream<VlessStatus> get statusStream => _controller.stream;

  void _onStatus(VlessStatus s) => _controller.add(s);

  Future<void> init({required String packageName}) async {
    if (_initialized) return;
    await _vless.initializeVless(
      providerBundleIdentifier: packageName,
      groupIdentifier: 'group.$packageName',
    );
    _initialized = true;
  }

  Future<bool> requestPermission() => _vless.requestPermission();

  /// اتصال با لینک اشتراکی کلاینت (vless://...).
  Future<void> start({required String remark, required String link}) async {
    final String config;
    try {
      config = buildConfig(link);
    } catch (_) {
      throw const AppException('لینک اتصال سرور معتبر نیست.');
    }
    await _vless.startVless(remark: remark, config: config);
  }

  Future<void> stop() => _vless.stopVless();

  void dispose() => _controller.close();

  // ---------------------------------------------------------------------
  // بهینه‌سازی کانفیگ Xray
  // ---------------------------------------------------------------------
  // کانفیگ پیش‌فرض افزونه «مسیریابی» ندارد و همه‌چیز (حتی شبکه‌ی محلی و
  // سایت‌های ایرانی) را از سرور رد می‌کند. این یعنی:
  //  • مصرف بی‌دلیل حجم اشتراک کاربر؛
  //  • کندی دسترسی به سایت‌ها/اپ‌های داخلی (یک مسیر رفت‌وبرگشت اضافه تا خارج).
  // اینجا چند قانون سبک و بدون نیاز به فایل geo اضافه می‌کنیم.

  /// IP های خصوصی/محلی؛ مستقیم.
  static const _privateCidrs = [
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '169.254.0.0/16',
    '224.0.0.0/4',
  ];

  /// دامنه‌های داخلی؛ مستقیم (بدون مصرف حجم VPN). `domain:` همه‌ی زیردامنه‌ها را هم می‌گیرد.
  static const _directDomains = [
    'domain:ir',
    'domain:digikala.com',
    'domain:aparat.com',
    'domain:snapp.taxi',
    'domain:tapsi.cab',
    'domain:filimo.com',
    'domain:namava.ir',
  ];

  /// کانفیگ نهایی Xray (JSON) برای یک لینک vless.
  static String buildConfig(String link) {
    // کپی عمیق: نقشه‌ی افزونه ممکن است تغییرناپذیر باشد
    final cfg = jsonDecode(jsonEncode(FlutterVless.parse(link).fullConfiguration))
        as Map<String, dynamic>;
    _tune(cfg);
    return jsonEncode(cfg);
  }

  static void _tune(Map<String, dynamic> cfg) {
    // Sniffing فقط برای مسیریابی: مقصد بسته تغییر نمی‌کند و DNS دوباره حل نمی‌شود.
    final inbounds = cfg['inbounds'];
    if (inbounds is List) {
      for (final i in inbounds) {
        if (i is Map && i['sniffing'] is Map) {
          (i['sniffing'] as Map)['routeOnly'] = true;
        }
      }
    }

    cfg['routing'] = {
      'domainStrategy': 'AsIs',
      'rules': [
        {'type': 'field', 'ip': _privateCidrs, 'outboundTag': 'direct'},
        {'type': 'field', 'domain': _directDomains, 'outboundTag': 'direct'},
        // QUIC روی تونل UDP ناپایدار و کند است؛ بلاک کردنش مرورگر/یوتیوب را
        // سریع به TCP برمی‌گرداند (روش رایج کلاینت‌های V2Ray).
        {
          'type': 'field',
          'network': 'udp',
          'port': '443',
          'outboundTag': 'blackhole',
        },
      ],
    };
  }
}
