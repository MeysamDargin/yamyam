import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:yamyam/api/api.dart';
import 'package:yamyam/api/endpoint.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/models/plan_models.dart';
import 'package:yamyam/services/app_exception.dart';

/// ارتباط با پنل مدیریت YamYam.
class PanelService {
  PanelService({http.Client? client}) : _http = client;

  final http.Client? _http;

  Future<http.Response> _get(Uri uri, Duration timeout) {
    final headers = {'Accept': 'application/json'};
    final c = _http;
    return (c == null ? http.get(uri, headers: headers) : c.get(uri, headers: headers))
        .timeout(timeout);
  }

  /// کانفیگ خام (برای کش) + مدل پارس‌شده.
  Future<({String raw, AppConfig config})> fetchConfig() async {
    if (apiServerBaseUrl.isEmpty) {
      throw const AppException(
        'آدرس پنل تنظیم نشده است (apiServerBaseUrl در lib/api/api.dart)',
      );
    }
    final uri = buildApiUri(apiServerBaseUrl, Endpoint.panelConfig);
    try {
      final res = await _get(uri, const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw AppException('پاسخ نامعتبر از سرور (${res.statusCode})');
      }
      final raw = utf8.decode(res.bodyBytes);
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const AppException('فرمت پاسخ سرور نامعتبر است');
      }
      return (raw: raw, config: AppConfig.fromJson(json));
    } on TimeoutException {
      throw const AppException('پاسخی از سرور دریافت نشد. اینترنت را بررسی کنید.');
    } on SocketException {
      throw const AppException('اتصال به اینترنت برقرار نیست.');
    } on http.ClientException {
      throw const AppException('اتصال به سرور برقرار نشد.');
    } on FormatException {
      throw const AppException('فرمت پاسخ سرور نامعتبر است');
    }
  }

  // ===================================================================== //
  // پلن‌ها
  // ===================================================================== //

  /// درخواست JSON به پنل؛ خطاهای `{detail}` به پیام فارسی تبدیل می‌شود.
  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Uint8List? raw,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = buildApiUri(apiServerBaseUrl, path, queryParameters: query);
    try {
      final req = http.Request(method, uri)..headers['Accept'] = 'application/json';
      if (raw != null) {
        req.bodyBytes = raw;
        req.headers['Content-Type'] = 'application/octet-stream';
      } else if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final client = _http ?? http.Client();
      final http.Response res;
      try {
        res = await http.Response.fromStream(await client.send(req).timeout(timeout))
            .timeout(timeout);
      } finally {
        if (_http == null) client.close();
      }
      dynamic json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        json = null;
      }
      if (res.statusCode >= 200 && res.statusCode < 300 && json is Map<String, dynamic>) {
        return json;
      }
      var msg = '';
      if (json is Map) {
        final d = json['detail'];
        msg = d is String ? d : (d is List && d.isNotEmpty ? '${(d.first as Map)['msg'] ?? ''}' : '');
      }
      throw AppException(msg.isEmpty ? 'درخواست ناموفق بود (${res.statusCode})' : msg);
    } on TimeoutException {
      throw const AppException('پاسخی از سرور دریافت نشد. اینترنت را بررسی کنید.');
    } on SocketException {
      throw const AppException('اتصال به اینترنت برقرار نیست.');
    } on http.ClientException {
      throw const AppException('اتصال به سرور برقرار نشد.');
    }
  }

  /// وضعیت پلن (سبک؛ بدون اعمال روی سرورها).
  Future<({String raw, UserPlan plan})> fetchPlan(String uid, {int version = 0}) async {
    final j = await _json('GET', Endpoint.panelPlanMe,
        query: {'uid': uid, 'v': version});
    return (raw: jsonEncode(j), plan: UserPlan.fromJson(j));
  }

  /// وضعیت پلن + اعمال روی کلاینت‌های موجود (کلاینت‌های سرورهای [serverIds] یا همه).
  Future<({String raw, UserPlan plan})> syncPlan(
    String uid, {
    List<int>? serverIds,
    int version = 0,
  }) async {
    final j = await _json(
      'POST',
      Endpoint.panelPlanSync,
      body: {
        'uid': uid,
        if (serverIds != null) 'server_ids': serverIds,
        'app_version': version,
      },
      timeout: const Duration(seconds: 30),
    );
    return (raw: jsonEncode(j), plan: UserPlan.fromJson(j));
  }

  Future<OrderTicket> createOrder({
    required String uid,
    required int packageId,
    String trackingCode = '',
    String payerName = '',
    String payerCard = '',
    String note = '',
    int version = 0,
  }) async {
    final j = await _json('POST', Endpoint.panelPlanOrders, body: {
      'uid': uid,
      'package_id': packageId,
      'tracking_code': trackingCode,
      'payer_name': payerName,
      'payer_card': payerCard,
      'note': note,
      'app_version': version,
    });
    final o = j['order'];
    if (o is! Map || '${j['token'] ?? ''}'.isEmpty) {
      throw const AppException('پاسخ سرور نامعتبر است');
    }
    return OrderTicket(PlanOrder.fromJson(o.cast<String, dynamic>()), '${j['token']}');
  }

  Future<PlanOrder> uploadReceipt(int orderId, String token, Uint8List bytes) async {
    final j = await _json(
      'PUT',
      Endpoint.panelOrderReceipt(orderId),
      query: {'token': token},
      raw: bytes,
      timeout: const Duration(seconds: 60),
    );
    return PlanOrder.fromJson(j);
  }

  Future<PlanOrder> cancelOrder(int orderId, String token) async {
    final j = await _json('POST', Endpoint.panelOrderCancel(orderId),
        body: {'token': token});
    return PlanOrder.fromJson(j);
  }
}
