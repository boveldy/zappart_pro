import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/proprietaire.dart';
import '../../theme/app_theme.dart';

/// Feuille de sélection d'un propriétaire (formulaire de bail) : liste + création
/// rapide. Retourne le [Proprietaire] choisi, ou `null` si fermé.
Future<Proprietaire?> pickProprietaire(
    BuildContext context, ProprietaireRepository repo) {
  return showModalBottomSheet<Proprietaire>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _Sheet(repo: repo),
  );
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.repo});
  final ProprietaireRepository repo;
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool _creating = false;
  final _nom = TextEditingController();
  final _tel = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nom.dispose();
    _tel.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nom.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final ref = await widget.repo.create(
        nom: _nom.text,
        telephone: _tel.text,
        email: _email.text,
      );
      final p = await widget.repo.one(ref.id);
      if (mounted && p != null) Navigator.pop(context, p);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Création impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_creating ? 'Nouveau propriétaire' : 'Choisir un propriétaire',
                style: GoogleFonts.mavenPro(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (_creating) ...[
              _f(_nom, 'Nom complet'),
              const SizedBox(height: 10),
              _f(_tel, 'Téléphone', phone: true),
              const SizedBox(height: 10),
              _f(_email, 'E-mail'),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => setState(() => _creating = false),
                    child: const Text('Retour'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_busy || _nom.text.trim().isEmpty) ? null : _create,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Créer et lier'),
                  ),
                ),
              ]),
            ] else ...[
              Flexible(
                child: SingleChildScrollView(
                  child: StreamBuilder<List<Proprietaire>>(
                    stream: widget.repo.mine(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.ink)),
                        );
                      }
                      final ps = snap.data!;
                      if (ps.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('Aucun propriétaire enregistré.',
                              style: GoogleFonts.mavenPro(
                                  fontSize: 13.5, color: AppTheme.inkSoft)),
                        );
                      }
                      return Column(
                        children: [
                          for (final p in ps)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: AppTheme.panel,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => Navigator.pop(context, p),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    child: Row(children: [
                                      const Icon(Icons.person_outline,
                                          color: AppTheme.ink),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(p.nom,
                                                style: GoogleFonts.mavenPro(
                                                    fontSize: 14.5,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            if (p.sousTitre.isNotEmpty)
                                              Text(p.sousTitre,
                                                  style: GoogleFonts.mavenPro(
                                                      fontSize: 12,
                                                      color: AppTheme.inkSoft)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded,
                                          color: AppTheme.inkSoft),
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _creating = true),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Créer un propriétaire'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.ink,
                    side: const BorderSide(color: AppTheme.line),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _f(TextEditingController c, String label, {bool phone = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            keyboardType: phone ? TextInputType.phone : null,
            onChanged: (_) => setState(() {}),
          ),
        ],
      );
}
