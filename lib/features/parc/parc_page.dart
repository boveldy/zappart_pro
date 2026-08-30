import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/house.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class ParcPage extends StatefulWidget {
  const ParcPage({super.key});

  @override
  State<ParcPage> createState() => _ParcPageState();
}

class _ParcPageState extends State<ParcPage> {
  String _query = '';
  String _statut = 'Tous';
  String _type = 'Tous';
  String _quartier = 'Tous';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null) {
      return const PageScaffold(
        title: 'Parc',
        child: EmptyState('Fiche partenaire en cours de liaison…'),
      );
    }
    if (!auth.estHote) {
      return const PageScaffold(
        title: 'Parc',
        child: EmptyState(
          'Votre compte est prestataire de services — pas de parc immobilier.',
        ),
      );
    }
    final repo = HouseRepository(ref);

    return StreamBuilder<List<House>>(
      stream: repo.mine(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const PageScaffold(
            title: 'Parc',
            child: EmptyState('Impossible de charger vos biens.'),
          );
        }
        final all = snap.data;
        final quartiers = <String>{
          for (final h in all ?? const <House>[])
            if (h.quartier.isNotEmpty) h.quartier
        }.toList()
          ..sort();

        return PageScaffold(
          title: 'Parc',
          subtitle: all == null
              ? null
              : '${all.length} bien${all.length > 1 ? 's' : ''}'
                  ' · ${all.where((h) => h.enLigne).length} en ligne',
          actions: [
            FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'La création d\'annonce depuis le web arrive bientôt. '
                    'En attendant, ajoutez un bien depuis l\'app Zappart.',
                  ),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.ink,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: GoogleFonts.mavenPro(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: const Text('＋ Ajouter une annonce'),
            ),
          ],
          child: Column(
            children: [
              _FilterBar(
                query: _query,
                statut: _statut,
                type: _type,
                quartier: _quartier,
                quartiers: quartiers,
                onQuery: (v) => setState(() => _query = v),
                onStatut: (v) => setState(() => _statut = v),
                onType: (v) => setState(() => _type = v),
                onQuartier: (v) => setState(() => _quartier = v),
              ),
              const SizedBox(height: 14),
              if (all == null)
                const AppCard(child: SkeletonBox(height: 260))
              else
                _Table(rows: _filter(all)),
            ],
          ),
        );
      },
    );
  }

  List<House> _filter(List<House> src) {
    bool matchStatut(House h) => switch (_statut) {
          'En ligne' => h.enLigne,
          'Hors ligne' => h.horsLigne,
          'En validation' => h.enValidation,
          'Rejetées' => h.rejetee,
          _ => true,
        };
    final q = _query.trim().toLowerCase();
    return src.where((h) {
      if (!matchStatut(h)) return false;
      if (_type != 'Tous' && h.locationType != _type) return false;
      if (_quartier != 'Tous' && h.quartier != _quartier) return false;
      if (q.isNotEmpty &&
          !h.titre.toLowerCase().contains(q) &&
          !h.cite.toLowerCase().contains(q) &&
          !'${h.numBien}'.contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.query,
    required this.statut,
    required this.type,
    required this.quartier,
    required this.quartiers,
    required this.onQuery,
    required this.onStatut,
    required this.onType,
    required this.onQuartier,
  });

  final String query, statut, type, quartier;
  final List<String> quartiers;
  final ValueChanged<String> onQuery, onStatut, onType, onQuartier;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            onChanged: onQuery,
            decoration: InputDecoration(
              hintText: 'Rechercher (quartier, cité, n°)',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              hintStyle:
                  GoogleFonts.mavenPro(fontSize: 12.5, color: AppTheme.inkSoft),
            ),
            style: GoogleFonts.mavenPro(fontSize: 13),
          ),
        ),
        _Dropdown(
          value: statut,
          items: const [
            'Tous',
            'En ligne',
            'Hors ligne',
            'En validation',
            'Rejetées'
          ],
          onChanged: onStatut,
        ),
        _Dropdown(
          value: type,
          items: const ['Tous', 'Journalier', 'Mensuel'],
          onChanged: onType,
        ),
        _Dropdown(
          value: quartier,
          items: ['Tous', ...quartiers],
          onChanged: onQuartier,
        ),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });
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
          style: GoogleFonts.mavenPro(fontSize: 12.5, color: AppTheme.ink),
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

class _Table extends StatelessWidget {
  const _Table({required this.rows});
  final List<House> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const AppCard(
        child: EmptyState('Aucun bien ne correspond.', icon: Icons.home_work_outlined),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              const SizedBox(width: 52),
              _h('Bien', flex: 4),
              _h('Type', flex: 2),
              _h('Prix', flex: 2, right: true),
              _h('Note', flex: 2),
              _h('Statut', flex: 2),
              const SizedBox(width: 24),
            ]),
          ),
          for (final h in rows) _Row(h),
        ],
      ),
    );
  }

  static Widget _h(String t, {int flex = 1, bool right = false}) => Expanded(
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

class _Row extends StatelessWidget {
  const _Row(this.h);
  final House h;

  static final _fmt = NumberFormat.decimalPattern('fr');

  @override
  Widget build(BuildContext context) {
    final b = h.badge;
    return InkWell(
      onTap: () => context.go('/parc/${h.id}'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 42,
                height: 42,
                child: h.images.isEmpty
                    ? Container(
                        color: AppTheme.panel,
                        child: const Icon(Icons.home_outlined,
                            size: 18, color: AppTheme.inkSoft))
                    : CachedNetworkImage(
                        imageUrl: h.images.first,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppTheme.panel),
                        errorWidget: (_, __, ___) => Container(
                            color: AppTheme.panel,
                            child: const Icon(Icons.broken_image_outlined,
                                size: 16, color: AppTheme.inkSoft)),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(h.titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.mavenPro(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                  h.locationType.isEmpty ? h.type : h.locationType,
                  style: GoogleFonts.mavenPro(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                h.prixAffiche == null
                    ? '—'
                    : _fmt.format(h.prixAffiche!.round()),
                textAlign: TextAlign.right,
                style: GoogleFonts.mavenPro(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  (h.nbAvis ?? 0) == 0
                      ? '—'
                      : '★ ${h.noteMoyenne?.toStringAsFixed(1) ?? '–'} (${h.nbAvis})',
                  style: GoogleFonts.mavenPro(
                      fontSize: 12, color: AppTheme.inkSoft),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(b.label, tone: b.tone),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppTheme.inkSoft),
          ],
        ),
      ),
    );
  }
}
