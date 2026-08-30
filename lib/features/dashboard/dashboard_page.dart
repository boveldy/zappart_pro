import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/dashboard_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Écran d'accueil de Zappart Pro — logiciel de gestion immobilière.
/// Noir / blanc / gris, Maven Pro. Vise **mensuel + journalier à parité**.
///
/// Blocs : à traiter · argent (solde à retirer, en attente, revenu) ·
/// occupation & parc · arrivées/départs · dernières réservations.
/// Le volet « services / prestataire » reste sur mobile — un compte
/// prestataire pur voit un simple encart.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null) {
      return const _Padded(
          child: _Empty(text: 'Fiche partenaire en cours de liaison…'));
    }
    final repo = DashboardRepository(ref, estHote: auth.estHote);
    return _DashboardLoader(repo: repo, estHote: auth.estHote);
  }
}

// ── Chargement combiné des flux ──────────────────────────────────────────
class _DashboardLoader extends StatefulWidget {
  const _DashboardLoader({required this.repo, required this.estHote});
  final DashboardRepository repo;
  final bool estHote;

  @override
  State<_DashboardLoader> createState() => _DashboardLoaderState();
}

class _DashboardLoaderState extends State<_DashboardLoader> {
  final _subs = <StreamSubscription>[];
  PartenaireLite? _part;
  List<WalletLine>? _wallet;
  List<RetraitLine>? _retraits;
  List<HouseLite>? _houses;
  List<ResaLite>? _resas;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    void bind<T>(Stream<T> s, void Function(T) set) {
      _subs.add(s.listen((v) {
        if (mounted) setState(() => set(v));
      }, onError: (_) {
        if (mounted) setState(() => _error = true);
      }));
    }

    bind(widget.repo.partenaire(), (v) => _part = v);
    bind(widget.repo.walletLedger(), (v) => _wallet = v);
    bind(widget.repo.retraits(), (v) => _retraits = v);
    bind(widget.repo.houses(), (v) => _houses = v);
    bind(widget.repo.reservations(), (v) => _resas = v);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const _Padded(
        child: _Empty(
          text: 'Impossible de charger le tableau de bord. '
              'Vérifiez votre connexion.',
        ),
      );
    }
    final ready = _part != null &&
        _wallet != null &&
        _retraits != null &&
        _houses != null &&
        _resas != null;
    if (!ready) return const _Padded(child: _Skeleton());

    if (!widget.estHote) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(nom: _part!.nom, tacheCount: 0),
            const SizedBox(height: 20),
            const _InfoCard(
              text: 'Votre compte est prestataire de services. La gestion de '
                  'vos missions se fait dans l\'application mobile Zappart.',
            ),
          ],
        ),
      );
    }

    return _Body(
      part: _part!,
      wallet: _wallet!,
      retraits: _retraits!,
      houses: _houses!,
      resas: _resas!,
    );
  }
}

// ── Corps ────────────────────────────────────────────────────────────────
class _Body extends StatelessWidget {
  const _Body({
    required this.part,
    required this.wallet,
    required this.retraits,
    required this.houses,
    required this.resas,
  });

  final PartenaireLite part;
  final List<WalletLine> wallet;
  final List<RetraitLine> retraits;
  final List<HouseLite> houses;
  final List<ResaLite> resas;

  static final _fmt = NumberFormat.decimalPattern('fr');
  static String _fcfa(num v) => '${_fmt.format(v.round())} FCFA';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // ---- parc ----
    final vivantes =
        houses.where((h) => h.statutValidation != 'supprimee').toList();
    final enLigne = vivantes.where((h) => h.enLigne).toList();
    final enValidation = vivantes.where((h) => h.enValidation).length;
    final rejetees = vivantes.where((h) => h.rejetee).length;
    final journaliers =
        enLigne.where((h) => h.locationType == 'Journalier').toList();
    final mensuels =
        enLigne.where((h) => h.locationType == 'Mensuel').toList();

    // ---- tâches ----
    final demandes = resas.where((r) => r.demandeAccord).length;
    final visitesSemaine = resas
        .where((r) =>
            r.typeCourt == 'Visite' &&
            r.dateDebut != null &&
            r.dateDebut!.isAfter(now.subtract(const Duration(hours: 12))) &&
            r.dateDebut!.isBefore(now.add(const Duration(days: 7))))
        .length;
    final taches = <_Tache>[
      if (demandes > 0)
        _Tache('$demandes demande${demandes > 1 ? 's' : ''} de réservation',
            'à accepter ou refuser', () => context.go('/reservations')),
      if (visitesSemaine > 0)
        _Tache('$visitesSemaine visite${visitesSemaine > 1 ? 's' : ''} cette semaine',
            'clients qui viennent voir un bien',
            () => context.go('/calendrier')),
      if (rejetees > 0)
        _Tache('$rejetees annonce${rejetees > 1 ? 's' : ''} rejetée${rejetees > 1 ? 's' : ''}',
            'à corriger pour repasser en ligne', () => context.go('/parc')),
    ];

    // ---- argent ----
    final walletActif = wallet.where((w) => w.actif).toList();
    final enAttente = walletActif
        .where((w) => w.enAttente)
        .fold<double>(0, (s, w) => s + w.montant);
    final revenu30j = walletActif
        .where((w) =>
            w.dateEncaissement != null &&
            now.difference(w.dateEncaissement!).inDays.abs() <= 30)
        .fold<double>(0, (s, w) => s + w.montant);
    final retraitEnCours =
        retraits.where((r) => r.status == 'a_payer').fold<int>(0, (s, r) => s + r.montant);

    // ---- occupation journalier (30 j) ----
    final nuits = resas
        .where((r) =>
            r.typeCourt == 'Journalier' &&
            r.status != 'Annulée' &&
            r.dateDebut != null &&
            r.dateSorti != null &&
            r.dateDebut!.isAfter(now.subtract(const Duration(days: 30))))
        .fold<int>(
            0, (s, r) => s + r.dateSorti!.difference(r.dateDebut!).inDays.clamp(0, 30));
    final capacite = journaliers.length * 30;
    final tauxJournalier = capacite > 0 ? (nuits / capacite).clamp(0.0, 1.0) : null;

    // ---- mensuel loués ----
    final mensuelIds = mensuels.map((h) => h.id).toSet();
    final loues = resas
        .where((r) =>
            r.typeCourt == 'Mensuel' &&
            (r.status == 'Réservée' || r.status == 'Soldée') &&
            r.houseId != null &&
            mensuelIds.contains(r.houseId))
        .map((r) => r.houseId)
        .toSet()
        .length;

    // ---- arrivées / départs 7 j ----
    final mouvements = <_Mouvement>[];
    for (final r in resas) {
      if (r.typeCourt != 'Journalier' || r.status == 'Annulée') continue;
      final din = r.dateDebut, dout = r.dateSorti;
      if (din != null &&
          din.isAfter(now.subtract(const Duration(hours: 12))) &&
          din.isBefore(now.add(const Duration(days: 7)))) {
        mouvements.add(_Mouvement(din, true, r.clientNom));
      }
      if (dout != null &&
          dout.isAfter(now.subtract(const Duration(hours: 12))) &&
          dout.isBefore(now.add(const Duration(days: 7)))) {
        mouvements.add(_Mouvement(dout, false, r.clientNom));
      }
    }
    mouvements.sort((a, b) => a.date.compareTo(b.date));

    // ---- dernières réservations (mensuel + journalier, pas les visites) ----
    final ventes = resas
        .where((r) => r.typeCourt == 'Journalier' || r.typeCourt == 'Mensuel')
        .toList()
      ..sort((a, b) => (b.dateCreated ?? DateTime(2000))
          .compareTo(a.dateCreated ?? DateTime(2000)));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(nom: part.nom, tacheCount: taches.length),
          const SizedBox(height: 20),

          // ── À traiter ───────────────────────────────────────────────
          _Card(
            title: 'À traiter',
            child: taches.isEmpty
                ? Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 18, color: AppTheme.inkSoft),
                      const SizedBox(width: 8),
                      Text('Tout est à jour.',
                          style: GoogleFonts.mavenPro(
                              fontSize: 13.5, color: AppTheme.inkSoft)),
                    ],
                  )
                : Column(
                    children: [
                      for (var i = 0; i < taches.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _TacheRow(taches[i]),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // ── Argent ──────────────────────────────────────────────────
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth < 720 ? 2 : 4;
            final gap = 14.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              SizedBox(
                width: w,
                child: _MoneyCard(
                  label: 'Solde disponible',
                  value: _fcfa(part.soldeDisponible),
                  hint: retraitEnCours > 0
                      ? 'retrait de ${_fcfa(retraitEnCours)} en cours'
                      : 'prêt à retirer',
                  dark: true,
                  action: part.soldeDisponible > 0
                      ? ('Retirer', () => context.go('/revenus'))
                      : null,
                ),
              ),
              SizedBox(
                width: w,
                child: _MoneyCard(
                  label: 'En attente',
                  value: _fcfa(enAttente),
                  hint: 'se débloque après les séjours',
                ),
              ),
              SizedBox(
                width: w,
                child: _MoneyCard(
                  label: 'Revenu · 30 j',
                  value: _fcfa(revenu30j),
                  hint: 'encaissé via Zappart',
                ),
              ),
              SizedBox(
                width: w,
                child: _MoneyCard(
                  label: 'Annonces en ligne',
                  value: '${enLigne.length}',
                  hint: enValidation > 0
                      ? '$enValidation en validation'
                      : 'sur le marketplace',
                ),
              ),
            ]);
          }),
          const SizedBox(height: 16),

          // ── Occupation & arrivées ───────────────────────────────────
          LayoutBuilder(builder: (context, c) {
            final stack = c.maxWidth < 900;
            final occ = _OccupationCard(
              tauxJournalier: tauxJournalier,
              nbJournalier: journaliers.length,
              mensuelEnLigne: mensuels.length,
              mensuelLoues: loues,
            );
            final mov = _MouvementsCard(mouvements: mouvements);
            return stack
                ? Column(children: [occ, const SizedBox(height: 16), mov])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: occ),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: mov),
                    ],
                  );
          }),
          const SizedBox(height: 16),

          // ── Dernières réservations ──────────────────────────────────
          _VentesCard(ventes: ventes.take(6).toList()),
        ],
      ),
    );
  }
}

// ── En-tête ──────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.nom, required this.tacheCount});
  final String nom;
  final int tacheCount;

  @override
  Widget build(BuildContext context) {
    final today = toBeginningOfSentenceCase(
        DateFormat('EEEE d MMMM', 'fr').format(DateTime.now()));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nom.isEmpty ? 'Tableau de bord' : 'Bonjour, $nom',
                  style: AppTheme.h1),
              const SizedBox(height: 3),
              Text(
                '$today${tacheCount > 0 ? ' · $tacheCount élément${tacheCount > 1 ? 's' : ''} à traiter' : ''}',
                style: AppTheme.label,
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: () => context.go('/parc'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.ink,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                GoogleFonts.mavenPro(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: const Text('＋ Ajouter une annonce'),
        ),
      ],
    );
  }
}

// ── Tâches ───────────────────────────────────────────────────────────────
class _Tache {
  _Tache(this.title, this.hint, this.onTap);
  final String title;
  final String hint;
  final VoidCallback onTap;
}

class _TacheRow extends StatelessWidget {
  const _TacheRow(this.t);
  final _Tache t;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: t.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: AppTheme.ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      style: GoogleFonts.mavenPro(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text(t.hint,
                      style: GoogleFonts.mavenPro(
                          fontSize: 11.5, color: AppTheme.inkSoft)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ── Carte argent ─────────────────────────────────────────────────────────
class _MoneyCard extends StatelessWidget {
  const _MoneyCard({
    required this.label,
    required this.value,
    required this.hint,
    this.dark = false,
    this.action,
  });
  final String label;
  final String value;
  final String hint;
  final bool dark;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppTheme.ink;
    final sub = dark ? Colors.white70 : AppTheme.inkSoft;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppTheme.ink : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? AppTheme.ink : AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: GoogleFonts.mavenPro(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: sub)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: GoogleFonts.mavenPro(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(height: 3),
          Text(hint,
              style: GoogleFonts.mavenPro(fontSize: 11.5, color: sub)),
          if (action != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: FilledButton(
                onPressed: action!.$2,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                  textStyle: GoogleFonts.mavenPro(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                child: Text(action!.$1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Occupation & parc ────────────────────────────────────────────────────
class _OccupationCard extends StatelessWidget {
  const _OccupationCard({
    required this.tauxJournalier,
    required this.nbJournalier,
    required this.mensuelEnLigne,
    required this.mensuelLoues,
  });
  final double? tauxJournalier;
  final int nbJournalier;
  final int mensuelEnLigne;
  final int mensuelLoues;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Occupation du parc',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tauxJournalier != null) ...[
            Text('JOURNALIER · 30 JOURS',
                style: GoogleFonts.mavenPro(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppTheme.inkSoft)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${(tauxJournalier! * 100).round()}',
                    style: GoogleFonts.mavenPro(
                        fontSize: 30, fontWeight: FontWeight.w800)),
                Text(' %  taux d\'occupation',
                    style: GoogleFonts.mavenPro(
                        fontSize: 12.5, color: AppTheme.inkSoft)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: tauxJournalier!.clamp(0.02, 1),
                minHeight: 7,
                backgroundColor: AppTheme.panel,
                valueColor: const AlwaysStoppedAnimation(AppTheme.ink),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text('$nbJournalier bien${nbJournalier > 1 ? 's' : ''} journalier',
                  style: GoogleFonts.mavenPro(
                      fontSize: 11, color: AppTheme.inkSoft)),
            ),
            const SizedBox(height: 16),
          ],
          Text('MENSUEL',
              style: GoogleFonts.mavenPro(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppTheme.inkSoft)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$mensuelLoues',
                  style: GoogleFonts.mavenPro(
                      fontSize: 30, fontWeight: FontWeight.w800)),
              Text(' / $mensuelEnLigne loués',
                  style: GoogleFonts.mavenPro(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ],
          ),
          if (mensuelEnLigne == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('aucun bien mensuel en ligne',
                  style: GoogleFonts.mavenPro(
                      fontSize: 11, color: AppTheme.inkSoft)),
            ),
        ],
      ),
    );
  }
}

// ── Arrivées / départs ───────────────────────────────────────────────────
class _Mouvement {
  _Mouvement(this.date, this.arrivee, this.client);
  final DateTime date;
  final bool arrivee;
  final String client;
}

class _MouvementsCard extends StatelessWidget {
  const _MouvementsCard({required this.mouvements});
  final List<_Mouvement> mouvements;

  @override
  Widget build(BuildContext context) {
    final items = mouvements.take(7).toList();
    return _Card(
      title: 'Arrivées & départs · 7 jours',
      trailing: Text('${mouvements.length}',
          style: GoogleFonts.mavenPro(fontSize: 12, color: AppTheme.inkSoft)),
      child: items.isEmpty
          ? const _Empty(text: 'Rien de prévu cette semaine.')
          : Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _MouvementRow(items[i]),
                ],
              ],
            ),
    );
  }
}

class _MouvementRow extends StatelessWidget {
  const _MouvementRow(this.m);
  final _Mouvement m;

  @override
  Widget build(BuildContext context) {
    final jour = DateFormat('EEE dd/MM', 'fr').format(m.date).toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: m.arrivee ? AppTheme.ink : AppTheme.panel,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(m.arrivee ? 'Arrivée' : 'Départ',
                style: GoogleFonts.mavenPro(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: m.arrivee ? Colors.white : AppTheme.ink)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(m.client.isEmpty ? 'Client' : m.client,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.mavenPro(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text(jour,
              style: GoogleFonts.mavenPro(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkSoft)),
        ],
      ),
    );
  }
}

// ── Dernières réservations ───────────────────────────────────────────────
class _VentesCard extends StatelessWidget {
  const _VentesCard({required this.ventes});
  final List<ResaLite> ventes;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Dernières réservations',
      trailing: TextButton(
        onPressed: () => context.go('/reservations'),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text('voir tout',
            style:
                GoogleFonts.mavenPro(fontSize: 12, color: AppTheme.inkSoft)),
      ),
      child: ventes.isEmpty
          ? const _Empty(text: 'Aucune réservation pour le moment.')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    _th('Client', flex: 3),
                    _th('Type', flex: 2),
                    _th('Statut', flex: 2),
                    _th('Montant', flex: 2, right: true),
                  ]),
                ),
                for (final r in ventes) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          r.clientNom.isEmpty ? 'Client' : r.clientNom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.mavenPro(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(r.typeCourt,
                            style: GoogleFonts.mavenPro(fontSize: 12.5)),
                      ),
                      Expanded(flex: 2, child: _StatusPill(r.status)),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.prix == null || r.prix == 0
                              ? '—'
                              : NumberFormat.decimalPattern('fr')
                                  .format(r.prix),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.mavenPro(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _th(String t, {int flex = 1, bool right = false}) => Expanded(
        flex: flex,
        child: Text(t.toUpperCase(),
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: GoogleFonts.mavenPro(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppTheme.inkSoft)),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    switch (status) {
      case 'Soldée':
      case 'Payée':
      case 'Terminée':
        bg = const Color(0xFFE9EFE9);
        fg = const Color(0xFF2F6B45);
        break;
      case 'Réservée':
        bg = const Color(0xFFF2EDE1);
        fg = const Color(0xFF7A5C1F);
        break;
      case 'Annulée':
        bg = const Color(0xFFF3E8E6);
        fg = const Color(0xFF8A4033);
        break;
      default:
        bg = const Color(0xFFECECEC);
        fg = const Color(0xFF5A5A5A);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(status.isEmpty ? 'En attente' : status,
            style: GoogleFonts.mavenPro(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}

// ── Carte générique ──────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  const _Card({required this.title, this.trailing, required this.child});
  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: GoogleFonts.mavenPro(
                      fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Utilitaires ──────────────────────────────────────────────────────────
class _Padded extends StatelessWidget {
  const _Padded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(28, 22, 28, 40), child: child);
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(text,
            textAlign: TextAlign.center,
            style:
                GoogleFonts.mavenPro(fontSize: 13.5, color: AppTheme.inkSoft)),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.panel, borderRadius: BorderRadius.circular(14)),
        child: Text(text,
            style:
                GoogleFonts.mavenPro(fontSize: 13, color: AppTheme.inkSoft)),
      );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    Widget box(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: AppTheme.panel, borderRadius: BorderRadius.circular(14)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [box(46), const SizedBox(height: 10), box(90), box(110), box(220), box(240)],
    );
  }
}
