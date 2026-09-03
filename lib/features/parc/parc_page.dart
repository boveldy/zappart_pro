import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/house.dart';
import '../../data/permissions.dart';
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
    final ref = auth.agenceRef;
    if (!auth.aGerance || ref == null) {
      return const PageScaffold(
        title: 'Parc',
        child: EmptyState(
          'Votre compte est prestataire de services — pas de parc immobilier.',
        ),
      );
    }
    final canCreer = auth.can(ProPerm.biensCreer);
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
            TextButton.icon(
              onPressed: () => context.go('/parc/archives'),
              icon: const Icon(Icons.inventory_2_outlined, size: 15),
              label: const Text('Biens archivés'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.inkSoft,
                textStyle: GoogleFonts.mavenPro(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            if (canCreer) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => context.go('/parc/nouveau'),
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
                _Results(rows: _filter(all)),
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
          'Brouillons' => h.brouillon,
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
            'Brouillons',
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

class _Results extends StatelessWidget {
  const _Results({required this.rows});
  final List<House> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const AppCard(
        child: EmptyState('Aucun bien ne correspond.',
            icon: Icons.home_work_outlined),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      const gap = 18.0;
      const minCard = 264.0;
      var cols = (c.maxWidth / (minCard + gap)).floor().clamp(1, 4);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final h in rows) SizedBox(width: w, child: _BienCard(h)),
        ],
      );
    });
  }
}

class _BienCard extends StatelessWidget {
  const _BienCard(this.h);
  final House h;

  static final _fmt = NumberFormat.decimalPattern('fr');

  @override
  Widget build(BuildContext context) {
    final b = h.badge;
    final lieu = [
      h.locationType.isEmpty ? h.type : h.locationType,
      if (h.zone.isNotEmpty) h.zone else h.quartier,
    ].where((e) => e.isNotEmpty).join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.go('/parc/${h.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 3 / 2,
                    child: h.images.isEmpty
                        ? Container(
                            color: AppTheme.panel,
                            child: const Icon(Icons.home_outlined,
                                size: 30, color: AppTheme.inkSoft))
                        : CachedNetworkImage(
                            imageUrl: h.images.first,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: AppTheme.panel),
                            errorWidget: (_, __, ___) => Container(
                                color: AppTheme.panel,
                                child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: AppTheme.inkSoft)),
                          ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: StatusChip(b.label, tone: b.tone),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.titre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 13, color: AppTheme.inkSoft),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(lieu,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.inkSoft)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _spec(Icons.bed_outlined, '${h.nbChambre ?? 0}'),
                        _spec(Icons.bathtub_outlined, '${h.nbBain ?? 0}'),
                        if ((h.surface ?? 0) > 0)
                          _spec(Icons.straighten, '${h.surface} m²'),
                        if ((h.nbAvis ?? 0) > 0)
                          _spec(Icons.star_border,
                              h.noteMoyenne?.toStringAsFixed(1) ?? '–'),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(color: AppTheme.ink),
                              children: [
                                TextSpan(
                                  text: h.prixAffiche == null
                                      ? '—'
                                      : _fmt.format(h.prixAffiche!.round()),
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800),
                                ),
                                TextSpan(
                                  text: '  ${h.uniteLabel}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.inkSoft),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Text('Voir la fiche',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.terracotta)),
                        const Icon(Icons.arrow_forward,
                            size: 13, color: AppTheme.terracotta),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _spec(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(i, size: 14, color: AppTheme.inkSoft),
            const SizedBox(width: 3),
            Text(t,
                style: const TextStyle(
                    fontSize: 11.5, color: AppTheme.inkSoft)),
          ],
        ),
      );
}
