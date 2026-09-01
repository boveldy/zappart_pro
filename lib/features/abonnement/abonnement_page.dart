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
import '../../services/paiement_service.dart';
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

String _formuleCode(Formule f) => switch (f) {
      Formule.gerant => 'gerant',
      Formule.agence => 'agence',
      Formule.agencePlus => 'agence_plus',
      Formule.reseau => 'reseau',
      Formule.decouverte => 'decouverte',
    };

Future<void> _open(String url) async =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Page « Mon abonnement » : forfait courant, jauge de quota, liste des plans,
/// paiement en ligne (si `paiement_en_ligne_actif`) ou passage via WhatsApp.
class AbonnementPage extends StatefulWidget {
  const AbonnementPage({super.key});

  @override
  State<AbonnementPage> createState() => _AbonnementPageState();
}

class _AbonnementPageState extends State<AbonnementPage> {
  bool _annuel = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final abo = auth.abonnement;
    final ref = auth.partenaireRef;

    return StreamBuilder<bool>(
      stream: PaiementService.paiementActif(),
      builder: (context, flagSnap) {
        final paiementActif = flagSnap.data ?? false;
        return PageScaffold(
          title: 'Mon abonnement',
          subtitle: 'Forfait, quota de baux et options',
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (ref == null)
                const AppCard(
                    child: EmptyState('Fiche partenaire introuvable.'))
              else
                StreamBuilder<List<Bail>>(
                  stream: BailRepository(ref).baux(),
                  builder: (context, snap) {
                    final actifs =
                        (snap.data ?? const []).where((b) => b.actif).length;
                    return _CurrentPlanCard(
                      abo: abo,
                      bauxActifs: actifs,
                      paiementActif: paiementActif,
                      onPayer: (f) => _lancerPaiement(f),
                    );
                  },
                ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text('Tous les forfaits',
                      style: GoogleFonts.mavenPro(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _PeriodToggle(
                    annuel: _annuel,
                    onChanged: (v) => setState(() => _annuel = v),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'On compte en baux actifs, pas en biens. Publier sur la '
                'marketplace reste gratuit. Au-delà du quota, les baux en cours '
                'continuent — seule la création d\'un nouveau bail est bloquée.',
                style: GoogleFonts.mavenPro(
                    fontSize: 12.5, color: AppTheme.inkSoft, height: 1.5),
              ),
              const SizedBox(height: 14),
              for (final p in PlanInfo.tous)
                _PlanCard(
                  plan: p,
                  courant: p.formule == abo.formule,
                  annuel: _annuel,
                  paiementActif: paiementActif,
                  onChoisir: () => _lancerPaiement(p.formule),
                ),
              const SizedBox(height: 10),
              Text(
                paiementActif
                    ? 'Paiement Wave, Orange Money ou carte. Aucun prélèvement '
                        'automatique : vous renouvelez chaque échéance.'
                    : 'Le règlement en ligne (Wave / Orange Money) arrive '
                        'bientôt. Pour l\'instant, le passage se fait via '
                        'l\'équipe Zappart.',
                style: GoogleFonts.mavenPro(
                    fontSize: 11.5, color: AppTheme.inkSoft),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _lancerPaiement(Formule f) async {
    if (f == Formule.reseau || f == Formule.decouverte) {
      _open(f == Formule.reseau
          ? '$_kWa?text=Bonjour%2C%20je%20veux%20un%20devis%20ZappArt%20Pro%20R%C3%A9seau.'
          : _waPassage(f));
      return;
    }
    final choix = await showDialog<_MethodeChoix>(
      context: context,
      builder: (_) => _MethodeDialog(
        formule: Abonnement(f).label,
        annuel: _annuel,
      ),
    );
    if (choix == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingDialog(),
    );
    try {
      final url = await PaiementService.initierAbonnement(
        formule: _formuleCode(f),
        periode: _annuel ? 'annuel' : 'mensuel',
        moyen: choix.moyen,
        numero: choix.numero,
      );
      if (mounted) Navigator.of(context).pop(); // ferme le loader
      await _open(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Paiement ouvert dans un nouvel onglet. Votre forfait '
              'se met à jour dès la confirmation.'),
        ));
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
  }
}

// ── Forfait courant ────────────────────────────────────────────────────────

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.abo,
    required this.bauxActifs,
    required this.paiementActif,
    required this.onPayer,
  });
  final Abonnement abo;
  final int bauxActifs;
  final bool paiementActif;
  final void Function(Formule) onPayer;

  @override
  Widget build(BuildContext context) {
    final quota = abo.quotaBaux;
    final ratio = quota <= 0 ? 0.0 : (bauxActifs / quota).clamp(0.0, 1.0);
    final proche = quota < 1000 && bauxActifs >= quota;
    final suivant = abo.formule != Formule.reseau
        ? Formule.values[abo.formule.index + 1]
        : null;

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
            const _Notice(
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
                  onPressed: () => paiementActif
                      ? onPayer(abo.formule)
                      : _open(_waPassage(abo.formule)),
                  child: const Text('Renouveler'),
                ),
              if (suivant != null)
                ElevatedButton(
                  onPressed: () => paiementActif
                      ? onPayer(suivant)
                      : _open(_waPassage(suivant)),
                  child: Text('Passer à ${Abonnement(suivant).label}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Carte d'un forfait ─────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.courant,
    required this.annuel,
    required this.paiementActif,
    required this.onChoisir,
  });
  final PlanInfo plan;
  final bool courant;
  final bool annuel;
  final bool paiementActif;
  final VoidCallback onChoisir;

  @override
  Widget build(BuildContext context) {
    final a = Abonnement(plan.formule);
    final prixMois = plan.prix < 0
        ? null
        : annuel
            ? (plan.prix * 10 / 12).round()
            : plan.prix;

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    plan.prix < 0
                        ? 'Sur devis'
                        : plan.prix == 0
                            ? 'Gratuit'
                            : '${_fmt.format(prixMois)} FCFA / mois',
                    style: GoogleFonts.mavenPro(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  if (annuel && (plan.prix) > 0)
                    Text('${_fmt.format(plan.prix * 10)} FCFA / an',
                        style: GoogleFonts.mavenPro(
                            fontSize: 10.5, color: AppTheme.inkSoft)),
                ],
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
                onPressed: onChoisir,
                child: Text(plan.formule == Formule.reseau
                    ? 'Demander un devis'
                    : paiementActif
                        ? 'Choisir ${a.label}'
                        : 'Choisir ${a.label} (via l\'équipe)'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bascule mensuel / annuel ───────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.annuel, required this.onChanged});
  final bool annuel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String t, bool on, VoidCallback tap) => InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: on ? AppTheme.ink : Colors.transparent),
            ),
            child: Text(t,
                style: GoogleFonts.mavenPro(
                    fontSize: 11.5,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? AppTheme.ink : AppTheme.inkSoft)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Mensuel', !annuel, () => onChanged(false)),
        const SizedBox(width: 3),
        seg('Annuel −2 mois', annuel, () => onChanged(true)),
      ]),
    );
  }
}

// ── Dialogue moyen de paiement ─────────────────────────────────────────────

class _MethodeChoix {
  const _MethodeChoix(this.moyen, this.numero);
  final String moyen;
  final String numero;
}

class _MethodeDialog extends StatefulWidget {
  const _MethodeDialog({required this.formule, required this.annuel});
  final String formule;
  final bool annuel;

  @override
  State<_MethodeDialog> createState() => _MethodeDialogState();
}

class _MethodeDialogState extends State<_MethodeDialog> {
  String _moyen = 'wave';
  final _num = TextEditingController();

  @override
  void dispose() {
    _num.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final besoinNum = _moyen == 'wave' || _moyen == 'orange_money';
    return AlertDialog(
      title: Text('Payer le forfait ${widget.formule}',
          style: GoogleFonts.mavenPro(
              fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Facturation ${widget.annuel ? "annuelle (2 mois offerts)" : "mensuelle"}.',
            style: GoogleFonts.mavenPro(
                fontSize: 12, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 14),
          for (final m in const [
            ('wave', 'Wave'),
            ('orange_money', 'Orange Money'),
            ('carte', 'Carte bancaire'),
          ])
            InkWell(
              onTap: () => setState(() => _moyen = m.$1),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(
                      _moyen == m.$1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: _moyen == m.$1 ? AppTheme.ink : AppTheme.inkSoft,
                    ),
                    const SizedBox(width: 10),
                    Text(m.$2,
                        style: GoogleFonts.mavenPro(fontSize: 13.5)),
                  ],
                ),
              ),
            ),
          if (besoinNum) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _num,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Numéro Wave / Orange Money',
                  hintText: '77 000 00 00'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _moyen == 'wave'
                ? 'Vous confirmerez sur votre téléphone (QR / lien Wave).'
                : _moyen == 'orange_money'
                    ? 'Vous recevrez une demande de confirmation Orange Money.'
                    : 'Paiement par carte sur la page sécurisée.',
            style: GoogleFonts.mavenPro(fontSize: 11, color: AppTheme.inkSoft),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () {
            if (besoinNum &&
                _num.text.replaceAll(RegExp(r'\D'), '').length < 9) {
              return;
            }
            Navigator.pop(
                context, _MethodeChoix(_moyen, _num.text.trim()));
          },
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();
  @override
  Widget build(BuildContext context) => const AlertDialog(
        content: SizedBox(
          height: 60,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 14),
                Text('Ouverture du paiement…'),
              ],
            ),
          ),
        ),
      );
}

// ── Briques ────────────────────────────────────────────────────────────────

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
