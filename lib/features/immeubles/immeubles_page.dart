import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/house.dart';
import '../../data/immeuble.dart';
import '../../data/permissions.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../parc/immeuble_sheet.dart';

/// Gestion des immeubles / résidences de l'agence. Modifier un immeuble
/// re-propage ses champs sur les biens rattachés (trigger backend
/// `propager_immeuble`), sans re-déclencher de validation.
class ImmeublesPage extends StatelessWidget {
  const ImmeublesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.agenceRef;
    if (ref == null) {
      return const PageScaffold(
        title: 'Immeubles',
        child: EmptyState('Fiche partenaire en cours de liaison…'),
      );
    }
    if (!auth.aGerance) {
      return const PageScaffold(
        title: 'Immeubles',
        child: EmptyState('Réservé aux comptes hôte / agence.'),
      );
    }
    final canGerer = auth.can(ProPerm.immeublesGerer);
    final repo = ImmeubleRepository(ref);
    final houseRepo = HouseRepository(ref);

    return PageScaffold(
      title: 'Immeubles',
      subtitle: 'Les infos communes aux logements d\'un même bâtiment',
      actions: [
        if (canGerer)
        FilledButton(
          onPressed: () => showImmeubleForm(context, repo),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.ink,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                GoogleFonts.mavenPro(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: const Text('＋ Ajouter un immeuble'),
        ),
      ],
      child: StreamBuilder<List<House>>(
        stream: houseRepo.mine(),
        builder: (context, houseSnap) {
          final counts = <String, int>{};
          for (final h in houseSnap.data ?? const <House>[]) {
            if (h.immeubleRefId != null) {
              counts[h.immeubleRefId!] = (counts[h.immeubleRefId!] ?? 0) + 1;
            }
          }
          return StreamBuilder<List<Immeuble>>(
            stream: repo.mine(),
            builder: (context, snap) {
              if (snap.hasError) {
                return const AppCard(
                    child: EmptyState('Impossible de charger les immeubles.'));
              }
              if (!snap.hasData) {
                return const AppCard(child: SkeletonBox(height: 220));
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return const AppCard(
                  child: EmptyState(
                    'Aucun immeuble. Créez-en un pour ne plus ressaisir '
                    'l\'adresse et le concierge à chaque annonce.',
                    icon: Icons.apartment_outlined,
                  ),
                );
              }
              return Column(
                children: [
                  for (final im in rows)
                    _Row(
                      im: im,
                      biens: counts[im.id] ?? 0,
                      repo: repo,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.im, required this.biens, required this.repo});
  final Immeuble im;
  final int biens;
  final ImmeubleRepository repo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_rounded, color: AppTheme.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(im.nom,
                    style: GoogleFonts.mavenPro(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
                if (im.sousTitre.isNotEmpty)
                  Text(im.sousTitre,
                      style: GoogleFonts.mavenPro(
                          fontSize: 12, color: AppTheme.inkSoft)),
                Text(
                  biens == 0
                      ? 'Aucun bien rattaché'
                      : '$biens bien${biens > 1 ? 's' : ''} rattaché${biens > 1 ? 's' : ''}',
                  style: GoogleFonts.mavenPro(
                      fontSize: 11.5, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
          if (context.read<AuthService>().can(ProPerm.immeublesGerer)) ...[
            IconButton(
              onPressed: () => showImmeubleForm(context, repo, existant: im),
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppTheme.inkSoft,
              tooltip: 'Modifier',
            ),
            IconButton(
              onPressed: () => _confirmDelete(context),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: const Color(0xFF8A4033),
              tooltip: 'Supprimer',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (biens > 0) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Immeuble utilisé', style: TextStyle(fontSize: 16)),
          content: Text(
            '$biens bien${biens > 1 ? 's sont' : ' est'} encore rattaché'
            '${biens > 1 ? 's' : ''} à « ${im.nom} ». Détachez-les d\'abord '
            '(dans le wizard de chaque annonce) avant de supprimer l\'immeuble.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Compris')),
          ],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Supprimer cet immeuble ?',
            style: TextStyle(fontSize: 16)),
        content: Text('« ${im.nom} » sera supprimé.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8A4033)),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await repo.delete(im.id);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Suppression impossible.')));
        }
      }
    }
  }
}
