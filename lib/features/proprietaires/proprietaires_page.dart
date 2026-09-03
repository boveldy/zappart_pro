import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/permissions.dart';
import '../../data/proprietaire.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Liste des propriétaires (bailleurs) de l'agence. Sert à lier les baux et à
/// consolider les relevés de gérance.
class ProprietairesPage extends StatelessWidget {
  const ProprietairesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.agenceRef;
    if (ref == null) {
      return const PageScaffold(
        title: 'Propriétaires',
        child: EmptyState('Fiche partenaire en cours de liaison…'),
      );
    }
    if (!auth.aGerance) {
      return const PageScaffold(
        title: 'Propriétaires',
        child: EmptyState('Réservé aux comptes hôte / agence.'),
      );
    }
    final canGerer = auth.can(ProPerm.proprietairesGerer);
    final repo = ProprietaireRepository(ref);

    return PageScaffold(
      title: 'Propriétaires',
      subtitle: 'Les bailleurs dont vous gérez les biens',
      actions: [
        if (canGerer)
        FilledButton(
          onPressed: () => _openForm(context, repo, null),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.ink,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                GoogleFonts.mavenPro(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: const Text('＋ Ajouter un propriétaire'),
        ),
      ],
      child: StreamBuilder<List<Proprietaire>>(
        stream: repo.mine(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const AppCard(
                child: EmptyState('Impossible de charger les propriétaires.'));
          }
          if (!snap.hasData) {
            return const AppCard(child: SkeletonBox(height: 220));
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const AppCard(
              child: EmptyState(
                'Aucun propriétaire. Ajoutez-en un, puis rattachez-le à un bail.',
                icon: Icons.person_outline,
              ),
            );
          }
          return Column(
            children: [
              for (final p in rows) _Row(p: p, repo: repo),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _openForm(
      BuildContext context, ProprietaireRepository repo, Proprietaire? p) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ProprietaireForm(repo: repo, existant: p),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.p, required this.repo});
  final Proprietaire p;
  final ProprietaireRepository repo;

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nom,
                    style: GoogleFonts.mavenPro(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
                if (p.sousTitre.isNotEmpty)
                  Text(p.sousTitre,
                      style: GoogleFonts.mavenPro(
                          fontSize: 12, color: AppTheme.inkSoft)),
                if (p.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(p.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.mavenPro(
                            fontSize: 11.5, color: AppTheme.inkSoft)),
                  ),
              ],
            ),
          ),
          if (context.read<AuthService>().can(ProPerm.proprietairesGerer)) ...[
            IconButton(
              onPressed: () =>
                  ProprietairesPage._openForm(context, repo, p),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Supprimer ce propriétaire ?',
            style: TextStyle(fontSize: 16)),
        content: Text(
          '${p.nom} sera retiré de la liste. Les baux déjà liés gardent le nom '
          'du propriétaire (les relevés restent corrects).',
          style: const TextStyle(fontSize: 13),
        ),
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
        await repo.delete(p.id);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Suppression impossible.')));
        }
      }
    }
  }
}

class _ProprietaireForm extends StatefulWidget {
  const _ProprietaireForm({required this.repo, this.existant});
  final ProprietaireRepository repo;
  final Proprietaire? existant;

  @override
  State<_ProprietaireForm> createState() => _ProprietaireFormState();
}

class _ProprietaireFormState extends State<_ProprietaireForm> {
  late final _nom = TextEditingController(text: widget.existant?.nom ?? '');
  late final _tel =
      TextEditingController(text: widget.existant?.telephone ?? '');
  late final _email = TextEditingController(text: widget.existant?.email ?? '');
  late final _note = TextEditingController(text: widget.existant?.note ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _nom.dispose();
    _tel.dispose();
    _email.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nom.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      if (widget.existant == null) {
        await widget.repo.create(
          nom: _nom.text,
          telephone: _tel.text,
          email: _email.text,
          note: _note.text,
        );
      } else {
        await widget.repo.update(
          widget.existant!.id,
          nom: _nom.text,
          telephone: _tel.text,
          email: _email.text,
          note: _note.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enregistrement impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
          widget.existant == null ? 'Nouveau propriétaire' : 'Modifier',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _lbl('Nom complet'),
            TextField(
              controller: _nom,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Ex. M. Sarr'),
            ),
            const SizedBox(height: 12),
            _lbl('Téléphone'),
            TextField(
              controller: _tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: '+221 77 000 00 00'),
            ),
            const SizedBox(height: 12),
            _lbl('E-mail'),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'nom@exemple.com'),
            ),
            const SizedBox(height: 12),
            _lbl('Note (optionnel)'),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                  hintText: 'RIB, préférences de reversement, remarques…'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: (_busy || _nom.text.trim().isEmpty) ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Text(t,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      );
}
