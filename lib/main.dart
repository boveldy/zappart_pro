import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'features/mobile_blocked_page.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await initializeDateFormatting('fr', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  runApp(const ZappartProApp());
}

class ZappartProApp extends StatefulWidget {
  const ZappartProApp({super.key});

  @override
  State<ZappartProApp> createState() => _ZappartProAppState();
}

class _ZappartProAppState extends State<ZappartProApp> {
  late final AuthService _auth = AuthService();
  late final _router = buildRouter(_auth);

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthService>.value(
      value: _auth,
      child: MaterialApp.router(
        title: 'Zappart Pro',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        routerConfig: _router,
        builder: (context, child) {
          // Zappart Pro = outil de bureau. Sous 720 px, page d'information
          // (provisoire) au lieu de l'app.
          if (MediaQuery.sizeOf(context).width < 720) {
            return const MobileBlockedPage();
          }
          return child ?? const SizedBox.shrink();
        },
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
