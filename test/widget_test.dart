import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zappart_pro/features/auth/login_page.dart';
import 'package:zappart_pro/services/auth_service.dart';
import 'package:zappart_pro/theme/app_theme.dart';

void main() {
  testWidgets('LoginPage builds without throwing', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>(
        create: (_) => throw StateError('should not be created'),
        lazy: true,
        child: MaterialApp(
          theme: AppTheme.build(),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Bon retour'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
