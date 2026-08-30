import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/reservations_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Réservations sur les logements de l'hôte : file des demandes d'accord à
/// traiter + relevé filtrable (type / statut / période). L'accord de
/// disponibilité passe par le callable `reservations` (`repondre_disponibilite`,
/// inchangé) — il est informatif, il n'engage pas le paiement.
class ReservationsPage extends StatefulWidget {
  const ReservationsPage({super.key});

  @override
  State<ReservationsPage> createState() => _ReservationsPageState();
}

class _ReservationsPageState extends State<ReservationsPage> {
  String _type = 'Tous';
  String _statut = 'Tous';
  String _periode = 'Toutes';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null || !auth.estHote) {
      return const PageScaffold(
        title: 'Réservations',
        child: EmptyState(
            'Votre compte est prestataire — voir l\'onglet Missions sur mobile.'),
      );
    }
    final repo = ReservationsRepository(ref);

    return StreamBuilder<Map<String, String>>(
      stream: repo.houseTitles(),
      builder: (context, titlesSnap) {
        final titles = titlesSnap.data ?? const <String, String>{};
        return StreamBuilder<List<ResaFull>>(
          stream: repo.reservations(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const PageScaffold(
                title: 'Réservations',
                child: EmptyState('Impossible de charger les réservations.'),
              );
            }
            final all = snap.data;
            final pending =
                (all ?? const <ResaFull>[]).where((r) => r.demandeAccord).toList();
            final rows = all == null ? null : _filter(all);

            return PageScaffold(
              title: 'Réservations',
              subtitle: all == null
                  ? null
                  : '${all.length} au total · ${all.where((r) => r.aVenir).length} à venir',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pending.isNotEmpty) ...[
                    _PendingCard(
                      pending: pending,
                      titles: titles,
                      onRepondre: (r, rep) => _repondre(repo, r, rep),
                    ),
                    const SizedBox(height: 18),
                  ],
                  _Filters(
                    type: _type,
                    statut: _statut,
                    periode: _periode,
                    onType: (v) => setState(() => _type = v),
                    onStatut: (v) => setState(() => _statut = v),
                    onPeriode: (v) => setState(() => _periode = v),
                  ),
                  const SizedBox(height: 14),
                  if (rows == null)
                    const AppCard(child: SkeletonBox(height: 260))
                  else
                    _Table(
                      rows: rows,
                      titles: titles,
                      onTap: (r) => _detail(repo, r, titles),
                      onRepondre: (r, rep) => _repondre(repo, r, rep),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<ResaFull> _filter(List<ResaFull> src) {
    final now = DateTime.now();
    return src.where((r) {
      if (_type != 'Tous' && r.typeCourt != _type) return false;
      if (_statut != 'Tous') {
        if (_statut == "Demande d'accord" && !r.demandeAccord) return false;
        if (_statut != "Demande d'accord" && r.status != _statut) return false;
      }
      if (_periode == 'À venir' && !r.aVenir) return false;
      if (_periode == 'Passées' && (r.aVenir || !r.clos && r.dateDebut == null)) {
        return false;
      }
      if (_periode == 'Ce mois') {
        final d = r.dateDebut ?? r.dateCreated;
        if (d == null || d.year != now.year || d.month != now.month) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _repondre(
      ReservationsRepository repo, ResaFull r, String rep) async {
    final err = await repo.repondre(r.id, rep);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ??
          (rep == 'accepte'
              ? 'Disponibilité confirmée au client.'
              : 'Refus envoyé au client.')),
    ));
  }

  void _detail(
      ReservationsRepository repo, ResaFull r, Map<String, String> titles) {
    showDialog<void>(
      context: context,
      builder: (_) => _DetailDialog(
        r: r,
        bien: titles[r.houseId] ?? '—',
        onRepondre: (rep) {
          Navigator.pop(context);
          _repondre(repo, r, rep);
        },
      ),
    );
  }
}

// ── File des demandes d'accord ─────────────────────────────────────────────

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.pending,
    required this.titles,
    required this.onRepondre,
  });
  final List<ResaFull> pending;
  final Map<String, String> titles;
  final void Function(ResaFull, String) onRepondre;

  static final _df = DateFormat('EEEE d MMM', 'fr');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF6EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8DCC2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${pending.length} demande${pending.length > 1 ? 's' : ''} '
              'd\'accord à traiter',
              style:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          const Text(
            'Le client attend votre confirmation de disponibilité avant de payer.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 12),
          for (final r in pending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.clientNom} · ${r.typeCourt}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(
                          [
                            titles[r.houseId] ?? '—',
                            if (r.dateDebut != null)
                              _cap(_df.format(r.dateDebut!)),
                          ].join('  ·  '),
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => onRepondre(r, 'refuse'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: Color(0xFFE3C9C4)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Refuser'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => onRepondre(r, 'accepte'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Accepter'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// ── Filtres ────────────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  const _Filters({
    required this.type,
    required this.statut,
    required this.periode,
    required this.onType,
    required this.onStatut,
    required this.onPeriode,
  });
  final String type, statut, periode;
  final ValueChanged<String> onType, onStatut, onPeriode;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _Dropdown(
          value: type,
          items: const ['Tous', 'Visite', 'Journalier', 'Mensuel', 'Service'],
          onChanged: onType,
        ),
        _Dropdown(
          value: statut,
          items: const [
            'Tous',
            "Demande d'accord",
            'En attente',
            'Réservée',
            'Soldée',
            'Terminée',
            'Annulée',
          ],
          onChanged: onStatut,
        ),
        _Dropdown(
          value: periode,
          items: const ['Toutes', 'À venir', 'Ce mois', 'Passées'],
          onChanged: onPeriode,
        ),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown(
      {required this.value, required this.items, required this.onChanged});
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

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
          value: items.contains(value) ? value : items.first,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(fontSize: 12.5, color: AppTheme.ink),
          items: [
            for (final i in items)
              DropdownMenuItem(value: i, child: Text(i)),
          ],
          onChanged: (v) => onChanged(v ?? items.first),
        ),
      ),
    );
  }
}

// ── Tableau ────────────────────────────────────────────────────────────────

class _Table extends StatelessWidget {
  const _Table({
    required this.rows,
    required this.titles,
    required this.onTap,
    required this.onRepondre,
  });
  final List<ResaFull> rows;
  final Map<String, String> titles;
  final void Function(ResaFull) onTap;
  final void Function(ResaFull, String) onRepondre;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const AppCard(
        child: EmptyState('Aucune réservation ne correspond.',
            icon: Icons.event_busy_outlined),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              _h('Client', 3),
              _h('Type', 2),
              _h('Logement', 3),
              _h('Dates', 3),
              _h('Prix', 2, right: true),
              _h('Statut', 3),
            ]),
          ),
          for (final r in rows)
            _Row(
              r: r,
              bien: titles[r.houseId] ?? '—',
              onTap: () => onTap(r),
              onRepondre: (rep) => onRepondre(r, rep),
            ),
        ],
      ),
    );
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
}

class _Row extends StatelessWidget {
  const _Row({
    required this.r,
    required this.bien,
    required this.onTap,
    required this.onRepondre,
  });
  final ResaFull r;
  final String bien;
  final VoidCallback onTap;
  final void Function(String) onRepondre;

  static final _df = DateFormat('d MMM', 'fr');
  static final _fmt = NumberFormat('#,###', 'fr_FR');

  @override
  Widget build(BuildContext context) {
    final b = r.statutBadge;
    final dates = r.dateDebut == null
        ? '—'
        : r.dateSorti != null && r.dateSorti != r.dateDebut
            ? '${_df.format(r.dateDebut!)} → ${_df.format(r.dateSorti!)}'
            : _df.format(r.dateDebut!);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(r.clientNom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              flex: 2,
              child: Text(r.typeCourt,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ),
            Expanded(
              flex: 3,
              child: Text(bien,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ),
            Expanded(
              flex: 3,
              child: Text(dates,
                  style: const TextStyle(fontSize: 12.5)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                r.prix == null ? '—' : _fmt.format(r.prix!.round()),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerRight,
                child: r.demandeAccord
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _miniBtn('Refuser', false,
                              () => onRepondre('refuse')),
                          const SizedBox(width: 6),
                          _miniBtn('Accepter', true,
                              () => onRepondre('accepte')),
                        ],
                      )
                    : StatusChip(b.label, tone: b.tone),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(String label, bool filled, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: filled ? AppTheme.ink : Colors.white,
            border: Border.all(
                color: filled ? AppTheme.ink : AppTheme.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : AppTheme.ink)),
        ),
      );
}

// ── Détail ─────────────────────────────────────────────────────────────────

class _DetailDialog extends StatelessWidget {
  const _DetailDialog({
    required this.r,
    required this.bien,
    required this.onRepondre,
  });
  final ResaFull r;
  final String bien;
  final void Function(String) onRepondre;

  static final _df = DateFormat('EEEE d MMMM yyyy', 'fr');
  static final _fmt = NumberFormat('#,###', 'fr_FR');

  @override
  Widget build(BuildContext context) {
    final b = r.statutBadge;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Row(
        children: [
          Expanded(
            child: Text('${r.typeCourt} · ${r.clientNom}',
                style: const TextStyle(fontSize: 16)),
          ),
          StatusChip(b.label, tone: b.tone),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line('Logement', bien),
            if (r.dateDebut != null)
              _line('Arrivée', _cap(_df.format(r.dateDebut!))),
            if (r.dateSorti != null && r.dateSorti != r.dateDebut)
              _line('Départ', _cap(_df.format(r.dateSorti!))),
            _line('Prix', r.prix == null ? '—' : '${_fmt.format(r.prix!.round())} FCFA'),
            if (r.dateCreated != null)
              _line('Demandée le',
                  _cap(DateFormat('d MMM yyyy', 'fr').format(r.dateCreated!))),
            if (r.accordHote.isNotEmpty)
              _line(
                  'Accord hôte',
                  switch (r.accordHote) {
                    'accepte' => 'Accepté',
                    'refuse' => 'Refusé',
                    _ => 'En attente',
                  }),
            if (r.type == 'Reservation visite')
              _line('Bail signé', r.signature ? 'Oui' : 'Non'),
            if (r.decisionClient.isNotEmpty)
              _line(
                  'Décision client',
                  switch (r.decisionClient) {
                    'accepte' => 'Prend le logement',
                    'refuser' => 'Pas intéressé',
                    'reflechir' => 'Réfléchit',
                    _ => r.decisionClient,
                  }),
            const SizedBox(height: 8),
            const Text(
              "La suite du cycle (encaissement, signature, clôture) est gérée "
              "par l'équipe Zappart.",
              style: TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
            ),
          ],
        ),
      ),
      actions: [
        if (r.demandeAccord) ...[
          TextButton(
            onPressed: () => onRepondre('refuse'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Refuser'),
          ),
          ElevatedButton(
            onPressed: () => onRepondre('accepte'),
            child: const Text('Accepter'),
          ),
        ] else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
      ],
    );
  }

  Widget _line(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
