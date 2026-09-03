import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/calendar_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Calendrier multi-biens : disponibilités de tout le parc, mois par mois.
/// Les jours occupés viennent de `house.blockedRanges` (réservations Zappart +
/// calendriers externes Airbnb/Booking, déjà fusionnés côté backend). Les
/// séjours Zappart sont superposés pour afficher le client.
class CalendrierPage extends StatefulWidget {
  const CalendrierPage({super.key});

  @override
  State<CalendrierPage> createState() => _CalendrierPageState();
}

class _CalendrierPageState extends State<CalendrierPage> {
  late DateTime _mois;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _mois = DateTime(n.year, n.month);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.agenceRef;
    if (ref == null || !auth.aGerance) {
      return const PageScaffold(
        title: 'Calendrier',
        child: EmptyState('Votre compte est prestataire — pas de parc à planifier.'),
      );
    }
    final repo = CalendarRepository(ref);

    return StreamBuilder<List<CalBien>>(
      stream: repo.biens(),
      builder: (context, bs) {
        return StreamBuilder<List<CalSejour>>(
          stream: repo.sejours(),
          builder: (context, ss) {
            if (bs.hasError) {
              return const PageScaffold(
                title: 'Calendrier',
                child: EmptyState('Impossible de charger le calendrier.'),
              );
            }
            final biens = bs.data;
            final sejours = ss.data ?? const <CalSejour>[];

            return PageScaffold(
              title: 'Calendrier',
              subtitle: biens == null
                  ? null
                  : '${biens.where((b) => b.isJournalier).length} en journalier · '
                      '${biens.where((b) => !b.isJournalier).length} en mensuel',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MonthBar(
                    mois: _mois,
                    onPrev: () => setState(
                        () => _mois = DateTime(_mois.year, _mois.month - 1)),
                    onNext: () => setState(
                        () => _mois = DateTime(_mois.year, _mois.month + 1)),
                    onToday: () {
                      final n = DateTime.now();
                      setState(() => _mois = DateTime(n.year, n.month));
                    },
                  ),
                  const SizedBox(height: 12),
                  const _Legend(),
                  const SizedBox(height: 14),
                  if (biens == null)
                    const AppCard(child: SkeletonBox(height: 300))
                  else if (biens.isEmpty)
                    const AppCard(
                      child: EmptyState(
                        'Aucun bien. Ajoutez une annonce depuis le Parc.',
                        icon: Icons.home_work_outlined,
                      ),
                    )
                  else ...[
                    _Grid(
                      mois: _mois,
                      biens: biens.where((b) => b.isJournalier).toList(),
                      sejours: sejours,
                      onIcal: (b) => _editIcal(context, repo, b),
                    ),
                    const SizedBox(height: 20),
                    _Mensuels(
                      biens: biens.where((b) => !b.isJournalier).toList(),
                      sejours: sejours,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editIcal(
      BuildContext context, CalendarRepository repo, CalBien b) async {
    final ctrls = [
      for (var i = 0; i < 4; i++)
        TextEditingController(
            text: i < b.icalUrls.length ? b.icalUrls[i] : ''),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Calendriers externes', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Collez ici les liens .ics d\'export de vos calendriers Airbnb / '
                'Booking pour ${b.titre}. Zappart bloque automatiquement ces '
                'dates (relu toutes les 3 h).',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: ctrls[i],
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Lien .ics ${i + 1}',
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await repo.setIcalUrls(b.id, ctrls.map((c) => c.text).toList());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Calendriers externes enregistrés.')));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Échec de l\'enregistrement.')));
        }
      }
    }
    for (final c in ctrls) {
      c.dispose();
    }
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.mois,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });
  final DateTime mois;
  final VoidCallback onPrev, onNext, onToday;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM yyyy', 'fr').format(mois);
    return Row(
      children: [
        _btn(Icons.chevron_left, onPrev),
        const SizedBox(width: 6),
        _btn(Icons.chevron_right, onNext),
        const SizedBox(width: 14),
        Text(
          '${label[0].toUpperCase()}${label.substring(1)}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: onToday,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.ink,
            side: const BorderSide(color: AppTheme.line),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text("Aujourd'hui"),
        ),
      ],
    );
  }

  Widget _btn(IconData i, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppTheme.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(i, size: 18, color: AppTheme.ink),
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t, {bool border = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
                border: border ? Border.all(color: AppTheme.line) : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(t, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
          ],
        );
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        item(Colors.white, 'Libre', border: true),
        item(AppTheme.ink, 'Réservé (client Zappart)'),
        item(const Color(0xFFD6D6D6), 'Bloqué (Airbnb / Booking / manuel)'),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.mois,
    required this.biens,
    required this.sejours,
    required this.onIcal,
  });
  final DateTime mois;
  final List<CalBien> biens;
  final List<CalSejour> sejours;
  final void Function(CalBien) onIcal;

  static const _cw = 30.0;
  static const _rh = 46.0;
  static const _nameW = 190.0;

  @override
  Widget build(BuildContext context) {
    if (biens.isEmpty) {
      return const AppCard(
        child: EmptyState('Aucun bien en location journalière.'),
      );
    }
    final nDays = DateUtils.getDaysInMonth(mois.year, mois.month);
    final days = [for (var d = 1; d <= nDays; d++) DateTime(mois.year, mois.month, d)];
    final today = DateUtils.dateOnly(DateTime.now());

    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colonne fixe : noms des biens
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 30, width: _nameW),
              for (final b in biens)
                SizedBox(
                  height: _rh,
                  width: _nameW,
                  child: _NameCell(b: b, onIcal: () => onIcal(b)),
                ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête : numéros de jour
                  Row(
                    children: [
                      for (final d in days)
                        SizedBox(
                          width: _cw,
                          height: 30,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat('E', 'fr')
                                      .format(d)
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 8.5, color: AppTheme.inkSoft),
                                ),
                                Text('${d.day}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: DateUtils.isSameDay(d, today)
                                            ? FontWeight.w800
                                            : FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final b in biens)
                    Row(
                      children: [
                        for (final d in days)
                          _DayCell(
                            width: _cw,
                            height: _rh,
                            day: d,
                            past: d.isBefore(today),
                            bien: b,
                            sejour: sejours.firstWhere(
                              (s) =>
                                  s.houseId == b.id &&
                                  !s.mensuel &&
                                  s.couvre(d),
                              orElse: () => _none,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final _none = CalSejour(
      houseId: '', clientNom: '', start: null, end: null, status: '', mensuel: false);
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.b, required this.onIcal});
  final CalBien b;
  final VoidCallback onIcal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 34,
              height: 34,
              child: b.image == null
                  ? Container(
                      color: AppTheme.panel,
                      child: const Icon(Icons.home_outlined,
                          size: 15, color: AppTheme.inkSoft))
                  : CachedNetworkImage(
                      imageUrl: b.image!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppTheme.panel),
                      errorWidget: (_, __, ___) =>
                          Container(color: AppTheme.panel),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(b.titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600)),
                InkWell(
                  onTap: onIcal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sync, size: 11, color: AppTheme.inkSoft),
                      const SizedBox(width: 3),
                      Text(
                        b.icalUrls.isEmpty
                            ? 'Lier Airbnb/Booking'
                            : '${b.icalUrls.length} calendrier(s)',
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.inkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.width,
    required this.height,
    required this.day,
    required this.past,
    required this.bien,
    required this.sejour,
  });
  final double width, height;
  final DateTime day;
  final bool past;
  final CalBien bien;
  final CalSejour sejour;

  @override
  Widget build(BuildContext context) {
    final hasSejour = sejour.houseId.isNotEmpty;
    final occupe = bien.occupeLe(day);

    Color bg;
    Color? fg;
    if (hasSejour) {
      bg = AppTheme.ink;
      fg = Colors.white;
    } else if (occupe) {
      bg = const Color(0xFFD6D6D6);
    } else {
      bg = Colors.white;
    }
    if (past) bg = bg == Colors.white ? const Color(0xFFFAFAFA) : bg;

    final cell = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      alignment: Alignment.center,
      child: hasSejour && sejour.clientNom.isNotEmpty
          ? Text(sejour.clientNom.substring(0, 1).toUpperCase(),
              style: TextStyle(
                  color: fg, fontSize: 10, fontWeight: FontWeight.w700))
          : null,
    );

    if (!hasSejour && !occupe) return cell;
    final msg = hasSejour
        ? '${sejour.clientNom} · ${sejour.status}'
            '${sejour.start != null ? '\n${DateFormat('d MMM', 'fr').format(sejour.start!)}'
                '${sejour.end != null ? ' → ${DateFormat('d MMM', 'fr').format(sejour.end!)}' : ''}' : ''}'
        : 'Bloqué (calendrier externe ou manuel)';
    return Tooltip(message: msg, child: cell);
  }
}

class _Mensuels extends StatelessWidget {
  const _Mensuels({required this.biens, required this.sejours});
  final List<CalBien> biens;
  final List<CalSejour> sejours;

  @override
  Widget build(BuildContext context) {
    if (biens.isEmpty) return const SizedBox.shrink();
    final today = DateTime.now();
    return AppCard(
      title: 'Locations mensuelles',
      child: Column(
        children: [
          for (final b in biens)
            Builder(builder: (_) {
              final s = sejours.where((s) =>
                  s.houseId == b.id && s.mensuel && s.couvre(today));
              final loue = s.isNotEmpty;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(b.titre,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    if (loue)
                      Text(s.first.clientNom,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.inkSoft)),
                    const SizedBox(width: 10),
                    StatusChip(loue ? 'Occupé' : 'Disponible',
                        tone: loue ? 'ink' : 'ok'),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
