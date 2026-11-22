import 'package:flutter_test/flutter_test.dart';
import 'package:yamyam/platform/client_id.dart';

void main() {
  test('windows ids use yywin, tv uses yytv, phone stays yy', () {
    expect(clientIdPrefix(windows: true), 'yywin');
    expect(clientIdPrefix(tv: true), 'yytv');
    expect(clientIdPrefix(windows: true, tv: true), 'yytv');
    expect(clientIdPrefix(windows: false, tv: false), 'yy');
  });
}
