import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Compte connecté sans fiche à lui, mais une invitation d'équipe ouverte porte
/// son e-mail → il rejoint l'agence (crée son `membres_pro/{uid}` et marque
/// l'invitation acceptée).
class RejoindrePage extends StatefulWidget {
  const RejoindrePage({super.key});

  @override
  State<RejoindrePage> createState() => _RejoindrePageState();
}

class _RejoindrePageState extends State<RejoindrePage> {
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AuthService>().acceptInvitation();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    // Succès : le routeur bascule tout seul (access → partner) via le
    // refreshListenable, dès que `membres_pro/{uid}` remonte.
  }

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
                const Icon(Icons.groups_2_outlined,
                    size: 40, color: AppTheme.inkSoft),
                const SizedBox(height: 14),
                Text('Vous avez été invité',
                    textAlign: TextAlign.center, style: AppTheme.h2),
                const SizedBox(height: 8),
                Text(
                  '${auth.inviteAgenceNom} vous invite à rejoindre son espace '
                  'Zappart Pro en tant que « ${auth.inviteRoleLabel} ».',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.mavenPro(
                      fontSize: 13.5, color: AppTheme.inkSoft),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.mavenPro(
                          fontSize: 12.5,
                          color: const Color(0xFF8A4033),
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _join,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Rejoindre ${auth.inviteAgenceNom}'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => auth.signOut(),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
