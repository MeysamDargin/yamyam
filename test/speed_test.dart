import 'package:flutter_test/flutter_test.dart';
import 'package:yamyam/core/ui.dart';

void main() {
  test('speedParts picks a readable unit', () {
    expect(speedParts(0).unit, 'کیلوبایت/ث');
    expect(speedParts(0).value, '۰٫۰');
    expect(speedParts(512 * 1024).value, '۵۱۲');
    expect(speedParts(512 * 1024).unit, 'کیلوبایت/ث');
    final fast = speedParts(2.5 * 1024 * 1024);
    expect(fast.unit, 'مگابایت/ث');
    expect(fast.value, '۲٫۵۰');
  });
}
