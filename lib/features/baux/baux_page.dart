import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/bail.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Liste des baux du partenaire + file des loyers en retard.
class BauxPage extends StatefulWidget {
  const BauxPage({super.key});

  @override
  State<BauxPage> createState() => _BauxPageState();
}

class _BauxPageState extends State<BauxPage> {
  String _statut = 'Tous';
  final _fmt = NumberFormat('#,###', 'fr_FR');
  static final _df = DateFormat('d MMM', 'fr');

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null || !auth.estHote) {
      return const PageScaffold(
        title: 'Baux',
        child: EmptyState('Votre compte est prestataire — pas de gestion locative.'),
      );
    }
    final repo = BailRepository(ref);

    return StreamBuilder<List<Echeance>>(
      stream: repo.echeances(),
      builder: (context, eSnap) {
        final ech = eSnap.data ?? const <Echeance>[];
        final parBail = <String, List<Echeance>>{};
        for (final e in ech) {
          (parBail[e.bailRefId] ??= []).add(e);
        }
        final retards = ech
            .where((e) => e.statutAffiche() == EStatut.retard)
            .toList();
        final retardTotal =
            retards.fold<double>(0, (a, e) => a + e.montantDu);

        return StreamBuilder<List<Bail>>(
          stream: repo.baux(),
          builder: (context, bSnap) {
            if (bSnap.hasError) {
              return const PageScaffold(
                title: 'Baux',
                child: EmptyState('Impossible de charger les baux.'),
              );
            }
            final all = bSnap.data;
            final actifs = (all ?? const <Bail>[]).where((b) => b.actif).length;

            return PageScaffold(
              title: 'Baux',
              subtitle: all == null
                  ? null
                  : '$actifs bail${actifs > 1 ? 's' : ''} actif${actifs > 1 ? 's' : ''}',
              actions: [
                FilledButton(
                  onPressed: () => context.go('/baux/nouveau'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.ink,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('＋ Nouveau bail'),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (retards.isNotEmpty) ...[
                    _RetardBanner(
                      nb: retards.length,
                      total: '${_fmt.format(retardTotal.round())} FCFA',
                    ),
                    const SizedBox(height: 16),
                  ],
                  _FilterBar(
                    statut: _statut,
                    onStatut: (v) => setState(() => _statut = v),
                  ),
                  const SizedBox(height: 14),
                  if (all == null)
                    const AppCard(child: SkeletonBox(height: 240))
                  else
                    _table(
                      rows: _filter(all, parBail),
                      parBail: parBail,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Bail> _filter(List<Bail> src, Map<String, List<Echeance>> parBail) {
    return src.where((b) {
      switch (_statut) {
        case 'Actifs':
          return b.actif;
        case 'Résiliés':
          return b.statut == 'resilie' || b.statut == 'termine';
        case 'En retard':
          return (parBail[b.id] ?? const [])
              .any((e) => e.statutAffiche() == EStatut.retard);
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => a.locataireNom.compareTo(b.locataireNom));
  }

  Widget _table({
    required List<Bail> rows,
    required Map<String, List<Echeance>> parBail,
  }) {
    if (rows.isEmpty) {
      return const AppCard(
        child: EmptyState('Aucun bail. Créez-en un pour suivre les loyers.',
            icon: Icons.description_outlined),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              _h('Locataire', 3),
              _h('Bien', 3),
              _h('Loyer / mois', 2, right: true),
              _h('Prochaine échéance', 3),
              _h('Statut', 2),
              const SizedBox(width: 20),
            ]),
          ),
          for (final b in rows)
            _row(
              b: b,
              prochaine: _prochaine(parBail[b.id] ?? const []),
            ),
        ],
      ),
    );
  }

  Echeance? _prochaine(List<Echeance> l) {
    final ouvertes = l
        .where((e) => e.statutBrut != 'paye' && e.statutBrut != 'annule')
        .toList()
      ..sort((a, b) => (a.dateEcheance ?? DateTime(2100))
          .compareTo(b.dateEcheance ?? DateTime(2100)));
    return ouvertes.isEmpty ? null : ouvertes.first;
  }

  static Widget _h(String t, int flex, {bool right = false}) => Expanded(
        flex: flex,
        child: Text(t.toUpperCase(),
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppTheme.inkSoft)),
      );

  Widget _row({required Bail b, required Echeance? prochaine}) {
    final st = prochaine?.statutAffiche();
    final badge = st == null
        ? (label: 'Soldé', tone: 'ok')
        : eStatutBadge(st);
    final retard = prochaine?.joursDeRetard();

    return InkWell(
      onTap: () => context.go('/baux/${b.id}'),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.locataireNom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(b.locataireTel,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.inkSoft)),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.bienTitre.isEmpty ? '—' : b.bienTitre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                  if (b.proprietaireNom.isNotEmpty)
                    Text('Pr. ${b.proprietaireNom}',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppTheme.inkSoft)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(_fmt.format(b.loyer.round()),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              flex: 3,
              child: Text(
                prochaine?.dateEcheance == null
                    ? '—'
                    : '${_df.format(prochaine!.dateEcheance!)}'
                        '${retard != null ? '  ·  +$retard j' : ''}',
                style: TextStyle(
                    fontSize: 12.5,
                    color: retard != null ? const Color(0xFF8A4033) : AppTheme.ink),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(badge.label, tone: badge.tone),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _RetardBanner extends StatelessWidget {
  const _RetardBanner({required this.nb, required this.total});
  final int nb;
  final String total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF2F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDD9D4)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: Color(0xFF8A4033), shape: BoxShape.circle),
            child: Text('$nb',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$nb loyer${nb > 1 ? 's' : ''} en retard',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                  text: ' · $total à recouvrer',
                  style: const TextStyle(color: AppTheme.inkSoft)),
            ], style: const TextStyle(fontSize: 13))),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.statut, required this.onStatut});
  final String statut;
  final ValueChanged<String> onStatut;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: statut,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(fontSize: 12.5, color: AppTheme.ink),
          items: const [
            DropdownMenuItem(value: 'Tous', child: Text('Statut : Tous')),
            DropdownMenuItem(value: 'Actifs', child: Text('Actifs')),
            DropdownMenuItem(value: 'En retard', child: Text('En retard')),
            DropdownMenuItem(value: 'Résiliés', child: Text('Résiliés / terminés')),
          ],
          onChanged: (v) => onStatut(v ?? 'Tous'),
        ),
      ),
    );
  }
}
