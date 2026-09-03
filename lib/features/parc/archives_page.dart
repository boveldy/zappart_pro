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

/// Biens retirés du parc (`statut_validation: 'supprimee'`). L'hôte les retrouve
/// ici et peut les **restaurer** — ils repartent alors en file de validation.
class ArchivesPage extends StatelessWidget {
  const ArchivesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<AuthService>().agenceRef;
    if (ref == null) {
      return const PageScaffold(
        title: 'Biens archivés',
        child: EmptyState('Fiche partenaire en cours de liaison…'),
      );
    }
    final repo = HouseRepository(ref);

    return PageScaffold(
      title: 'Biens archivés',
      subtitle: 'Biens retirés du parc — restaurables',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => context.go('/parc'),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Parc'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.inkSoft,
              padding: EdgeInsets.zero,
              textStyle:
                  GoogleFonts.mavenPro(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<House>>(
            stream: repo.archives(),
            builder: (context, snap) {
              if (snap.hasError) {
                return const AppCard(
                    child: EmptyState('Impossible de charger les archives.'));
              }
              if (!snap.hasData) {
                return const AppCard(child: SkeletonBox(height: 200));
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return const AppCard(
                  child: EmptyState(
                    'Aucun bien archivé.',
                    icon: Icons.inventory_2_outlined,
                  ),
                );
              }
              return Column(
                children: [
                  for (final h in rows) _ArchiveRow(house: h, repo: repo),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ArchiveRow extends StatefulWidget {
  const _ArchiveRow({required this.house, required this.repo});
  final House house;
  final HouseRepository repo;

  @override
  State<_ArchiveRow> createState() => _ArchiveRowState();
}

class _ArchiveRowState extends State<_ArchiveRow> {
  bool _busy = false;

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await widget.repo.restore(widget.house.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bien restauré — il repart en validation.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Restauration impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.house;
    final df = DateFormat('d MMM yyyy', 'fr');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: h.images.isEmpty
                  ? Container(
                      color: AppTheme.panel,
                      child: const Icon(Icons.image_outlined,
                          size: 20, color: AppTheme.inkSoft))
                  : CachedNetworkImage(
                      imageUrl: h.images.first,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppTheme.panel),
                      errorWidget: (_, __, ___) =>
                          Container(color: AppTheme.panel),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.mavenPro(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(
                  [
                    if (h.locationType.isNotEmpty) h.locationType,
                    if (h.type.isNotEmpty) h.type,
                    if (h.createdAt != null) 'créé le ${df.format(h.createdAt!)}',
                  ].join(' · '),
                  style: GoogleFonts.mavenPro(
                      fontSize: 11.5, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : OutlinedButton(
                  onPressed: _restore,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.ink,
                    side: const BorderSide(color: AppTheme.line),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: GoogleFonts.mavenPro(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Restaurer'),
                ),
        ],
      ),
    );
  }
}
