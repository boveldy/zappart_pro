import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/journal_pro.dart';
import '../../data/permissions.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Historique d'activité de l'agence — qui a fait quoi. Réservé à `journal.voir`.
/// Vue plafonnée aux 200 dernières actions (V1).
class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  String _acteur = 'Tous';
  String _famille = 'Toutes';

  static const _familles = <String, String>{
    'Toutes': '',
    'Baux & loyers': 'bail.|echeance.|signalement.|depense.|encaissement.',
    'Annonces': 'bien.',
    'Propriétaires / immeubles': 'proprietaire.|immeuble.',
    'Équipe': 'membre.',
  };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.agenceRef;
    if (ref == null || !auth.can(ProPerm.journalVoir)) {
      return const PageScaffold(
        title: 'Historique',
        child: EmptyState('Accès réservé à l\'administrateur de l\'agence.'),
      );
    }

    return StreamBuilder<List<JournalEntry>>(
      stream: Journal.stream(ref),
      builder: (context, snap) {
        final all = snap.data ?? const <JournalEntry>[];
        final acteurs = <String>{'Tous', for (final e in all) e.acteurNom}
            .toList();
        final prefixes = _familles[_famille]!.split('|').where((p) => p.isNotEmpty);
        final filtered = all.where((e) {
          if (_acteur != 'Tous' && e.acteurNom != _acteur) return false;
          if (prefixes.isNotEmpty &&
              !prefixes.any((p) => e.action.startsWith(p))) {
            return false;
          }
          return true;
        }).toList();

        return PageScaffold(
          title: 'Historique',
          subtitle: '${all.length} dernière${all.length > 1 ? 's' : ''} '
              'action${all.length > 1 ? 's' : ''} de l\'équipe',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Drop(
                    value: _famille,
                    items: _familles.keys.toList(),
                    onChanged: (v) => setState(() => _famille = v),
                  ),
                  _Drop(
                    value: _acteur,
                    items: acteurs,
                    onChanged: (v) => setState(() => _acteur = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (snap.connectionState == ConnectionState.waiting)
                const SkeletonBox(height: 160)
              else if (filtered.isEmpty)
                const EmptyState('Aucune action pour ce filtre.')
              else
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: [
                      for (final e in filtered) _EntryRow(e: e),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Drop extends StatelessWidget {
  const _Drop(
      {required this.value, required this.items, required this.onChanged});
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<String>(
        value: items.contains(value) ? value : items.first,
        underline: const SizedBox.shrink(),
        isDense: true,
        borderRadius: BorderRadius.circular(10),
        style: GoogleFonts.mavenPro(
            fontSize: 12.5, color: AppTheme.ink, fontWeight: FontWeight.w600),
        items: [
          for (final i in items)
            DropdownMenuItem(value: i, child: Text(i)),
        ],
        onChanged: (v) => onChanged(v ?? items.first),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.e});
  final JournalEntry e;

  static final _df = DateFormat('d MMM · HH:mm', 'fr');
  static final _fmt = NumberFormat('#,###', 'fr_FR');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.mavenPro(
                        fontSize: 12.5, color: AppTheme.ink),
                    children: [
                      TextSpan(
                          text: e.acteurNom,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' ${e.actionLabel}'),
                    ],
                  ),
                ),
                if (e.cibleLibelle.isNotEmpty)
                  Text(
                    e.montant != null
                        ? '${e.cibleLibelle} · ${_fmt.format(e.montant!.round())} FCFA'
                        : e.cibleLibelle,
                    style: GoogleFonts.mavenPro(
                        fontSize: 11.5, color: AppTheme.inkSoft),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(e.date == null ? '' : _df.format(e.date!),
              style: GoogleFonts.mavenPro(
                  fontSize: 10.5, color: AppTheme.inkSoft)),
        ],
      ),
    );
  }
}
