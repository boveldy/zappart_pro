import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui.dart';
import '../../services/abonnement.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Paramètres : identité de l'agence, facturation, abonnement, compte.
///
/// Tout est en **lecture seule** (nom, adresse, commission, numéros de
/// versement gérés par l'équipe Zappart) — sauf le **logo**, que le partenaire
/// change lui-même (règle Firestore `Partenaires` : `affectedKeys().hasOnly
/// (['logo'])`), et la session.
class ParametresPage extends StatelessWidget {
  const ParametresPage({super.key});

  // TODO(support) : remplacer par les vrais canaux support partenaires.
  static const _supportWhatsApp = 'https://wa.me/221769999999';
  static const _supportEmail = 'partenaires@zappart.app';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    final email = FirebaseAuth.instance.currentUser?.email ?? '—';

    return PageScaffold(
      title: 'Paramètres',
      subtitle: 'Identité de l\'agence, facturation et compte',
      child: ref == null
          ? const EmptyState('Fiche partenaire en cours de liaison…')
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: ref.snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Column(
                    children: [
                      SkeletonBox(height: 108),
                      SizedBox(height: 16),
                      SkeletonBox(height: 220),
                      SizedBox(height: 16),
                      SkeletonBox(height: 160),
                    ],
                  );
                }
                final m = snap.data!.data() ?? const <String, dynamic>{};
                return _Body(
                  m: m,
                  partnerRef: ref,
                  connexionEmail: email,
                  abonnement: auth.abonnement,
                  onWhatsApp: () => _open(_supportWhatsApp),
                  onEmail: () => _open(
                      'mailto:$_supportEmail?subject=Modification%20fiche%20partenaire'),
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

class _Body extends StatelessWidget {
  const _Body({
    required this.m,
    required this.partnerRef,
    required this.connexionEmail,
    required this.abonnement,
    required this.onWhatsApp,
    required this.onEmail,
  });

  final Map<String, dynamic> m;
  final DocumentReference<Map<String, dynamic>> partnerRef;
  final String connexionEmail;
  final Abonnement abonnement;
  final VoidCallback onWhatsApp;
  final VoidCallback onEmail;

  String _s(String k) => (m[k] as String?)?.trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final agence = _s('nomAgence');
    final responsable = '${_s('prenom')} ${_s('nom')}'.trim();
    final nom = agence.isNotEmpty ? agence : responsable;
    final type = [
      _s('typepartenaire'),
      if (_s('typeservice').isNotEmpty) _s('typeservice'),
    ].where((e) => e.isNotEmpty).join(' · ');
    final actif = m['actif'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IdentityHeader(
          nom: nom.isEmpty ? 'Agence' : nom,
          type: type,
          logo: _s('logo'),
          actif: actif,
          abonnement: abonnement,
          partnerRef: partnerRef,
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Identité & contact',
          child: Column(
            children: [
              if (agence.isNotEmpty && responsable.isNotEmpty)
                _Kv('Responsable', responsable),
              _Kv('Type', type),
              _Kv('Téléphone', _s('telephone')),
              _Kv('E-mail', _s('email')),
              _Kv('Quartier', _s('quartier')),
              _Kv('Adresse', _s('localisationTexte'), last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Facturation(m: m, partnerRef: partnerRef),
        const SizedBox(height: 16),
        _AbonnementCard(abonnement: abonnement),
        const SizedBox(height: 16),
        _CompteCard(email: connexionEmail, actif: actif),
        const SizedBox(height: 16),
        _SupportBanner(onWhatsApp: onWhatsApp, onEmail: onEmail),
      ],
    );
  }
}

// ── En-tête identité + changement de logo ───────────────────────────────────

class _IdentityHeader extends StatefulWidget {
  const _IdentityHeader({
    required this.nom,
    required this.type,
    required this.logo,
    required this.actif,
    required this.abonnement,
    required this.partnerRef,
  });

  final String nom;
  final String type;
  final String logo;
  final bool actif;
  final Abonnement abonnement;
  final DocumentReference<Map<String, dynamic>> partnerRef;

  @override
  State<_IdentityHeader> createState() => _IdentityHeaderState();
}

class _IdentityHeaderState extends State<_IdentityHeader> {
  bool _busy = false;

  Future<void> _changerLogo() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 82,
    );
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final storageRef =
          FirebaseStorage.instance.ref('Partenaires/${widget.partnerRef.id}/logo.jpg');
      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await storageRef.getDownloadURL();
      // Seul `logo` change → passe la règle Firestore hôte/prestataire.
      await widget.partnerRef.set({'logo': url}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logo mis à jour.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de mettre à jour le logo.')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final initiale =
        widget.nom.isNotEmpty ? widget.nom.characters.first.toUpperCase() : '?';
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
            logo: widget.logo,
            initiale: initiale,
            busy: _busy,
            onTap: _busy ? null : _changerLogo,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.nom,
                    style: GoogleFonts.mavenPro(
                        fontSize: 19, fontWeight: FontWeight.w800, height: 1.15)),
                if (widget.type.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(widget.type,
                      style: GoogleFonts.mavenPro(
                          fontSize: 12.5, color: AppTheme.inkSoft)),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusChip(widget.actif ? 'Compte actif' : 'En validation',
                        tone: widget.actif ? 'ok' : 'wait'),
                    StatusChip('Forfait ${widget.abonnement.label}', tone: 'ink'),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _busy ? null : _changerLogo,
                  icon: const Icon(Icons.photo_camera_outlined, size: 15),
                  label: Text(widget.logo.isEmpty
                      ? 'Ajouter un logo'
                      : 'Changer le logo'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.ink,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.logo,
    required this.initiale,
    required this.busy,
    required this.onTap,
  });
  final String logo;
  final String initiale;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppTheme.ink,
          borderRadius: BorderRadius.circular(16),
          image: logo.isNotEmpty
              ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover)
              : null,
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : logo.isEmpty
                ? Text(initiale,
                    style: GoogleFonts.mavenPro(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white))
                : null,
      ),
    );
  }
}

// ── Facturation & versement ────────────────────────────────────────────────

class _Facturation extends StatelessWidget {
  const _Facturation({required this.m, required this.partnerRef});
  final Map<String, dynamic> m;
  final DocumentReference<Map<String, dynamic>> partnerRef;

  String _s(String k) => (m[k] as String?)?.trim() ?? '';

  /// L'agence a-t-elle au moins un bien sur le marketplace (soumis ou publié) ?
  /// Sinon elle ne fait que de la gérance → la commission marketplace ne la
  /// concerne pas, on masque la ligne.
  Future<bool> _faitDuMarketplace() async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('house')
          .where('partenaireId', isEqualTo: partnerRef)
          .get();
      return q.docs.any((d) {
        final sv = (d.data()['statut_validation'] as String?)?.trim() ?? '';
        return sv != 'prive' && sv != 'supprimee' && sv.isNotEmpty;
      });
    } catch (_) {
      return true; // en cas de doute, on affiche
    }
  }

  String _commissionLabel() {
    final base = _s('commission_base');
    final valeur = (m['commission_valeur'] as num?)?.toDouble();
    if (valeur == null || valeur <= 0) return 'Définie par Zappart';
    final v = valeur.toStringAsFixed(valeur % 1 == 0 ? 0 : 1);
    return base == 'pourcent' ? '$v % du loyer' : '$v mois de loyer';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _faitDuMarketplace(),
      builder: (context, snap) {
        final marketplace = snap.data ?? false;
        return AppCard(
          title: marketplace ? 'Facturation & versement' : 'Versement',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (marketplace) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Commission mensuelle Zappart',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.inkSoft)),
                          ),
                          Text(_commissionLabel(),
                              style: GoogleFonts.mavenPro(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'S\'applique quand un client prend un de vos biens en '
                        'bail via le marketplace : c\'est la part du 1ᵉʳ mois de '
                        'commission que Zappart conserve (le reste vous est '
                        'reversé). Le journalier n\'est pas concerné.',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.inkSoft, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _Kv('Numéro Wave', _s('wave_numero')),
              _Kv('Orange Money / MaxIt', _s('max_it_numero'), last: true),
              const SizedBox(height: 10),
              const Text(
                'Le numéro de versement est reconfirmé à chaque demande de '
                'retrait dans Revenus. Ces informations sont modifiées par le '
                'support.',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.inkSoft, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Abonnement ─────────────────────────────────────────────────────────────

class _AbonnementCard extends StatelessWidget {
  const _AbonnementCard({required this.abonnement});
  final Abonnement abonnement;

  @override
  Widget build(BuildContext context) {
    final a = abonnement;
    final df = DateFormat('d MMM yyyy', 'fr');
    final quota = a.quotaBaux >= 1000 ? 'baux illimités' : '${a.quotaBaux} baux actifs';
    final echeance = a.actifJusqu == null
        ? (a.estPayant ? null : 'Gratuit — sans limite de durée')
        : (a.expire
            ? 'Expiré le ${df.format(a.actifJusqu!)}'
            : 'Renouvellement le ${df.format(a.actifJusqu!)}');

    return AppCard(
      title: 'Abonnement',
      trailing: TextButton(
        onPressed: () => context.go('/abonnement'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.ink,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        child: const Text('Gérer'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(a.label,
                  style: GoogleFonts.mavenPro(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('· $quota',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ],
          ),
          if (echeance != null) ...[
            const SizedBox(height: 4),
            Text(echeance,
                style: TextStyle(
                    fontSize: 12.5,
                    color: a.expire ? AppTheme.danger : AppTheme.inkSoft,
                    fontWeight: a.expire ? FontWeight.w700 : FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

// ── Compte ─────────────────────────────────────────────────────────────────

class _CompteCard extends StatelessWidget {
  const _CompteCard({required this.email, required this.actif});
  final String email;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Compte',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Kv('Connecté avec', email),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Statut de la fiche',
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.inkSoft)),
                ),
                StatusChip(actif ? 'Actif' : 'En validation',
                    tone: actif ? 'ok' : 'wait'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => context.read<AuthService>().signOut(),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Se déconnecter'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: Color(0xFFE3C9C4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bandeau support ────────────────────────────────────────────────────────

class _SupportBanner extends StatelessWidget {
  const _SupportBanner({required this.onWhatsApp, required this.onEmail});
  final VoidCallback onWhatsApp;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Une information à corriger ?',
              style: GoogleFonts.mavenPro(
                  fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Nom, adresse, commission, coordonnées de versement, documents : '
            'l\'équipe Zappart met votre fiche à jour.',
            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: onWhatsApp,
                icon: const Icon(Icons.chat_bubble_outline, size: 15),
                label: const Text('WhatsApp'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onEmail,
                icon: const Icon(Icons.mail_outline, size: 15),
                label: const Text('E-mail'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.ink,
                  side: const BorderSide(color: AppTheme.line),
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

// ── Ligne clé / valeur (filet fin, cohérent avec fiche_bail_page) ──────────

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.last = false});
  final String k;
  final String v;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F1F1))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ),
            Expanded(
              flex: 3,
              child: Text(v.trim().isEmpty ? '—' : v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
