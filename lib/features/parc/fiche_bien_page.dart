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

class FicheBienPage extends StatelessWidget {
  const FicheBienPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final ref = context.watch<AuthService>().partenaireRef;
    if (ref == null) {
      return const _Shell(child: EmptyState('Session en cours…'));
    }
    final repo = HouseRepository(ref);
    return StreamBuilder<House?>(
      stream: repo.one(id),
      builder: (context, snap) {
        if (snap.hasError) {
          return const _Shell(child: EmptyState('Impossible de charger ce bien.'));
        }
        if (!snap.hasData) {
          return const _Shell(child: SkeletonBox(height: 400));
        }
        final h = snap.data;
        if (h == null) {
          return const _Shell(child: EmptyState('Bien introuvable ou archivé.'));
        }
        return _Shell(child: _Content(house: h, repo: repo));
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
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
          child,
        ],
      ),
    );
  }
}

class _Content extends StatefulWidget {
  const _Content({required this.house, required this.repo});
  final House house;
  final HouseRepository repo;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  int _photo = 0;
  bool _busy = false;

  Future<void> _toggleActive() async {
    setState(() => _busy = true);
    try {
      await widget.repo.setActive(widget.house.id, !widget.house.active);
    } catch (_) {
      _snack('Action impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Archiver ce bien ?',
            style: GoogleFonts.mavenPro(fontWeight: FontWeight.w700)),
        content: Text(
          'Le bien sort de votre parc et de la marketplace. '
          'L\'historique des réservations est conservé. '
          'La restauration se fait via le support.',
          style: GoogleFonts.mavenPro(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.ink),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.archive(widget.house.id);
      if (mounted) context.go('/parc');
    } catch (_) {
      _snack('Archivage impossible. Réessayez.');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final h = widget.house;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final left = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Gallery(
            images: h.images,
            index: _photo,
            onSelect: (i) => setState(() => _photo = i),
          ),
          const SizedBox(height: 16),
          _InfoBlock(house: h),
        ],
      );
      final right = _ActionsPanel(
        house: h,
        busy: _busy,
        onToggle: _toggleActive,
        onArchive: _archive,
        onEdit: () => _snack(
            'La modification depuis le web arrive bientôt. Pour l\'instant, modifiez via l\'app Zappart.'),
      );
      return wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: right),
              ],
            )
          : Column(children: [left, const SizedBox(height: 16), right]);
    });
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery(
      {required this.images, required this.index, required this.onSelect});
  final List<String> images;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
            color: AppTheme.panel, borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined,
            size: 30, color: AppTheme.inkSoft),
      );
    }
    final i = index.clamp(0, images.length - 1);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: CachedNetworkImage(
              imageUrl: images[i],
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppTheme.panel),
              errorWidget: (_, __, ___) => Container(color: AppTheme.panel),
            ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, k) => GestureDetector(
                onTap: () => onSelect(k),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 78,
                    foregroundDecoration: k == i
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppTheme.ink, width: 2))
                        : null,
                    child: CachedNetworkImage(
                      imageUrl: images[k],
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppTheme.panel),
                      errorWidget: (_, __, ___) =>
                          Container(color: AppTheme.panel),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.house});
  final House house;

  static final _fmt = NumberFormat.decimalPattern('fr');

  @override
  Widget build(BuildContext context) {
    final h = house;
    final specs = <(IconData, String)>[
      if ((h.nbChambre ?? 0) > 0) (Icons.bed_outlined, '${h.nbChambre} ch.'),
      if ((h.nbSalon ?? 0) > 0)
        (Icons.weekend_outlined, '${h.nbSalon!.toInt()} salon'),
      if ((h.nbBain ?? 0) > 0)
        (Icons.bathtub_outlined, '${h.nbBain} SdB'),
      if ((h.surface ?? 0) > 0) (Icons.straighten, '${h.surface} m²'),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(h.titre,
                    style: GoogleFonts.mavenPro(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              StatusChip(h.badge.label, tone: h.badge.tone),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (h.locationType.isNotEmpty) h.locationType,
              if (h.type.isNotEmpty) h.type,
              if (h.zone.isNotEmpty) h.zone,
            ].join(' · '),
            style: GoogleFonts.mavenPro(fontSize: 12.5, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 12),
          Text(
            h.prixAffiche == null
                ? 'Prix non renseigné'
                : '${_fmt.format(h.prixAffiche!.round())} FCFA ${h.uniteLabel}',
            style: GoogleFonts.mavenPro(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          if (h.locationType == 'Mensuel' &&
              ((h.caution ?? 0) > 0 || (h.comission ?? 0) > 0)) ...[
            const SizedBox(height: 4),
            Text(
              [
                if ((h.caution ?? 0) > 0)
                  'Caution ${_fmt.format(h.caution!.round())}'
                      '${h.cautionMois != null ? ' (${h.cautionMois} mois)' : ''}',
                if ((h.comission ?? 0) > 0)
                  'Commission ${_fmt.format(h.comission!.round())}',
              ].join(' · '),
              style:
                  GoogleFonts.mavenPro(fontSize: 12, color: AppTheme.inkSoft),
            ),
          ],
          if (h.rejetee && h.motifRejet.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9ECEA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: Color(0xFF8A4033)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Annonce rejetée',
                            style: GoogleFonts.mavenPro(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF8A4033))),
                        Text(h.motifRejet,
                            style: GoogleFonts.mavenPro(
                                fontSize: 12,
                                color: const Color(0xFF8A4033))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (specs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final (ic, label) in specs)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.panel,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(ic, size: 14, color: AppTheme.inkSoft),
                      const SizedBox(width: 6),
                      Text(label,
                          style: GoogleFonts.mavenPro(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ],
            ),
          ],
          if (h.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Description',
                style: GoogleFonts.mavenPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft)),
            const SizedBox(height: 4),
            Text(h.description,
                style: GoogleFonts.mavenPro(fontSize: 13, height: 1.5)),
          ],
          if (h.comodites.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Commodités',
                style: GoogleFonts.mavenPro(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in h.comodites)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(c,
                        style: GoogleFonts.mavenPro(fontSize: 11.5)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel({
    required this.house,
    required this.busy,
    required this.onToggle,
    required this.onArchive,
    required this.onEdit,
  });
  final House house;
  final bool busy;
  final VoidCallback onToggle, onArchive, onEdit;

  @override
  Widget build(BuildContext context) {
    final h = house;
    final canToggle = h.statutValidation == 'validee';
    return Column(
      children: [
        AppCard(
          title: 'Diffusion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.enLigne
                              ? 'Publié sur Zappart'
                              : canToggle
                                  ? 'Hors ligne'
                                  : 'Pas encore publiable',
                          style: GoogleFonts.mavenPro(
                              fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          canToggle
                              ? (h.enLigne
                                  ? 'Visible par les clients dans l\'app'
                                  : 'Invisible — repassez en ligne quand vous voulez')
                              : 'En attente de validation par l\'équipe Zappart',
                          style: GoogleFonts.mavenPro(
                              fontSize: 11.5, color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: h.enLigne,
                    onChanged: canToggle && !busy ? (_) => onToggle() : null,
                    activeTrackColor: AppTheme.ink,
                  ),
                ],
              ),
              if (h.boostActif) ...[
                const SizedBox(height: 10),
                const StatusChip('Boost actif', tone: 'ink'),
              ],
              if (h.immeubleRefId != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.apartment_rounded,
                      size: 15, color: AppTheme.inkSoft),
                  const SizedBox(width: 6),
                  Text('Rattaché à un immeuble',
                      style: GoogleFonts.mavenPro(
                          fontSize: 12, color: AppTheme.inkSoft)),
                ]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          title: 'Actions',
          child: Column(
            children: [
              _ActionBtn(
                icon: Icons.edit_outlined,
                label: 'Modifier l\'annonce',
                onTap: onEdit,
              ),
              const SizedBox(height: 8),
              _ActionBtn(
                icon: Icons.inventory_2_outlined,
                label: 'Archiver le bien',
                danger: true,
                onTap: busy ? null : onArchive,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = danger ? const Color(0xFF8A4033) : AppTheme.ink;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: c),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label,
              style: GoogleFonts.mavenPro(
                  fontSize: 13, fontWeight: FontWeight.w600, color: c)),
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          side: BorderSide(
              color: danger ? const Color(0xFFE7D3CF) : AppTheme.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
