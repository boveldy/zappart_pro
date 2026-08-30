import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Écran de section pas encore implémenté — pose la structure de page
/// (titre, sous-titre, zone de contenu) que chaque écran réel remplira.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
    this.plannedFor,
  });

  final String title;
  final String subtitle;
  final String? plannedFor;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.h1),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTheme.label),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: AppTheme.card,
            child: Column(
              children: [
                const Icon(Icons.construction_rounded,
                    size: 30, color: AppTheme.inkSoft),
                const SizedBox(height: 10),
                Text(
                  plannedFor == null
                      ? 'Écran à construire.'
                      : 'Écran à construire — $plannedFor.',
                  style: GoogleFonts.mavenPro(
                      fontSize: 13.5, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
