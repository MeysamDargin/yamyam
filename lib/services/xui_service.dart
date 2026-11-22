import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:yamyam/api/api.dart';
import 'package:yamyam/api/endpoint.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/models/client_account.dart';
import 'package:yamyam/models/client_stats.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/services/app_exception.dart';

/// کلاینت API پنل 3X-UI برای «یک» سرور (احراز هویت با توکن Bearer).
class XuiApi {
  final VpnServer server;
  XuiApi(this.server);

  /// آیا هنوز برای همین سرور/آدرس/توکن ساخته شده است؟
  bool matches(VpnServer s) =>
      s.id == server.id &&
      s.baseUrl == server.baseUrl &&
      s.apiToken == server.apiToken &&
      s.verifySsl == server.verifySsl;

  // یک کلاینت پایدار: اتصال TLS بین درخواست‌های پشت‌سرهم دوباره استفاده می‌شود
  // (کمتر handshake، کمتر حجم، سریع‌تر).
  late final http.Client _client = _newClient();

  void close() => _client.close();

  static const _gb = 1024 * 1024 * 1024;
  static const _day = 24 * 60 * 60 * 1000;

  http.Client _newClient() {
    if (server.verifySsl) return http.Client();
    // سرور با گواهی self-signed: فقط برای همین هاست پذیرفته می‌شود.
    final host = Uri.parse(server.baseUrl).host;
    return IOClient(
      HttpClient()..badCertificateCallback = (_, h, __) => h == host,
    );
  }

  /// درخواست عمومی؛ `obj` پاسخ `{success,msg,obj}` را برمی‌گرداند.
  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final token = server.apiToken;
    if (token == null || token.isEmpty) {
      throw const XuiException('توکن این سرور در پنل مشخص نشده است.');
    }
    final uri = buildApiUri(server.baseUrl, path);
    final client = _client;
    try {
      final req = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          if (body != null) 'Content-Type': 'application/json',
        });
      if (body != null) req.body = jsonEncode(body);

      final streamed = await client.send(req).timeout(const Duration(seconds: 15));
      final res = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 15));

      dynamic json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        // 3X-UI در صورت توکن/مسیر اشتباه 404 غیر JSON می‌دهد
        throw XuiException(
          'پاسخ نامعتبر از سرور (${res.statusCode}). آدرس یا توکن سرور را بررسی کنید.',
        );
      }
      if (json is! Map || json['success'] != true) {
        final msg = json is Map ? '${json['msg'] ?? ''}' : '';
        throw XuiException(
          msg.isEmpty ? 'درخواست ناموفق بود' : msg,
          apiError: true,
        );
      }
      return json['obj'];
    } on TimeoutException {
      throw const XuiException('سرور پاسخ نداد (timeout)', network: true);
    } on SocketException {
      throw const XuiException('اتصال به سرور برقرار نشد', network: true);
    } on HandshakeException {
      throw const XuiException('خطای SSL در اتصال به سرور', network: true);
    } on http.ClientException {
      throw const XuiException('اتصال به سرور برقرار نشد', network: true);
    }
  }

  // ------------------------------------------------------------------ //
  // Client
  // ------------------------------------------------------------------ //

  /// وضعیت کلاینت (مصرف، انقضا، فعال/غیرفعال).
  Future<ClientStats> getStats(String email) async {
    final obj = await _send('GET', Endpoint.xuiClientTraffic(email));
    if (obj is! Map) {
      throw const XuiException('کلاینت پیدا نشد', apiError: true);
    }
    return ClientStats.fromJson(obj.cast<String, dynamic>());
  }

  /// لینک‌های اتصال کلاینت (vless://, ...).
  Future<List<String>> getLinks(String email) async {
    final obj = await _send('GET', Endpoint.xuiClientLinks(email));
    return (obj is List ? obj : const []).map((e) => '$e').toList();
  }

  /// ساخت کلاینت روی اینباندِ تنظیم‌شده‌ی همین سرور.
  Future<ClientAccount> createClient({
    required String email,
    required ClientDefaults defaults,
    ServerSpec? spec,
  }) async {
    final flow = await _detectFlow();
    final now = DateTime.now().millisecondsSinceEpoch;
    final client = clientBody(
      email: email,
      flow: flow,
      defaults: defaults,
      spec: spec,
      nowMs: now,
    );

    try {
      await _send('POST', Endpoint.xuiClientAdd, body: {
        'client': client,
        'inboundIds': [server.inboundId],
      });
    } on XuiException catch (e) {
      if (!e.apiError) rethrow;
      // اگر ایمیل از قبل وجود داشته (مثلاً ثبت قبلی نیمه‌کاره) همان را استفاده کن
      try {
        await getStats(email);
      } on XuiException {
        throw XuiException('ساخت اکانت ناموفق بود: ${e.message}', apiError: true);
      }
    }

    final stats = await getStats(email);
    return ClientAccount(
      serverId: server.id,
      email: email,
      uuid: stats.uuid,
      baseUrl: server.baseUrl,
      inboundId: server.inboundId,
      createdAt: DateTime.now(),
    );
  }

  /// بدنه‌ی کلاینت جدید. اگر [spec] (پلن کاربر روی این سرور) باشد، همان اعمال می‌شود؛
  /// وگرنه پیش‌فرض‌های کلی پنل. (پنل بعد از ساخت هم یک‌بار همگام‌سازی می‌کند.)
  @visibleForTesting
  static Map<String, dynamic> clientBody({
    required String email,
    required String flow,
    required ClientDefaults defaults,
    ServerSpec? spec,
    required int nowMs,
  }) {
    if (spec == null) {
      return {
        'email': email,
        'enable': true,
        'flow': flow,
        'comment': 'yamyam-app',
        'totalGB': (defaults.trafficGb * _gb).round(),
        'expiryTime': defaults.expiryDays > 0 ? nowMs + defaults.expiryDays * _day : 0,
        'limitIp': defaults.limitIp,
        'tgId': 0,
      };
    }
    return {
      'email': email,
      'enable': spec.enabled,
      'flow': flow,
      'comment': 'yamyam-app',
      'totalGB': spec.totalBytes,
      'expiryTime': spec.expiryMs > 0
          ? spec.expiryMs
          : (spec.expiryDays > 0 ? nowMs + spec.expiryDays * _day : 0),
      'limitIp': spec.limitIp,
      'tgId': 0,
      'trafficReset': spec.reset,
      'reset': spec.dailyReset ? 1 : 0,
    };
  }

  /// افزودن حجم/روز به اشتراک (برای جایزه‌ی تبلیغات) با `bulkAdjust`.
  /// اگر فیلدِ مربوطه نامحدود باشد، پنل آن را رد می‌کند و [skipReason] پر می‌شود.
  Future<({int adjusted, String? skipReason})> adjustClient(
    String email, {
    int addBytes = 0,
    int addDays = 0,
  }) async {
    final obj = await _send('POST', Endpoint.xuiClientsBulkAdjust, body: {
      'emails': [email],
      if (addBytes != 0) 'addBytes': addBytes,
      if (addDays != 0) 'addDays': addDays,
    });
    final m = obj is Map ? obj : const {};
    final adjusted = (m['adjusted'] as num?)?.toInt() ?? 0;
    if (adjusted > 0) return (adjusted: adjusted, skipReason: null);
    final skipped = m['skipped'];
    if (skipped is List && skipped.isNotEmpty) {
      final f = skipped.first;
      final reason = f is Map ? '${f['reason'] ?? ''}' : '$f';
      return (adjusted: 0, skipReason: reason.isEmpty ? 'skipped' : reason);
    }
    throw const XuiException('جایزه اعمال نشد', apiError: true);
  }

  /// `flow` مناسب اینباند: اول از کلاینت‌های موجود، بعد VLESS+Reality+TCP → vision.
  Future<String> _detectFlow() async {
    try {
      final obj = await _send('GET', Endpoint.xuiInbound(server.inboundId));
      if (obj is! Map) return '';
      final settings = _asMap(obj['settings']);
      final clients = settings?['clients'];
      if (clients is List) {
        for (final c in clients) {
          final f = c is Map ? '${c['flow'] ?? ''}' : '';
          if (f.isNotEmpty) return f;
        }
      }
      final stream = _asMap(obj['streamSettings']);
      if ('${obj['protocol']}' == 'vless' &&
          '${stream?['security']}' == 'reality' &&
          '${stream?['network']}' == 'tcp') {
        return 'xtls-rprx-vision';
      }
    } on XuiException {
      // مهم نیست؛ بدون flow ادامه می‌دهیم
    }
    return '';
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return v.cast<String, dynamic>();
    if (v is String && v.isNotEmpty) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return d.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }
}
