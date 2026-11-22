import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yamyam/core/ui.dart';
import 'package:yamyam/platform/tv_platform.dart';
import 'package:yamyam/screen/splash_page.dart';
import 'package:yamyam/services/storage_service.dart';
import 'package:yamyam/state/app_controller.dart';
import 'package:yamyam/state/app_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TvPlatform.detect();

  final storage = await StorageService.open();
  final controller = AppController(storage: storage);
  // راه‌اندازی هم‌زمان با نمایش اسپلش (دریافت کانفیگ پنل، init هسته‌ی VPN، ...)
  unawaited(controller.start());

  runApp(AppScope(controller: controller, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Yamyam',
      theme: ThemeData(
        fontFamily: kAppFont,
        // فونت اپ روی همه‌ی دکمه‌ها (ButtonStyle از fontFamily تم ارث نمی‌برد)
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            textStyle: const TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            textStyle: const TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: const TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // کل اپ راست‌به‌چپ (دیالوگ‌ها و شیت‌ها هم)
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const SplashPage(),
    );
  }
}
