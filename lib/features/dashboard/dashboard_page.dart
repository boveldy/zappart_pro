import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/dashboard_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Écran d'accueil de Zappart Pro — noir / blanc / gris, Maven Pro.
/// En-tête + rangée de 4 indicateurs, prochaines arrivées + répartition,
/// dernières réservations. Données réelles, scopées à la fiche partenaire.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null) {
      return const _Padded(child: _Empty(text: 'Fiche partenaire en cours de liaison…'));
    }
    final repo = DashboardRepository(
      ref,
      estHote: auth.estHote,
      estPrestataire: auth.estPrestataire,
    );

    return StreamBuilder<List<HouseLite>>(
      stream: repo.houses(),
      builder: (context, hSnap) {
        return StreamBuilder<List<ResaLite>>(
          stream: repo.reservations(),
          builder: (context, rSnap) {
            if (hSnap.hasError || rSnap.hasError) {
              return const _Padded(
                child: _Empty(
                  text: 'Impossible de charger le tableau de bord. '
                      'Vérifiez votre connexion.',
                ),
              );
            }
            if (!hSnap.hasData || !rSnap.hasData) {
              return const _Padded(child: _Skeleton());
            }
            return _Body(
              houses: hSnap.data!,
              resas: rSnap.data!,
              estHote: auth.estHote,
            );
          },
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.houses,
    required this.resas,
    required this.estHote,
  });
  final List<HouseLite> houses;
  final List<ResaLite> resas;
  final bool estHote;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final vivantes =
        houses.where((h) => h.statutValidation != 'supprimee').toList();
    final enLigne = vivantes.where((h) => h.enLigne).length;
    final enValidation = vivantes.where((h) => h.enValidation).length;
    final rejetees = vivantes.where((h) => h.rejetee).length;

    final demandes = resas.where((r) => r.demandeAccord).length;
    final resa30j = resas
        .where((r) =>
            r.dateCreated != null &&
            now.difference(r.dateCreated!).inDays <= 30 &&
            now.difference(r.dateCreated!).inDays >= 0)
        .length;

    final arrivees = resas.where((r) => r.aVenir).toList()
      ..sort((a, b) => (a.dateDebut ?? a.dateSorti ?? now)
          .compareTo(b.dateDebut ?? b.dateSorti ?? now));

    final recentes = [...resas]..sort((a, b) =>
        (b.dateCreated ?? DateTime(2000)).compareTo(a.dateCreated ?? DateTime(2000)));

    final repartition = <String, int>{
      'Visite': resas.where((r) => r.typeCourt == 'Visite').length,
      'Journalier': resas.where((r) => r.typeCourt == 'Journalier').length,
      'Mensuel': resas.where((r) => r.typeCourt == 'Mensuel').length,
      'Service': resas.where((r) => r.typeCourt == 'Service').length,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(demandes: demandes),
          const SizedBox(height: 20),
          if (!estHote) ...[
            const _InfoCard(
              text: 'Votre compte est prestataire de services. Le suivi de vos '
                  'missions arrivera bientôt dans un écran dédié.',
            ),
            const SizedBox(height: 16),
          ],
          if (demandes > 0 || rejetees > 0) ...[
            _AlertBanner(
              text: demandes > 0
                  ? (demandes > 1
                      ? '$demandes demandes à valider'
                      : 'Une demande à valider')
                  : (rejetees > 1
                      ? '$rejetees annonces à corriger'
                      : 'Une annonce à corriger'),
              hint: demandes > 0
                  ? 'Confirmez votre disponibilité'
                  : 'Elles ont été refusées à la validation',
              onTap: () =>
                  context.go(demandes > 0 ? '/reservations' : '/parc'),
            ),
            const SizedBox(height: 16),
          ],
          _StatRow(
            items: [
              _Stat('Annonces en ligne', '$enLigne',
                  hint: enValidation > 0 ? '$enValidation en validation' : 'à jour'),
              _Stat('Demandes à traiter', '$demandes',
                  hint: demandes > 0 ? 'réponse attendue' : 'rien en attente',
                  emphasize: demandes > 0),
              _Stat('Réservations · 30 j', '$resa30j', hint: 'toutes catégories'),
              _Stat('Total annonces', '${vivantes.length}',
                  hint: rejetees > 0 ? '$rejetees rejetée(s)' : 'parc actif'),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final stack = c.maxWidth < 900;
              final left = _ArriveesCard(arrivees: arrivees);
              final right = _RepartitionCard(data: repartition, total: resas.length);
              return stack
                  ? Column(children: [left, const SizedBox(height: 16), right])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: left),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: right),
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          _RecentesCard(resas: recentes.take(6).toList()),
        ],
      ),
    );
  }
}

// ── En-tête ──────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.demandes});
  final int demandes;

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
              Text('Tableau de bord', style: AppTheme.h1),
              const SizedBox(height: 3),
              Text(
                '$today${demandes > 0 ? ' · $demandes demande${demandes > 1 ? 's' : ''} en attente' : ''}',
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

// ── Bandeau d'alerte ─────────────────────────────────────────────────────
class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.text, required this.hint, this.onTap});
  final String text;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.ink,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: Colors.white, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text,
                        style: GoogleFonts.mavenPro(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    Text(hint,
                        style: GoogleFonts.mavenPro(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rangée d'indicateurs ─────────────────────────────────────────────────
class _Stat {
  _Stat(this.label, this.value, {required this.hint, this.emphasize = false});
  final String label;
  final String value;
  final String hint;
  final bool emphasize;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.items});
  final List<_Stat> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 720 ? 2 : 4;
      final gap = 14.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final s in items) SizedBox(width: w, child: _StatCard(s)),
        ],
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.s);
  final _Stat s;

  @override
  Widget build(BuildContext context) {
    final dark = s.emphasize;
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
          Text(s.label.toUpperCase(),
              style: GoogleFonts.mavenPro(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: dark ? Colors.white70 : AppTheme.inkSoft,
              )),
          const SizedBox(height: 8),
          Text(s.value,
              style: GoogleFonts.mavenPro(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: dark ? Colors.white : AppTheme.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(height: 3),
          Text(s.hint,
              style: GoogleFonts.mavenPro(
                fontSize: 11.5,
                color: dark ? Colors.white60 : AppTheme.inkSoft,
              )),
        ],
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
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: GoogleFonts.mavenPro(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Prochaines arrivées ──────────────────────────────────────────────────
class _ArriveesCard extends StatelessWidget {
  const _ArriveesCard({required this.arrivees});
  final List<ResaLite> arrivees;

  @override
  Widget build(BuildContext context) {
    final items = arrivees.take(6).toList();
    return _Card(
      title: 'Prochaines arrivées',
      trailing: Text('${arrivees.length}',
          style: GoogleFonts.mavenPro(fontSize: 12, color: AppTheme.inkSoft)),
      child: items.isEmpty
          ? const _Empty(text: 'Aucune arrivée programmée.')
          : Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _ArriveeRow(items[i]),
                ],
              ],
            ),
    );
  }
}

class _ArriveeRow extends StatelessWidget {
  const _ArriveeRow(this.r);
  final ResaLite r;

  @override
  Widget build(BuildContext context) {
    final d = r.dateDebut ?? r.dateSorti;
    final jour = d == null
        ? '—'
        : DateFormat('EEE\ndd/MM', 'fr').format(d).toUpperCase();
    final heure = d == null ? '' : DateFormat('HH\'h\'mm', 'fr').format(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(jour,
                textAlign: TextAlign.center,
                style: GoogleFonts.mavenPro(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: AppTheme.inkSoft)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.clientNom.isEmpty ? 'Client' : r.clientNom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.mavenPro(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text('${r.typeCourt} · ${r.status}',
                    style: GoogleFonts.mavenPro(
                        fontSize: 11.5, color: AppTheme.inkSoft)),
              ],
            ),
          ),
          if (heure.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(heure,
                  style: GoogleFonts.mavenPro(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink)),
            ),
        ],
      ),
    );
  }
}

// ── Répartition par type ─────────────────────────────────────────────────
class _RepartitionCard extends StatelessWidget {
  const _RepartitionCard({required this.data, required this.total});
  final Map<String, int> data;
  final int total;

  @override
  Widget build(BuildContext context) {
    final max = data.values.fold<int>(1, (a, b) => b > a ? b : a);
    const shades = [
      Color(0xFF141414),
      Color(0xFF5C5C5C),
      Color(0xFF9A9A9A),
      Color(0xFFD0D0D0),
    ];
    final entries = data.entries.toList();
    return _Card(
      title: 'Répartition des réservations',
      trailing: Text('$total au total',
          style: GoogleFonts.mavenPro(fontSize: 12, color: AppTheme.inkSoft)),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _Bar(
              label: entries[i].key,
              value: entries[i].value,
              fraction: entries[i].value / max,
              color: shades[i % shades.length],
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });
  final String label;
  final int value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: GoogleFonts.mavenPro(
                      fontSize: 12.5, fontWeight: FontWeight.w500)),
            ),
            Text('$value',
                style: GoogleFonts.mavenPro(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.02, 1),
            minHeight: 7,
            backgroundColor: AppTheme.panel,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ── Dernières réservations ───────────────────────────────────────────────
class _RecentesCard extends StatelessWidget {
  const _RecentesCard({required this.resas});
  final List<ResaLite> resas;

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
            style: GoogleFonts.mavenPro(
                fontSize: 12, color: AppTheme.inkSoft)),
      ),
      child: resas.isEmpty
          ? const _Empty(text: 'Aucune réservation pour le moment.')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      _th('Client', flex: 3),
                      _th('Type', flex: 2),
                      _th('Statut', flex: 2),
                      _th('Montant', flex: 2, right: true),
                    ],
                  ),
                ),
                for (final r in resas) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(
                      children: [
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
                                : NumberFormat.decimalPattern('fr').format(r.prix),
                            textAlign: TextAlign.right,
                            style: GoogleFonts.mavenPro(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                        ),
                      ],
                    ),
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
      default: // En attente
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

// ── Utilitaires ──────────────────────────────────────────────────────────
class _Padded extends StatelessWidget {
  const _Padded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
        child: child,
      );
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
            style: GoogleFonts.mavenPro(
                fontSize: 13.5, color: AppTheme.inkSoft)),
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
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text,
            style: GoogleFonts.mavenPro(
                fontSize: 13, color: AppTheme.inkSoft)),
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
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [box(46), const SizedBox(height: 10), box(96), box(240), box(260)],
    );
  }
}
