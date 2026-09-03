import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/bail.dart';
import '../../data/permissions.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'bail_releve.dart';

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
    final ref = auth.agenceRef;
    if (!auth.aGerance || ref == null) {
      return const PageScaffold(
        title: 'Baux',
        child: EmptyState('Votre compte est prestataire — pas de gestion locative.'),
      );
    }
    final canCreer = auth.can(ProPerm.bauxCreer);
    final repo = BailRepository(ref);

    return StreamBuilder<List<Depense>>(
      stream: repo.depenses(),
      builder: (context, dSnap) {
        final deps = dSnap.data ?? const <Depense>[];
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
            final aTerme = (all ?? const <Bail>[])
                .where((b) => b.arriveATerme(parBail[b.id] ?? const []))
                .length;

            return PageScaffold(
              title: 'Baux',
              subtitle: all == null
                  ? null
                  : '$actifs bail${actifs > 1 ? 's' : ''} actif${actifs > 1 ? 's' : ''}',
              actions: [
                if ((all ?? const <Bail>[])
                    .any((b) => b.proprietaireNom.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: OutlinedButton(
                      onPressed: () => _openRelevePart(
                          context, all ?? const [], ech, deps),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.ink,
                        side: const BorderSide(color: AppTheme.line),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Relevé par propriétaire'),
                    ),
                  ),
                if (canCreer)
                  FilledButton(
                  onPressed: () {
                    final abo = auth.abonnement;
                    final quotaOk =
                        abo.quotaBaux >= 1000 || actifs < abo.quotaBaux;
                    if (!quotaOk || abo.bloqueCreation) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(abo.bloqueCreation
                            ? 'Abonnement expiré — renouvelez pour créer un bail.'
                            : 'Quota de ${abo.quotaBaux} baux atteint (forfait '
                                '${abo.label}). Passez au forfait supérieur.'),
                        action: SnackBarAction(
                          label: 'Forfaits',
                          textColor: Colors.white,
                          onPressed: () => context.go('/abonnement'),
                        ),
                      ));
                      return;
                    }
                    context.go('/baux/nouveau');
                  },
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
                  _SignalementsBanner(repo: repo),
                  if (aTerme > 0) ...[
                    _TermeBanner(nb: aTerme),
                    const SizedBox(height: 16),
                  ],
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
              aTerme: b.arriveATerme(parBail[b.id] ?? const []),
            ),
        ],
      ),
    );
  }

  Future<void> _openRelevePart(
    BuildContext context,
    List<Bail> baux,
    List<Echeance> echeances,
    List<Depense> depenses,
  ) async {
    final agence = context.read<AuthService>().displayName;
    await showDialog<void>(
      context: context,
      builder: (_) => _RelevePartDialog(
        baux: baux,
        echeances: echeances,
        depenses: depenses,
        agence: agence,
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

  Widget _row(
      {required Bail b, required Echeance? prochaine, bool aTerme = false}) {
    final st = prochaine?.statutAffiche();
    final badge = b.termine
        ? (label: b.finMotifLabel, tone: 'muted')
        : aTerme
            ? (label: 'À renouveler', tone: 'wait')
            : st == null
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
                b.termine
                    ? (b.finDate == null
                        ? 'Clôturé'
                        : 'Fin : ${_df.format(b.finDate!)}')
                    : prochaine?.dateEcheance == null
                        ? '—'
                        : '${_df.format(prochaine!.dateEcheance!)}'
                            '${retard != null ? '  ·  +$retard j' : ''}',
                style: TextStyle(
                    fontSize: 12.5,
                    color: retard != null
                        ? const Color(0xFF8A4033)
                        : AppTheme.inkSoft),
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

class _TermeBanner extends StatelessWidget {
  const _TermeBanner({required this.nb});
  final int nb;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF2EDE1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6DBC2)),
      ),
      child: Row(children: [
        const Icon(Icons.event_busy_outlined, size: 18, color: Color(0xFF7A5C1F)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$nb bail${nb > 1 ? 's' : ''} arrive${nb > 1 ? 'nt' : ''} à son terme — '
            'à prolonger ou clôturer',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _SignalementsBanner extends StatelessWidget {
  const _SignalementsBanner({required this.repo});
  final BailRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SignalementLoyer>>(
      stream: repo.signalementsEnAttente(),
      builder: (context, snap) {
        final n = snap.data?.length ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF2EDE1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6DBC2)),
            ),
            child: Row(children: [
              const Icon(Icons.notifications_active_outlined,
                  size: 18, color: Color(0xFF7A5C1F)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$n paiement${n > 1 ? 's' : ''} déclaré${n > 1 ? 's' : ''} '
                  'par un locataire — à confirmer sur la fiche du bail',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        );
      },
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

// ── Dialogue « Relevé par propriétaire » ───────────────────────────────────

enum _PPeriode { moisEnCours, moisDernier, trimestre, annee, tout }

class _RelevePartDialog extends StatefulWidget {
  const _RelevePartDialog({
    required this.baux,
    required this.echeances,
    required this.depenses,
    required this.agence,
  });
  final List<Bail> baux;
  final List<Echeance> echeances;
  final List<Depense> depenses;
  final String agence;

  @override
  State<_RelevePartDialog> createState() => _RelevePartDialogState();
}

class _RelevePartDialogState extends State<_RelevePartDialog> {
  String? _prop;
  _PPeriode _p = _PPeriode.moisEnCours;
  bool _excel = false;
  bool _busy = false;

  List<String> get _proprios {
    final s = <String>{
      for (final b in widget.baux)
        if (b.proprietaireNom.isNotEmpty) b.proprietaireNom,
    }.toList()
      ..sort();
    return s;
  }

  ({DateTime debut, DateTime fin, String label}) _bornes() {
    final now = DateTime.now();
    switch (_p) {
      case _PPeriode.moisEnCours:
        return (
          debut: DateTime(now.year, now.month, 1),
          fin: DateTime(now.year, now.month + 1, 0),
          label: DateFormat('MMMM yyyy', 'fr').format(now),
        );
      case _PPeriode.moisDernier:
        final m = DateTime(now.year, now.month - 1, 1);
        return (
          debut: m,
          fin: DateTime(m.year, m.month + 1, 0),
          label: DateFormat('MMMM yyyy', 'fr').format(m),
        );
      case _PPeriode.trimestre:
        return (
          debut: DateTime(now.year, now.month - 2, 1),
          fin: DateTime(now.year, now.month + 1, 0),
          label: '3 derniers mois',
        );
      case _PPeriode.annee:
        return (
          debut: DateTime(now.year, 1, 1),
          fin: DateTime(now.year, 12, 31),
          label: 'Année ${now.year}',
        );
      case _PPeriode.tout:
        return (
          debut: DateTime(2020),
          fin: DateTime(now.year + 1),
          label: 'Depuis le début',
        );
    }
  }

  Future<void> _go() async {
    final prop = _prop;
    if (prop == null) return;
    setState(() => _busy = true);
    final b = _bornes();
    try {
      await BailReleve.parProprietaire(
        proprietaire: prop,
        baux: widget.baux.where((x) => x.proprietaireNom == prop).toList(),
        echeances: widget.echeances,
        depenses: widget.depenses,
        agence: widget.agence,
        debut: b.debut,
        fin: b.fin,
        periodeLabel: b.label,
        excel: _excel,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Génération impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = {
      _PPeriode.moisEnCours: 'Mois en cours',
      _PPeriode.moisDernier: 'Mois dernier',
      _PPeriode.trimestre: '3 derniers mois',
      _PPeriode.annee: 'Année civile',
      _PPeriode.tout: 'Depuis le début',
    };
    _prop ??= _proprios.isEmpty ? null : _proprios.first;

    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Relevé par propriétaire', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _lbl('Propriétaire'),
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _prop,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 13, color: AppTheme.ink),
                  items: [
                    for (final p in _proprios)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => setState(() => _prop = v),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _lbl('Période'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in labels.entries)
                  GestureDetector(
                    onTap: () => setState(() => _p = e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _p == e.key ? AppTheme.ink : Colors.white,
                        border: Border.all(
                            color: _p == e.key ? AppTheme.ink : AppTheme.line),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(e.value,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _p == e.key
                                  ? Colors.white
                                  : AppTheme.ink)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _lbl('Format'),
            Row(children: [
              _fmtPill('PDF', !_excel, () => setState(() => _excel = false)),
              const SizedBox(width: 8),
              _fmtPill('Excel', _excel, () => setState(() => _excel = true)),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _busy || _prop == null ? null : _go,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Télécharger'),
        ),
      ],
    );
  }

  Widget _fmtPill(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: on ? AppTheme.ink : Colors.white,
            border: Border.all(color: on ? AppTheme.ink : AppTheme.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : AppTheme.ink)),
        ),
      );

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}
