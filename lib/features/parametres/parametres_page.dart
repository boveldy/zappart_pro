import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Paramètres : fiche partenaire (lecture seule), coordonnées de versement,
/// compte. Les informations de la fiche (nom, adresse, commission, numéros de
/// versement) sont gérées par l'équipe Zappart — la modification se fait par le
/// support. Le partenaire garde la main sur sa session.
class ParametresPage extends StatelessWidget {
  const ParametresPage({super.key});

  static const _supportWhatsApp = 'https://wa.me/221769999999';
  static const _supportEmail = 'partenaires@zappart.app';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    final email = FirebaseAuth.instance.currentUser?.email ?? '—';

    return PageScaffold(
      title: 'Paramètres',
      subtitle: 'Fiche partenaire et compte',
      child: ref == null
          ? const EmptyState('Fiche partenaire en cours de liaison…')
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: ref.snapshots(),
              builder: (context, snap) {
                final m = snap.data?.data() ?? const <String, dynamic>{};
                final loading = !snap.hasData;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (loading)
                      const AppCard(child: SkeletonBox(height: 180))
                    else ...[
                      _Fiche(m: m),
                      const SizedBox(height: 16),
                      _Versement(m: m),
                      const SizedBox(height: 16),
                      _Compte(email: email, actif: m['actif'] == true),
                      const SizedBox(height: 16),
                      _Support(
                        onWhatsApp: () => _open(_supportWhatsApp),
                        onEmail: () => _open(
                            'mailto:$_supportEmail?subject=Modification%20fiche%20partenaire'),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);
  final String k;
  final String v;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ),
            Expanded(
              child: Text(v.isEmpty ? '—' : v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _Fiche extends StatelessWidget {
  const _Fiche({required this.m});
  final Map<String, dynamic> m;

  String _s(String k) => (m[k] as String?)?.trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final agence = _s('nomAgence');
    final nomComplet = '${_s('prenom')} ${_s('nom')}'.trim();
    final type = _s('typepartenaire');
    final service = _s('typeservice');
    final nbBiens = (m['nombreBiens'] as num?)?.toInt();

    return AppCard(
      title: 'Fiche partenaire',
      child: Column(
        children: [
          _KV('Nom', agence.isNotEmpty ? agence : nomComplet),
          if (agence.isNotEmpty && nomComplet.isNotEmpty)
            _KV('Responsable', nomComplet),
          _KV('Type', [type, if (service.isNotEmpty) service].join(' · ')),
          _KV('Téléphone', _s('telephone')),
          _KV('E-mail', _s('email')),
          _KV('Quartier', _s('quartier')),
          _KV('Adresse', _s('localisationTexte')),
          if (nbBiens != null) _KV('Biens déclarés', '$nbBiens'),
        ],
      ),
    );
  }
}

class _Versement extends StatelessWidget {
  const _Versement({required this.m});
  final Map<String, dynamic> m;

  String _s(String k) => (m[k] as String?)?.trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final base = _s('commission_base');
    final valeur = (m['commission_valeur'] as num?)?.toDouble();
    final commission = valeur == null
        ? '—'
        : base == 'pourcentage'
            ? '${valeur.toStringAsFixed(valeur % 1 == 0 ? 0 : 1)} %'
            : '${valeur.round()} FCFA';

    return AppCard(
      title: 'Facturation & versement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KV('Commission Zappart', commission),
          _KV('Numéro Wave', _s('wave_numero')),
          _KV('Numéro Orange Money / MaxIt', _s('max_it_numero')),
          const SizedBox(height: 8),
          const Text(
            'Le numéro de versement est confirmé à chaque demande de retrait '
            'dans l\'écran Revenus. Pour modifier la commission ou vos '
            'informations, contactez le support.',
            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _Compte extends StatelessWidget {
  const _Compte({required this.email, required this.actif});
  final String email;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Compte',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KV('Connecté en tant que', email),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const SizedBox(
                  width: 170,
                  child: Text('Statut',
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.inkSoft)),
                ),
                StatusChip(actif ? 'Actif' : 'En validation',
                    tone: actif ? 'ok' : 'wait'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.read<AuthService>().signOut(),
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Se déconnecter'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: Color(0xFFE3C9C4)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Support extends StatelessWidget {
  const _Support({required this.onWhatsApp, required this.onEmail});
  final VoidCallback onWhatsApp, onEmail;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Besoin de modifier une information ?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nom, adresse, commission, documents : l\'équipe Zappart met votre '
            'fiche à jour. Écrivez-nous.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onWhatsApp,
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('WhatsApp'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onEmail,
                icon: const Icon(Icons.mail_outline, size: 16),
                label: const Text('E-mail'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.ink,
                  side: const BorderSide(color: AppTheme.line),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
