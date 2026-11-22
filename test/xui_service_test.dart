import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yamyam/models/app_config.dart';
import 'package:yamyam/services/app_exception.dart';
import 'package:yamyam/services/xui_service.dart';

/// یک 3X-UI ساختگی: توکن Bearer، افزودن/دریافت کلاینت، ترافیک و لینک.
class FakeXui {
  late HttpServer server;
  final clients = <String, Map<String, dynamic>>{};
  final requests = <String>[];
  Map<String, dynamic>? lastAddBody;
  Map<String, dynamic>? lastAdjustBody;

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      requests.add('${req.method} ${req.uri.path}');
      Future<void> reply(Object body, {int code = 200}) async {
        req.response.statusCode = code;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      }

      if (req.headers.value('authorization') != 'Bearer good') {
        req.response.statusCode = 404;
        req.response.write('404 page not found');
        await req.response.close();
        return;
      }
      final p = req.uri.path.replaceFirst('/xui', '');
      if (p == '/panel/api/inbounds/get/3') {
        return reply({
          'success': true,
          'obj': {
            'id': 3, 'protocol': 'vless',
            'settings': {'clients': []},
            'streamSettings': jsonEncode({'network': 'tcp', 'security': 'reality'}),
          },
        });
      }
      if (p == '/panel/api/clients/add') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        lastAddBody = body;
        final c = body['client'] as Map<String, dynamic>;
        if (clients.containsKey(c['email'])) {
          return reply({'success': false, 'msg': 'Duplicate email'});
        }
        clients[c['email'] as String] = {
          ...c, 'uuid': 'uuid-${clients.length + 1}', 'up': 0, 'down': 0,
        };
        return reply({'success': true, 'msg': 'Client added'});
      }
      if (p == '/panel/api/clients/bulkAdjust') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        lastAdjustBody = body;
        final email = (body['emails'] as List).first as String;
        final c = clients[email];
        if (c == null) return reply({'success': true, 'obj': {'adjusted': 0, 'skipped': []}});
        if ((c['totalGB'] ?? 0) == 0 && body['addBytes'] != null) {
          return reply({
            'success': true,
            'obj': {
              'adjusted': 0,
              'skipped': [
                {'email': email, 'reason': 'unlimited traffic'},
              ],
            },
          });
        }
        if (body['addBytes'] != null) {
          c['totalGB'] = (c['totalGB'] as int) + (body['addBytes'] as int);
        }
        return reply({'success': true, 'obj': {'adjusted': 1, 'skipped': []}});
      }
      final m = RegExp(r'^/panel/api/clients/(traffic|links)/(.+)$').firstMatch(p);
      if (m != null) {
        final c = clients[Uri.decodeComponent(m.group(2)!)];
        if (c == null) return reply({'success': false, 'msg': 'record not found'});
        if (m.group(1) == 'traffic') {
          return reply({
            'success': true,
            'obj': {
              'email': c['email'], 'uuid': c['uuid'], 'enable': c['enable'],
              'up': 10, 'down': 20, 'total': c['totalGB'], 'expiryTime': c['expiryTime'],
              'lastOnline': 0,
            },
          });
        }
        return reply({'success': true, 'obj': ['vless://${c['uuid']}@host:443?type=tcp#${c['email']}']});
      }
      await reply({'success': false, 'msg': 'unknown'});
    });
  }

  VpnServer vpn({String token = 'good', int inbound = 3}) => VpnServer(
        id: 1, title: 't', country: 'c', countryCode: 'DE', flag: '🇩🇪',
        baseUrl: 'http://127.0.0.1:${server.port}/xui', inboundId: inbound,
        priority: 0, verifySsl: true, apiToken: token,
      );

  Future<void> stop() => server.close(force: true);
}

void main() {
  late FakeXui xui;
  setUp(() async => (xui = FakeXui())..start());
  tearDown(() => xui.stop());

  test('createClient attaches to the configured inbound with defaults + reality flow', () async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final api = XuiApi(xui.vpn());
    final acc = await api.createClient(
      email: 'yy-abc',
      defaults: const ClientDefaults(trafficGb: 2, expiryDays: 30, limitIp: 1),
    );

    expect(acc.email, 'yy-abc');
    expect(acc.uuid, 'uuid-1');
    expect(acc.inboundId, 3);

    final body = xui.lastAddBody!;
    expect(body['inboundIds'], [3]);
    final c = body['client'] as Map<String, dynamic>;
    expect(c['totalGB'], 2 * 1024 * 1024 * 1024);
    expect(c['limitIp'], 1);
    expect(c['flow'], 'xtls-rprx-vision'); // detected from reality+tcp inbound
    expect(c['expiryTime'] as int, greaterThan(DateTime.now().millisecondsSinceEpoch));
  });

  test('stats + links + idempotent re-create', () async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final api = XuiApi(xui.vpn());
    await api.createClient(email: 'a@b', defaults: const ClientDefaults());
    // creating again (duplicate email) must not fail — it reuses the existing client
    final again = await api.createClient(email: 'a@b', defaults: const ClientDefaults());
    expect(again.uuid, 'uuid-1');

    final stats = await api.getStats('a@b');
    expect(stats.used, 30);
    expect(stats.unlimitedTraffic, isTrue);
    expect(stats.canConnect, isTrue);

    final links = await api.getLinks('a@b');
    expect(links.single, startsWith('vless://uuid-1@host:443'));
  });

  test('adjustClient (ad rewards): adds bytes/days; unlimited is skipped with a reason', () async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final api = XuiApi(xui.vpn());
    await api.createClient(
      email: 'r@b',
      defaults: const ClientDefaults(trafficGb: 1, expiryDays: 30, limitIp: 1),
    );
    final r = await api.adjustClient('r@b', addBytes: 500 * 1024 * 1024, addDays: 2);
    expect(r.adjusted, 1);
    expect(r.skipReason, isNull);
    expect(xui.lastAdjustBody, {
      'emails': ['r@b'],
      'addBytes': 500 * 1024 * 1024,
      'addDays': 2,
    });
    expect(xui.clients['r@b']!['totalGB'], 1024 * 1024 * 1024 + 500 * 1024 * 1024);

    // فقط روز: addBytes ارسال نمی‌شود
    await api.adjustClient('r@b', addDays: 1);
    expect(xui.lastAdjustBody!.containsKey('addBytes'), isFalse);

    // حجم نامحدود: اعمال نمی‌شود ولی دلیلش برمی‌گردد
    await api.createClient(email: 'u@b', defaults: const ClientDefaults(trafficGb: 0, expiryDays: 30));
    final u = await api.adjustClient('u@b', addBytes: 1024);
    expect(u.adjusted, 0);
    expect(u.skipReason, contains('unlimited'));

    // کلاینت ناموجود: خطا
    await expectLater(
      api.adjustClient('nobody', addDays: 1),
      throwsA(isA<XuiException>().having((e) => e.apiError, 'apiError', true)),
    );
  });

  test('missing client → apiError; wrong token → non-network error; offline → network', () async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await expectLater(
      XuiApi(xui.vpn()).getStats('nobody'),
      throwsA(isA<XuiException>().having((e) => e.apiError, 'apiError', true)),
    );
    await expectLater(
      XuiApi(xui.vpn(token: 'bad')).getStats('x'),
      throwsA(isA<XuiException>()
          .having((e) => e.apiError, 'apiError', false)
          .having((e) => e.network, 'network', false)),
    );
    final dead = xui.vpn();
    await xui.stop();
    await expectLater(
      XuiApi(dead).getStats('x'),
      throwsA(isA<XuiException>().having((e) => e.network, 'network', true)),
    );
  });
}
