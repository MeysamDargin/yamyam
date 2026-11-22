import 'package:flutter/widgets.dart';
import 'package:yamyam/state/app_controller.dart';

/// دسترسی به [AppController] در درخت ویجت‌ها (بدون پکیج اضافه).
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  /// با listen=true ویجت با هر تغییر کنترلر rebuild می‌شود.
  static AppController of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AppScope>()
        : context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in context');
    return scope!.notifier!;
  }
}
