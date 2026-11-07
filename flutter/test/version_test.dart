import 'package:flutter_test/flutter_test.dart';
import 'package:svitlo/main.dart';

void main() {
  test('isNewerVersion', () {
    expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('1.2.10', '1.2.9'), isTrue);
    expect(isNewerVersion('2.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
  });
}
