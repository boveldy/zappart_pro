import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../theme/brand.dart';

/// Affiché sous ~720 px de large. Zappart Pro est un outil de bureau ; la
/// gestion mobile passe par l'espace partenaire de l'app Zappart. Version
/// provisoire — un vrai support mobile sera décidé plus tard.
class MobileBlockedPage extends StatelessWidget {
  const MobileBlockedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ZappartWordmark(height: 30),
                const SizedBox(height: 28),
                const Icon(Icons.desktop_windows_outlined,
                    size: 40, color: AppTheme.inkSoft),
                const SizedBox(height: 18),
                Text(
                  'Zappart Pro se consulte sur ordinateur',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.mavenPro(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'L\'espace de gestion (parc, calendrier, réservations, '
                  'revenus) est prévu pour un écran large. Ouvrez ce lien '
                  'depuis un ordinateur.\n\nSur téléphone, utilisez l\'espace '
                  'partenaire de l\'application Zappart.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.mavenPro(
                      fontSize: 13.5, height: 1.5, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
