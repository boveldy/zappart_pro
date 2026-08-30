import 'package:flutter_test/flutter_test.dart';
import 'package:zappart_pro/theme/app_theme.dart';

void main() {
  test('theme builds', () {
    final theme = AppTheme.build();
    expect(theme.scaffoldBackgroundColor, AppTheme.bg);
  });
}
