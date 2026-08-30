import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zappart_pro/features/auth/login_page.dart';
import 'package:zappart_pro/services/auth_service.dart';
import 'package:zappart_pro/theme/app_theme.dart';

void main() {
  testWidgets('LoginPage builds without throwing', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>(
        // lazy: not constructed unless read (LoginPage only reads it in
        // callbacks) → avoids needing a live Firebase App in the test.
        create: (_) => throw StateError('should not be created'),
        lazy: true,
        child: MaterialApp(theme: AppTheme.build(), home: const LoginPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
