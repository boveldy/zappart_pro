import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui.dart';
import '../../data/bail.dart';
import '../../services/abonnement.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

const _kWa = 'https://wa.me/221772356313';
final _fmt = NumberFormat('#,###', 'fr_FR');

String _waPassage(Formule f) {
  final nom = switch (f) {
    Formule.gerant => 'Gérant',
    Formule.agence => 'Agence',
    Formule.agencePlus => 'Agence Plus',
    Formule.reseau => 'Réseau',
    Formule.decouverte => 'Découverte',
  };
  return '$_kWa?text=Bonjour%2C%20je%20veux%20passer%20au%20plan%20$nom%20de%20ZappArt%20Pro.';
}

/// Page « Mon abonnement » : forfait courant, jauge de quota, liste des plans.
/// Le paiement en ligne (GeniusPay `type=='abonnement'`) n'est pas encore
/// câblé → les boutons ouvrent WhatsApp, l'admin active le forfait.
class AbonnementPage extends StatelessWidget {
  const AbonnementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final abo = auth.abonnement;
    final ref = auth.partenaireRef;

    return PageScaffold(
      title: 'Mon abonnement',
      subtitle: 'Forfait, quota de baux et options',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (ref == null)
            const AppCard(child: EmptyState('Fiche partenaire introuvable.'))
          else
            StreamBuilder<List<Bail>>(
              stream: BailRepository(ref).baux(),
              builder: (context, snap) {
                final actifs =
                    (snap.data ?? const []).where((b) => b.actif).length;
                return _CurrentPlanCard(abo: abo, bauxActifs: actifs);
              },
            ),
          const SizedBox(height: 22),
          Text('Tous les forfaits',
              style: GoogleFonts.mavenPro(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'On compte en baux actifs, pas en biens. Publier sur la marketplace '
            'reste gratuit. Au-delà du quota, les baux en cours continuent — '
            'seule la création d\'un nouveau bail est bloquée.',
            style: GoogleFonts.mavenPro(
                fontSize: 12.5, color: AppTheme.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 14),
          for (final p in PlanInfo.tous)
            _PlanCard(plan: p, courant: p.formule == abo.formule),
          const SizedBox(height: 10),
          Text(
            'Le règlement en ligne (Wave / Orange Money) arrive bientôt. '
            'Pour l\'instant, le passage se fait via l\'équipe Zappart.',
            style: GoogleFonts.mavenPro(
                fontSize: 11.5, color: AppTheme.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.abo, required this.bauxActifs});
  final Abonnement abo;
  final int bauxActifs;

  @override
  Widget build(BuildContext context) {
    final quota = abo.quotaBaux;
    final ratio = quota <= 0 ? 0.0 : (bauxActifs / quota).clamp(0.0, 1.0);
    final proche = quota < 1000 && bauxActifs >= quota;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(abo.label,
                  style: GoogleFonts.mavenPro(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (abo.fondateur) const _Tag('Fondateur · −40 %'),
              const Spacer(),
              Text(
                abo.estPayant
                    ? '${_fmt.format(abo.prixMensuel)} FCFA / mois'
                    : 'Gratuit',
                style: GoogleFonts.mavenPro(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Baux actifs',
                  style: GoogleFonts.mavenPro(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
              const Spacer(),
              Text(
                quota >= 1000 ? '$bauxActifs' : '$bauxActifs / $quota',
                style: GoogleFonts.mavenPro(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: quota >= 1000 ? 0 : ratio,
              minHeight: 8,
              backgroundColor: AppTheme.panel,
              color: proche ? AppTheme.danger : AppTheme.ink,
            ),
          ),
          if (proche) ...[
            const SizedBox(height: 10),
            _Notice(
              'Quota atteint — passez au forfait supérieur pour créer de '
              'nouveaux baux.',
              danger: true,
            ),
          ],
          if (abo.expire) ...[
            const SizedBox(height: 10),
            _Notice(
              abo.bloqueCreation
                  ? 'Abonnement expiré. Création de bail bloquée jusqu\'au '
                      'renouvellement.'
                  : 'Abonnement expiré — période de grâce (7 jours). Pensez à '
                      'renouveler.',
              danger: abo.bloqueCreation,
            ),
          ] else if (abo.estPayant && (abo.joursRestants ?? 99) <= 7) ...[
            const SizedBox(height: 10),
            _Notice('Renouvellement dans ${abo.joursRestants} jour(s).'),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (abo.estPayant)
                OutlinedButton(
                  onPressed: () => _open(_waPassage(abo.formule)),
                  child: const Text('Renouveler'),
                ),
              if (abo.formule != Formule.reseau)
                ElevatedButton(
                  onPressed: () => _open(_waPassage(
                      Formule.values[abo.formule.index + 1])),
                  child: Text('Passer à '
                      '${Abonnement(Formule.values[abo.formule.index + 1]).label}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.courant});
  final PlanInfo plan;
  final bool courant;

  @override
  Widget build(BuildContext context) {
    final a = Abonnement(plan.formule);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: courant ? AppTheme.ink : AppTheme.line,
            width: courant ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(a.label,
                  style: GoogleFonts.mavenPro(
                      fontSize: 15.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (courant) const _Tag('Forfait actuel'),
              const Spacer(),
              Text(
                plan.prix < 0
                    ? 'Sur devis'
                    : plan.prix == 0
                        ? 'Gratuit'
                        : '${_fmt.format(plan.prix)} FCFA / mois',
                style: GoogleFonts.mavenPro(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(plan.quota,
              style: GoogleFonts.mavenPro(
                  fontSize: 12, color: AppTheme.inkSoft)),
          const SizedBox(height: 10),
          for (final av in plan.avantages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: 14, color: AppTheme.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(av,
                        style: GoogleFonts.mavenPro(
                            fontSize: 12.5, color: AppTheme.ink)),
                  ),
                ],
              ),
            ),
          if (!courant) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => _open(plan.formule == Formule.reseau
                    ? '$_kWa?text=Bonjour%2C%20je%20veux%20un%20devis%20ZappArt%20Pro%20R%C3%A9seau.'
                    : _waPassage(plan.formule)),
                child: Text(plan.formule == Formule.reseau
                    ? 'Demander un devis'
                    : 'Choisir ${a.label}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _open(String url) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: GoogleFonts.mavenPro(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink)),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.danger = false});
  final String text;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final c = danger ? AppTheme.danger : AppTheme.inkSoft;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: danger
            ? AppTheme.danger.withValues(alpha: 0.06)
            : AppTheme.panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(danger ? Icons.warning_amber_rounded : Icons.info_outline,
              size: 15, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.mavenPro(
                    fontSize: 12, color: c, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// Encart d'incitation à monter en gamme, affiché à la place d'une
/// fonctionnalité réservée (statistiques, vues d'annonces…).
class AboUpsell extends StatelessWidget {
  const AboUpsell({
    super.key,
    required this.titre,
    required this.detail,
    this.formuleRequise = Formule.agence,
  });

  final String titre;
  final String detail;
  final Formule formuleRequise;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: AppTheme.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(titre,
                    style: GoogleFonts.mavenPro(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$detail\n\nInclus à partir du forfait '
            '${Abonnement(formuleRequise).label}.',
            style: GoogleFonts.mavenPro(
                fontSize: 12.5, color: AppTheme.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => context.go('/abonnement'),
            child: const Text('Voir les forfaits'),
          ),
        ],
      ),
    );
  }
}
