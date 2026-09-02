import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/map_picker.dart';
import '../../data/annonce_catalog.dart';
import '../../data/annonce_form.dart';
import '../../data/immeuble.dart';
import '../../theme/app_theme.dart';

/// Feuille de sélection d'immeuble : liste les immeubles de l'hôte + « Créer un
/// immeuble ». Retourne l'[Immeuble] choisi, ou `null` si l'hôte ferme.
Future<Immeuble?> pickImmeuble(
    BuildContext context, ImmeubleRepository repo) {
  return showModalBottomSheet<Immeuble>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _PickerSheet(repo: repo),
  );
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.repo});
  final ImmeubleRepository repo;

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
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vos immeubles',
                style: GoogleFonts.mavenPro(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Rattachez ce logement à un immeuble pour ne plus ressaisir '
              'l\'adresse, la position et le concierge.',
              style: GoogleFonts.mavenPro(
                  fontSize: 12.5, height: 1.4, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: StreamBuilder<List<Immeuble>>(
                  stream: repo.mine(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Text('Impossible de charger vos immeubles.',
                          style: GoogleFonts.mavenPro(
                              fontSize: 13.5, color: AppTheme.inkSoft));
                    }
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.ink)),
                      );
                    }
                    final ims = snap.data!;
                    if (ims.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Aucun immeuble enregistré.',
                            style: GoogleFonts.mavenPro(
                                fontSize: 13.5, color: AppTheme.inkSoft)),
                      );
                    }
                    return Column(
                      children: [
                        for (final im in ims)
                          _Tile(
                            immeuble: im,
                            onTap: () => Navigator.pop(context, im),
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
                onPressed: () async {
                  final im = await showImmeubleForm(context, repo);
                  if (im != null && context.mounted) {
                    Navigator.pop(context, im);
                  }
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Créer un immeuble'),
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
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.immeuble, required this.onTap});
  final Immeuble immeuble;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.apartment_rounded, color: AppTheme.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(immeuble.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.mavenPro(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                      if (immeuble.sousTitre.isNotEmpty)
                        Text(immeuble.sousTitre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.mavenPro(
                                fontSize: 12, color: AppTheme.inkSoft)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.inkSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Formulaire de création / modification d'immeuble ───────────────────────

/// Ouvre le formulaire d'immeuble (création si [existant] est nul, sinon
/// modification). Retourne l'[Immeuble] enregistré, ou `null` si annulé.
Future<Immeuble?> showImmeubleForm(
  BuildContext context,
  ImmeubleRepository repo, {
  Immeuble? existant,
}) {
  return showDialog<Immeuble>(
    context: context,
    builder: (_) => _ImmeubleFormDialog(repo: repo, existant: existant),
  );
}

class _ImmeubleFormDialog extends StatefulWidget {
  const _ImmeubleFormDialog({required this.repo, this.existant});
  final ImmeubleRepository repo;
  final Immeuble? existant;

  @override
  State<_ImmeubleFormDialog> createState() => _ImmeubleFormDialogState();
}

class _ImmeubleFormDialogState extends State<_ImmeubleFormDialog> {
  late final _nom = TextEditingController(text: widget.existant?.nom ?? '');
  late final _cite = TextEditingController(text: widget.existant?.cite ?? '');
  late final _adresse =
      TextEditingController(text: widget.existant?.localisation ?? '');
  late final _conciergeNom =
      TextEditingController(text: widget.existant?.conciergenom ?? '');
  late final _conciergeNum =
      TextEditingController(text: widget.existant?.conciergenum ?? '');
  late String _quartier = widget.existant?.quartier ?? '';
  late String _zone = widget.existant?.zone ?? '';
  double? _lat;
  double? _lng;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final geo = widget.existant?.geolocalisation;
    if (geo != null) {
      final c = AnnonceForm.parseLatLng(geo);
      _lat = c?.$1;
      _lng = c?.$2;
    }
  }

  @override
  void dispose() {
    _nom.dispose();
    _cite.dispose();
    _adresse.dispose();
    _conciergeNom.dispose();
    _conciergeNum.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nom.text.trim().isNotEmpty &&
      _quartier.isNotEmpty &&
      (!quartierADesZones(_quartier) || _zone.isNotEmpty) &&
      _cite.text.trim().isNotEmpty &&
      _adresse.text.trim().isNotEmpty &&
      _lat != null &&
      _lng != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final String id;
      if (widget.existant == null) {
        final ref = await widget.repo.create(
          nom: _nom.text.trim(),
          quartier: _quartier.trim(),
          zone: _zone,
          cite: _cite.text.trim(),
          localisation: _adresse.text.trim(),
          geolocalisation: AnnonceForm.mapsLink(_lat!, _lng!),
          conciergenom: _conciergeNom.text.trim(),
          conciergenum: _conciergeNum.text.trim(),
          conciergephoto: '',
        );
        id = ref.id;
      } else {
        id = widget.existant!.id;
        await widget.repo.update(
          id,
          nom: _nom.text.trim(),
          quartier: _quartier.trim(),
          zone: _zone,
          cite: _cite.text.trim(),
          localisation: _adresse.text.trim(),
          geolocalisation: AnnonceForm.mapsLink(_lat!, _lng!),
          conciergenom: _conciergeNom.text.trim(),
          conciergenum: _conciergeNum.text.trim(),
        );
      }
      final im = await widget.repo.one(id);
      if (mounted) Navigator.pop(context, im);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Enregistrement impossible. Réessayez.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
          widget.existant == null ? 'Nouvel immeuble' : 'Modifier l\'immeuble',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Les infos communes au bâtiment, saisies une seule fois. Chaque '
                'logement rattaché les reprend automatiquement.',
                style: GoogleFonts.mavenPro(
                    fontSize: 12, color: AppTheme.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 14),
              _lbl('Nom de l\'immeuble'),
              TextField(
                controller: _nom,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Ex. Résidence Fatou'),
              ),
              const SizedBox(height: 12),
              _lbl('Quartier'),
              DropdownButtonFormField<String>(
                initialValue: _quartier.isEmpty ? null : _quartier,
                isExpanded: true,
                hint: const Text('Choisir un quartier'),
                items: [
                  for (final q in kQuartiers)
                    DropdownMenuItem(value: q.key, child: Text(q.label)),
                ],
                onChanged: (v) => setState(() {
                  _quartier = v ?? '';
                  _zone = '';
                }),
              ),
              if (quartierADesZones(_quartier)) ...[
                const SizedBox(height: 12),
                _lbl('Zone / sous-quartier'),
                DropdownButtonFormField<String>(
                  initialValue: _zone.isEmpty ? null : _zone,
                  isExpanded: true,
                  hint: const Text('Choisir la zone'),
                  items: [
                    for (final z in zonesDuQuartier(_quartier))
                      DropdownMenuItem(value: z.label, child: Text(z.label)),
                  ],
                  onChanged: (v) => setState(() => _zone = v ?? ''),
                ),
              ],
              const SizedBox(height: 12),
              _lbl('Cité / résidence'),
              TextField(
                controller: _cite,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(hintText: 'Ex. Cité Keur Gorgui'),
              ),
              const SizedBox(height: 12),
              _lbl('Adresse / repère'),
              TextField(
                controller: _adresse,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    hintText: 'Rue, immeuble, repère connu'),
              ),
              const SizedBox(height: 14),
              _lbl('Position GPS (obligatoire)'),
              MapPicker(
                lat: _lat,
                lng: _lng,
                quartierKey: _quartier,
                onChanged: (lat, lng) => setState(() {
                  _lat = lat;
                  _lng = lng;
                }),
              ),
              const SizedBox(height: 14),
              _lbl('Concierge (optionnel)'),
              TextField(
                controller: _conciergeNom,
                decoration: const InputDecoration(hintText: 'Nom du concierge'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _conciergeNum,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(hintText: 'Téléphone du concierge'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: (_canSave && !_saving) ? _save : null,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(widget.existant == null
                  ? 'Créer l\'immeuble'
                  : 'Enregistrer'),
        ),
      ],
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700)),
      );
}

// ── Carte lecture seule affichée dans le wizard quand un immeuble est lié ──

class ImmeubleReadonlyCard extends StatelessWidget {
  const ImmeubleReadonlyCard({
    super.key,
    required this.nom,
    required this.detail,
    required this.onDetach,
  });
  final String nom;
  final String detail;
  final VoidCallback onDetach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_rounded, color: AppTheme.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nom,
                    style: GoogleFonts.mavenPro(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                if (detail.isNotEmpty)
                  Text(detail,
                      style: GoogleFonts.mavenPro(
                          fontSize: 12, color: AppTheme.inkSoft)),
                const SizedBox(height: 2),
                Text('Quartier, adresse, position et concierge hérités.',
                    style: GoogleFonts.mavenPro(
                        fontSize: 11, color: AppTheme.inkSoft)),
              ],
            ),
          ),
          TextButton(
            onPressed: onDetach,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8A4033),
              textStyle: GoogleFonts.mavenPro(
                  fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            child: const Text('Détacher'),
          ),
        ],
      ),
    );
  }
}
