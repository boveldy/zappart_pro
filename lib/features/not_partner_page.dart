import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Compte connecté mais sans `partenaire_ref` : soit un particulier, soit une
/// fiche partenaire pas encore liée par le trigger backend
/// `link_partenaire_from_user` (quelques secondes après création).
class NotPartnerPage extends StatelessWidget {
  const NotPartnerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 40, color: AppTheme.inkSoft),
                const SizedBox(height: 14),
                Text('Accès réservé aux partenaires',
                    textAlign: TextAlign.center, style: AppTheme.h2),
                const SizedBox(height: 8),
                Text(
                  'Le compte ${auth.user?.email ?? ''} n\'est rattaché à '
                  'aucune fiche partenaire. Si vous venez de vous inscrire, '
                  'patientez une minute puis actualisez.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.mavenPro(
                      fontSize: 13.5, color: AppTheme.inkSoft),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => auth.signOut(),
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
