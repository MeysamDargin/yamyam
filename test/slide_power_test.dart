import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamyam/models/vpn_status.dart';
import 'package:yamyam/widgets/slide_power.dart';

Widget _host(
  VpnStatus st,
  Future<void> Function() onToggle,
  ValueNotifier<double> p, {
  TargetPlatform platform = TargetPlatform.android,
}) =>
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SlidePower(
                status: st,
                colorA: Colors.green,
                colorB: Colors.teal,
                dark: false,
                progress: p,
                onToggle: onToggle,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('dragging past the threshold toggles; short drag springs back', (t) async {
    var calls = 0;
    final p = ValueNotifier<double>(0);
    await t.pumpWidget(_host(VpnStatus.disconnected, () async => calls++, p));

    // RTL: دستگیره سمت راست است و به چپ کشیده می‌شود
    await t.drag(find.byIcon(Icons.power_settings_new_rounded), const Offset(-60, 0));
    // فنر در اولین فریم فقط «شروع» می‌شود؛ فریم بعدی مقدارِ نشسته‌اش را نشان می‌دهد
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(calls, 0);
    expect(p.value, closeTo(0, 0.01));

    await t.drag(find.byIcon(Icons.power_settings_new_rounded), const Offset(-300, 0));
    await t.pump();
    expect(calls, 1);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('tap on phone does not toggle (only a hint nudge)', (t) async {
    var calls = 0;
    await t.pumpWidget(_host(VpnStatus.disconnected, () async => calls++, ValueNotifier(0)));
    await t.tap(find.byIcon(Icons.power_settings_new_rounded));
    await t.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });

  testWidgets('a click on desktop slides the knob and toggles', (t) async {
    var calls = 0;
    final connect = Completer<void>();
    final p = ValueNotifier<double>(0);
    await t.pumpWidget(_host(
      VpnStatus.disconnected,
      () {
        calls++;
        return connect.future;
      },
      p,
      platform: TargetPlatform.windows,
    ));
    await t.tap(find.byType(SlidePower));
    await t.pump();
    expect(calls, 1);
    await t.pump(const Duration(milliseconds: 500));
    expect(p.value, greaterThan(0.9));
    connect.complete();
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    final disconnect = Completer<void>();
    await t.pumpWidget(_host(
      VpnStatus.connected,
      () {
        calls++;
        return disconnect.future;
      },
      p,
      platform: TargetPlatform.linux,
    ));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byType(SlidePower));
    await t.pump();
    expect(calls, 2);
    await t.pump(const Duration(milliseconds: 500));
    expect(p.value, lessThan(0.1));
    disconnect.complete();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('connected: drag back disconnects; connecting: tap cancels', (t) async {
    var calls = 0;
    final p = ValueNotifier<double>(1);
    await t.pumpWidget(_host(VpnStatus.connected, () async => calls++, p));
    await t.pump();
    expect(p.value, closeTo(1, 0.01));
    await t.drag(find.byType(SlidePower), const Offset(300, 0));
    await t.pump();
    expect(calls, 1);
    await t.pump(const Duration(seconds: 1));

    await t.pumpWidget(_host(VpnStatus.connecting, () async => calls++, p));
    await t.pump();
    await t.tap(find.byType(SlidePower));
    await t.pump();
    expect(calls, 2);
    await t.pump(const Duration(seconds: 1));
  });
}
