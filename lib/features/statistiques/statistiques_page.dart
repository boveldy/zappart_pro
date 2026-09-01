import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/house.dart';
import '../../data/stats_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../abonnement/abonnement_page.dart';

/// Statistiques d'audience du parc : classement des biens par vues, totaux,
/// tendance. Lit `annonce_stats` (1 requête) + les `Reservation` du partenaire.
class StatistiquesPage extends StatefulWidget {
  const StatistiquesPage({super.key});

  @override
  State<StatistiquesPage> createState() => _StatistiquesPageState();
}

class _StatistiquesPageState extends State<StatistiquesPage> {
  int _jours = 30;
  static const _periodes = [7, 30, 90];
  static final _fmt = NumberFormat.decimalPattern('fr');

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null || !auth.estHote) {
      return const PageScaffold(
        title: 'Statistiques',
        child: EmptyState('Votre compte est prestataire — pas de parc à suivre.'),
      );
    }
    // Vues d'annonces & statistiques : réservées à l'offre Agence et plus —
    // évite de consommer des lectures Firestore pour les petits forfaits.
    if (!auth.abonnement.statsIncluses) {
      return const PageScaffold(
        title: 'Statistiques',
        child: Padding(
          padding: EdgeInsets.all(20),
          child: AboUpsell(
            titre: 'Statistiques d\'audience',
            detail:
                'Vues par annonce, classement du parc, tendance et taux de '
                'conversion des visites.',
          ),
        ),
      );
    }
    final houseRepo = HouseRepository(ref);
    final statsRepo = StatsRepository(ref);

    return StreamBuilder<List<House>>(
      stream: houseRepo.mine(),
      builder: (context, hSnap) {
        return StreamBuilder<Map<String, AnnonceStats>>(
          stream: statsRepo.allStats(),
          builder: (context, sSnap) {
            return StreamBuilder<List<ResaStat>>(
              stream: statsRepo.allReservations(),
              builder: (context, rSnap) {
                if (hSnap.hasError || sSnap.hasError) {
                  return const PageScaffold(
                    title: 'Statistiques',
                    child: EmptyState('Impossible de charger les statistiques.'),
                  );
                }
                final biens = hSnap.data;
                final stats = sSnap.data ?? const <String, AnnonceStats>{};
                final resas = rSnap.data ?? const <ResaStat>[];

                if (biens == null) {
                  return const PageScaffold(
                    title: 'Statistiques',
                    child: AppCard(child: SkeletonBox(height: 320)),
                  );
                }

                final resaParBien = <String, int>{};
                for (final r in resas.where((r) => r.compteConversion)) {
                  resaParBien[r.houseId] = (resaParBien[r.houseId] ?? 0) + 1;
                }

                final lignes = [
                  for (final b in biens)
                    (
                      bien: b,
                      st: stats[b.id] ?? AnnonceStats(0, const {}),
                      resa: resaParBien[b.id] ?? 0,
                    )
                ]..sort((a, b) =>
                    b.st.vuesDepuis(_jours).compareTo(a.st.vuesDepuis(_jours)));

                final vuesPeriode = lignes.fold<int>(
                    0, (a, l) => a + l.st.vuesDepuis(_jours));
                final vuesTotal =
                    lignes.fold<int>(0, (a, l) => a + l.st.vuesTotal);
                final enLigne = biens.where((b) => b.enLigne).length;
                final moyenne =
                    biens.isEmpty ? 0 : (vuesPeriode / biens.length).round();

                return PageScaffold(
                  title: 'Statistiques',
                  subtitle: 'Audience de vos annonces sur Zappart',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PeriodeBar(
                        jours: _jours,
                        options: _periodes,
                        onChanged: (j) => setState(() => _jours = j),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Kpi('Vues · $_jours j', _fmt.format(vuesPeriode)),
                          _Kpi('Vues cumulées', _fmt.format(vuesTotal)),
                          _Kpi('Biens en ligne', '$enLigne / ${biens.length}'),
                          _Kpi('Moyenne / bien · $_jours j',
                              _fmt.format(moyenne)),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (lignes.isEmpty)
                        const AppCard(
                          child: EmptyState(
                              'Aucun bien. Ajoutez une annonce depuis le Parc.'),
                        )
                      else
                        _Classement(lignes: lignes, jours: _jours),
                      if (vuesTotal == 0) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Le comptage des vues a démarré récemment — les chiffres '
                          'se rempliront au fil des consultations.',
                          style:
                              TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

typedef _Ligne = ({House bien, AnnonceStats st, int resa});

class _PeriodeBar extends StatelessWidget {
  const _PeriodeBar({
    required this.jours,
    required this.options,
    required this.onChanged,
  });
  final int jours;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.line),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              onTap: () => onChanged(o),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: jours == o ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: jours == o ? AppTheme.line : Colors.transparent),
                ),
                child: Text('$o jours',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            jours == o ? FontWeight.w700 : FontWeight.w500,
                        color: jours == o
                            ? AppTheme.ink
                            : AppTheme.inkSoft)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Classement extends StatelessWidget {
  const _Classement({required this.lignes, required this.jours});
  final List<_Ligne> lignes;
  final int jours;

  static final _fmt = NumberFormat.decimalPattern('fr');

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              const SizedBox(width: 34),
              _h('Bien', 4),
              _h('Vues · $jours j', 2, right: true),
              _h('Vues cumul.', 2, right: true),
              _h('Réservations', 2, right: true),
              _h('Conversion', 2, right: true),
              const SizedBox(width: 20),
            ]),
          ),
          for (var i = 0; i < lignes.length; i++)
            _Row(rang: i + 1, ligne: lignes[i], jours: jours),
        ],
      ),
    );
  }

  static Widget _h(String t, int flex, {bool right = false}) => Expanded(
        flex: flex,
        child: Text(t.toUpperCase(),
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppTheme.inkSoft)),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.rang, required this.ligne, required this.jours});
  final int rang;
  final _Ligne ligne;
  final int jours;

  @override
  Widget build(BuildContext context) {
    final h = ligne.bien;
    final vp = ligne.st.vuesDepuis(jours);
    final vt = ligne.st.vuesTotal;
    final conv = vt == 0 ? null : ligne.resa / vt * 100;

    return InkWell(
      onTap: () => context.go('/parc/${h.id}'),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text('$rang',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkSoft)),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 34,
                height: 34,
                child: h.images.isEmpty
                    ? Container(
                        color: AppTheme.panel,
                        child: const Icon(Icons.home_outlined,
                            size: 15, color: AppTheme.inkSoft))
                    : CachedNetworkImage(
                        imageUrl: h.images.first,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppTheme.panel),
                        errorWidget: (_, __, ___) =>
                            Container(color: AppTheme.panel),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text(
                    [
                      if (h.locationType.isNotEmpty) h.locationType,
                      if (!h.enLigne) 'hors ligne',
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 10.5, color: AppTheme.inkSoft),
                  ),
                ],
              ),
            ),
            _num(flex: 2, text: _Classement._fmt.format(vp), strong: true),
            _num(flex: 2, text: _Classement._fmt.format(vt)),
            _num(flex: 2, text: '${ligne.resa}'),
            _num(
                flex: 2,
                text: conv == null ? '—' : '${conv.toStringAsFixed(1)} %'),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.inkSoft),
          ],
        ),
      ),
    );
  }

  Widget _num({required int flex, required String text, bool strong = false}) =>
      Expanded(
        flex: flex,
        child: Text(text,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                color: strong ? AppTheme.ink : AppTheme.inkSoft)),
      );
}
