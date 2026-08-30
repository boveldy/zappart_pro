import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/annonce_catalog.dart';
import '../../data/annonce_form.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Wizard web d'ajout d'annonce (Zappart Pro). 7 écrans, navigation par boutons.
/// La fiche part en `statut_validation: 'en_attente'` → file de validation admin.
class NouvelleAnnoncePage extends StatefulWidget {
  const NouvelleAnnoncePage({super.key});

  @override
  State<NouvelleAnnoncePage> createState() => _NouvelleAnnoncePageState();
}

class _NouvelleAnnoncePageState extends State<NouvelleAnnoncePage> {
  AnnonceForm? _form;
  int _step = 0;

  static const _titres = [
    'Localisation',
    'Caractéristiques',
    'Commodités',
    'Photos',
    'Concierge',
    'Prix & description',
    'Récapitulatif',
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null || !auth.estHote) {
      return const PageScaffold(
        title: 'Ajouter une annonce',
        child: EmptyState(
          'Votre compte n\'est pas un compte hôte — pas de parc immobilier.',
        ),
      );
    }
    _form ??= AnnonceForm(ref);

    return ChangeNotifierProvider<AnnonceForm>.value(
      value: _form!,
      child: Consumer<AnnonceForm>(
        builder: (context, form, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopBar(step: _step, total: _titres.length),
                    const SizedBox(height: 6),
                    Text(_titres[_step], style: AppTheme.h1),
                    const SizedBox(height: 4),
                    Text('Étape ${_step + 1} sur ${_titres.length}',
                        style: AppTheme.label),
                    const SizedBox(height: 22),
                    _body(form),
                    const SizedBox(height: 24),
                    _Footer(
                      step: _step,
                      total: _titres.length,
                      canNext: form.okForStep(_step),
                      submitting: form.submitting,
                      onBack: () {
                        if (_step == 0) {
                          context.go('/parc');
                        } else {
                          setState(() => _step--);
                        }
                      },
                      onNext: () => setState(() => _step++),
                      onSubmit: () => _submit(form),
                    ),
                    if (form.erreur != null) ...[
                      const SizedBox(height: 12),
                      Text(form.erreur!,
                          style: const TextStyle(
                              color: AppTheme.danger, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(AnnonceForm f) => switch (_step) {
        0 => _StepLocalisation(f),
        1 => _StepCaracteristiques(f),
        2 => _StepCommodites(f),
        3 => _StepPhotos(f),
        4 => _StepConcierge(f),
        5 => _StepPrix(f),
        _ => _StepRecap(f),
      };

  Future<void> _submit(AnnonceForm f) async {
    final ok = await f.submit();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Annonce envoyée pour validation. Elle sera en ligne dès son approbation.'),
      ));
      context.go('/parc');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Barre de progression + pied de page
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.step, required this.total});
  final int step, total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? AppTheme.ink : AppTheme.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.step,
    required this.total,
    required this.canNext,
    required this.submitting,
    required this.onBack,
    required this.onNext,
    required this.onSubmit,
  });
  final int step, total;
  final bool canNext, submitting;
  final VoidCallback onBack, onNext, onSubmit;

  @override
  Widget build(BuildContext context) {
    final last = step == total - 1;
    return Row(
      children: [
        TextButton(
          onPressed: submitting ? null : onBack,
          child: Text(step == 0 ? 'Annuler' : 'Retour',
              style: const TextStyle(color: AppTheme.inkSoft)),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: submitting || (!last && !canNext) || (last && !canNext)
              ? null
              : (last ? onSubmit : onNext),
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(last ? 'Soumettre pour validation' : 'Suivant'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Petits composants de saisie
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text, {this.hint});
  final String text;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(hint!,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.inkSoft)),
              ),
          ],
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.initial,
    required this.onChanged,
    this.hintText,
    this.keyboardType,
    this.maxLines = 1,
  });
  final String initial;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initial,
      onChanged: onChanged,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(hintText: hintText),
    );
  }
}

class _ChoiceChips extends StatelessWidget {
  const _ChoiceChips({
    required this.options,
    required this.selected,
    required this.onTap,
    this.multi = false,
  });
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          InkWell(
            onTap: () => onTap(o),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected.contains(o) ? AppTheme.ink : Colors.white,
                border: Border.all(
                    color: selected.contains(o)
                        ? AppTheme.ink
                        : AppTheme.line),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(o,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selected.contains(o)
                          ? Colors.white
                          : AppTheme.ink)),
            ),
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 20,
    this.enabled = true,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min, max;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Row(
        children: [
          Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13.5))),
          _rnd(Icons.remove,
              enabled && value > min ? () => onChanged(value - 1) : null),
          SizedBox(
            width: 38,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          _rnd(Icons.add,
              enabled && value < max ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }

  Widget _rnd(IconData i, VoidCallback? onTap) => Material(
        color: Colors.white,
        shape: CircleBorder(
            side: BorderSide(
                color: onTap == null ? AppTheme.line : AppTheme.ink)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(i,
                size: 16,
                color: onTap == null ? AppTheme.line : AppTheme.ink),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Étape 1 — Localisation
// ─────────────────────────────────────────────────────────────────────────────

class _StepLocalisation extends StatelessWidget {
  const _StepLocalisation(this.f);
  final AnnonceForm f;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Type de location'),
          _ChoiceChips(
            options: const ['Journalier', 'Mensuel'],
            selected: {f.locationtype},
            onTap: (v) {
              f.locationtype = v;
              f.touch();
            },
          ),
          const SizedBox(height: 18),
          const _Label('Type de logement'),
          _ChoiceChips(
            options: kTypesLogement,
            selected: {f.type},
            onTap: (v) {
              f.type = v;
              f.appliquerContraintesType();
              f.touch();
            },
          ),
          const SizedBox(height: 18),
          const _Label('Quartier'),
          DropdownButtonFormField<String>(
            value: f.quartier.isEmpty ? null : f.quartier,
            isExpanded: true,
            hint: const Text('Choisir un quartier'),
            items: [
              for (final q in kQuartiers)
                DropdownMenuItem(value: q.key, child: Text(q.label)),
            ],
            onChanged: (v) {
              f.quartier = v ?? '';
              f.touch();
            },
          ),
          const SizedBox(height: 14),
          const _Label('Cité / résidence'),
          _Field(
            initial: f.cite,
            hintText: 'Ex. Cité Keur Gorgui',
            onChanged: (v) {
              f.cite = v;
              f.touch();
            },
          ),
          const SizedBox(height: 14),
          const _Label('Zone / sous-quartier', hint: 'Optionnel — ex. Liberté 6'),
          _Field(
            initial: f.zone,
            onChanged: (v) {
              f.zone = v;
              f.touch();
            },
          ),
          const SizedBox(height: 14),
          const _Label('Adresse / point de repère'),
          _Field(
            initial: f.adresse,
            hintText: 'Rue, immeuble, repère connu',
            onChanged: (v) {
              f.adresse = v;
              f.touch();
            },
          ),
          const SizedBox(height: 14),
          const _Label('Étage', hint: 'Optionnel'),
          _ChoiceChips(
            options: kEmplacements,
            selected: {f.emplacement},
            onTap: (v) {
              f.emplacement = f.emplacement == v ? '' : v;
              f.touch();
            },
          ),
          const SizedBox(height: 18),
          const _Label('Position GPS',
              hint:
                  'Collez le lien Google Maps du bien (partage → copier le lien). Obligatoire : la visite et le déménagement offert en dépendent.'),
          _MapsLinkField(f),
        ],
      ),
    );
  }
}

class _MapsLinkField extends StatefulWidget {
  const _MapsLinkField(this.f);
  final AnnonceForm f;
  @override
  State<_MapsLinkField> createState() => _MapsLinkFieldState();
}

class _MapsLinkFieldState extends State<_MapsLinkField> {
  final _ctrl = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final r = AnnonceForm.parseLatLng(_ctrl.text);
    setState(() {
      if (r == null) {
        _err = 'Lien non reconnu — collez un lien contenant les coordonnées.';
      } else {
        _err = null;
        widget.f.geoLat = r.$1;
        widget.f.geoLng = r.$2;
      }
    });
    widget.f.touch();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                    hintText: 'https://maps.app.goo.gl/…  ou  lat, lng'),
                onSubmitted: (_) => _apply(),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _apply,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.ink,
                side: const BorderSide(color: AppTheme.ink),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Placer'),
            ),
          ],
        ),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_err!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        if (f.hasPosition)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 16, color: AppTheme.success),
                const SizedBox(width: 6),
                Text(
                    'Position enregistrée : '
                    '${f.geoLat!.toStringAsFixed(5)}, ${f.geoLng!.toStringAsFixed(5)}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppTheme.inkSoft)),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Étape 2 — Caractéristiques
// ─────────────────────────────────────────────────────────────────────────────

class _StepCaracteristiques extends StatelessWidget {
  const _StepCaracteristiques(this.f);
  final AnnonceForm f;

  @override
  Widget build(BuildContext context) {
    final half = List.generate(48, (i) => i * 30);
    String hm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}h${(m % 60).toString().padLeft(2, '0')}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Stepper(
            label: 'Chambres',
            value: f.nbchambre,
            min: 1,
            enabled: !f.chambreFigee,
            onChanged: (v) {
              f.nbchambre = v;
              f.touch();
            },
          ),
          const Divider(height: 22),
          _Stepper(
            label: 'Salons',
            value: f.nbsalon,
            enabled: f.autoriseSalon,
            onChanged: (v) {
              f.nbsalon = v;
              f.touch();
            },
          ),
          const Divider(height: 22),
          _Stepper(
            label: 'Salles de bain',
            value: f.nbbain,
            min: 1,
            onChanged: (v) {
              f.nbbain = v;
              f.touch();
            },
          ),
          const Divider(height: 22),
          _Stepper(
            label: 'Cuisines',
            value: f.nbcuisine,
            enabled: f.autoriseCuisine,
            onChanged: (v) {
              f.nbcuisine = v;
              f.touch();
            },
          ),
          const Divider(height: 22),
          Row(children: [
            const Expanded(
                child: Text('Nombre de pièces (chambres + salons)',
                    style: TextStyle(fontSize: 13.5, color: AppTheme.inkSoft))),
            Text('${f.nbpiece}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 18),
          const _Label('Surface (m²)', hint: 'Optionnel'),
          SizedBox(
            width: 160,
            child: _Field(
              initial: f.surface == 0 ? '' : '${f.surface}',
              keyboardType: TextInputType.number,
              hintText: 'm²',
              onChanged: (v) {
                f.surface = int.tryParse(v.trim()) ?? 0;
                f.touch();
              },
            ),
          ),
          if (f.isJournalier) ...[
            const SizedBox(height: 18),
            _Stepper(
              label: 'Capacité (voyageurs)',
              value: f.capacite,
              min: 1,
              max: 30,
              onChanged: (v) {
                f.capacite = v;
                f.touch();
              },
            ),
            const SizedBox(height: 18),
            const _Label('Numéro du bien',
                hint: 'Référence interne montrée au client et au concierge'),
            SizedBox(
              width: 160,
              child: _Field(
                initial: f.numbien == 0 ? '' : '${f.numbien}',
                keyboardType: TextInputType.number,
                hintText: 'Ex. 12',
                onChanged: (v) {
                  f.numbien = int.tryParse(v.trim()) ?? 0;
                  f.touch();
                },
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('Arrivée'),
                    DropdownButtonFormField<int>(
                      value: f.heureArriveeMin,
                      isExpanded: true,
                      items: [
                        for (final m in half)
                          DropdownMenuItem(value: m, child: Text(hm(m))),
                      ],
                      onChanged: (v) {
                        f.heureArriveeMin = v ?? f.heureArriveeMin;
                        f.touch();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('Départ'),
                    DropdownButtonFormField<int>(
                      value: f.heureDepartMin,
                      isExpanded: true,
                      items: [
                        for (final m in half)
                          DropdownMenuItem(value: m, child: Text(hm(m))),
                      ],
                      onChanged: (v) {
                        f.heureDepartMin = v ?? f.heureDepartMin;
                        f.touch();
                      },
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            const _Label('Règles de la maison', hint: 'Au moins une'),
            _ChoiceChips(
              options: kReglesMaison,
              selected: f.regles,
              multi: true,
              onTap: (v) {
                f.regles.contains(v) ? f.regles.remove(v) : f.regles.add(v);
                f.touch();
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Étape 3 — Commodités
// ─────────────────────────────────────────────────────────────────────────────

class _StepCommodites extends StatelessWidget {
  const _StepCommodites(this.f);
  final AnnonceForm f;

  @override
  Widget build(BuildContext context) {
    final groupes = comoditesGroupes(journalier: f.isJournalier);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in groupes.entries) ...[
            _Label(g.key),
            _ChoiceChips(
              options: g.value,
              selected: f.comodites,
              multi: true,
              onTap: (v) {
                f.comodites.contains(v)
                    ? f.comodites.remove(v)
                    : f.comodites.add(v);
                f.touch();
              },
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Étape 4 — Photos
// ─────────────────────────────────────────────────────────────────────────────

class _StepPhotos extends StatefulWidget {
  const _StepPhotos(this.f);
  final AnnonceForm f;
  @override
  State<_StepPhotos> createState() => _StepPhotosState();
}

class _StepPhotosState extends State<_StepPhotos> {
  bool _loading = false;

  Future<void> _pick() async {
    setState(() => _loading = true);
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 82);
      for (final x in picked) {
        final bytes = await x.readAsBytes();
        widget.f.photos.add(PickedPhoto(
          bytes: bytes,
          name: x.name,
          mime: x.mimeType ??
              (x.name.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : 'image/jpeg'),
        ));
      }
      widget.f.touch();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Photos du logement',
              hint:
                  'Minimum 3. La première photo est la couverture. Max 10 Mo par image.'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < f.photos.length; i++)
                _Thumb(
                  photo: f.photos[i],
                  cover: i == 0,
                  onRemove: () {
                    f.photos.removeAt(i);
                    f.touch();
                  },
                  onCover: i == 0
                      ? null
                      : () {
                          final p = f.photos.removeAt(i);
                          f.photos.insert(0, p);
                          f.touch();
                        },
                ),
              InkWell(
                onTap: _loading ? null : _pick,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined,
                                  color: AppTheme.inkSoft),
                              SizedBox(height: 6),
                              Text('Ajouter',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.inkSoft)),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (f.photos.any((p) => p.tropLourde))
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Une photo dépasse 10 Mo — retirez-la ou compressez-la.',
                  style: TextStyle(color: AppTheme.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.photo,
    required this.cover,
    required this.onRemove,
    required this.onCover,
  });
  final PickedPhoto photo;
  final bool cover;
  final VoidCallback onRemove;
  final VoidCallback? onCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(photo.bytes, fit: BoxFit.cover),
          ),
          if (photo.tropLourde)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('> 10 Mo',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: cover
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppTheme.ink,
                        borderRadius: BorderRadius.circular(999)),
                    child: const Text('Couverture',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  )
                : InkWell(
                    onTap: onCover,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppTheme.line)),
                      child: const Text('Définir couverture',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Étape 5 — Concierge
// ─────────────────────────────────────────────────────────────────────────────

class _StepConcierge extends StatelessWidget {
  const _StepConcierge(this.f);
  final AnnonceForm f;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Contact sur place',
              hint:
                  'Nom et téléphone remis au client après paiement (gardien, gérant, vous-même).'),
          const SizedBox(height: 6),
          const _Label('Nom'),
          _Field(
            initial: f.conciergeNom,
            hintText: 'Ex. M. Diallo',
            onChanged: (v) {
              f.conciergeNom = v;
              f.touch();
            },
          ),
          const SizedBox(height: 14),
          const _Label('Téléphone'),
          _Field(
            initial: f.conciergeNum,
            keyboardType: TextInputType.phone,
            hintText: '+221 77 000 00 00',
            onChanged: (v) {
              f.conciergeNum = v;
              f.touch();
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Étape 6 — Prix & description
// ─────────────────────────────────────────────────────────────────────────────

class _StepPrix extends StatelessWidget {
  const _StepPrix(this.f);
  final AnnonceForm f;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern('fr');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(f.isJournalier ? 'Prix par nuit (FCFA)' : 'Loyer mensuel (FCFA)',
              hint:
                  'Ce que vous touchez. Zappart ajoute sa marge par-dessus, sans toucher à ce montant.'),
          SizedBox(
            width: 220,
            child: _Field(
              initial: f.prix == 0 ? '' : f.prix.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              hintText: 'Ex. 150000',
              onChanged: (v) {
                f.prix = double.tryParse(v.trim().replaceAll(' ', '')) ?? 0;
                f.touch();
              },
            ),
          ),
          if (!f.isJournalier) ...[
            const SizedBox(height: 18),
            const _Label('Caution (nombre de mois de loyer)'),
            _ChoiceChips(
              options: const ['1', '2', '3'],
              selected: {'${f.cautionMois}'},
              onTap: (v) {
                f.cautionMois = int.parse(v);
                f.touch();
              },
            ),
            if (f.prix > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'Caution due par le locataire : ${fmt.format(f.cautionCalculee.round())} FCFA',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppTheme.inkSoft)),
              ),
            const SizedBox(height: 18),
            const _Label('Charges (eau / électricité)'),
            _ChoiceChips(
              options: kChargesOptions.values.toList(),
              selected: {kChargesOptions[f.chargesIncluses] ?? ''},
              onTap: (label) {
                f.chargesIncluses = kChargesOptions.entries
                    .firstWhere((e) => e.value == label)
                    .key;
                f.touch();
              },
            ),
            if (f.chargesIncluses == 'partiel') ...[
              const SizedBox(height: 10),
              _Field(
                initial: f.chargesPrecision,
                hintText: 'Ce qui est inclus / à part',
                onChanged: (v) {
                  f.chargesPrecision = v;
                  f.touch();
                },
              ),
            ],
            const SizedBox(height: 18),
            const _Label('Durée d\'engagement minimale'),
            _ChoiceChips(
              options: [for (final m in kBailOptions) '$m mois'],
              selected: {'${f.bailMinMois} mois'},
              onTap: (v) {
                f.bailMinMois = int.parse(v.split(' ').first);
                f.touch();
              },
            ),
          ],
          if (f.isJournalier) ...[
            const SizedBox(height: 18),
            Row(children: [
              Switch(
                value: f.journeeActive,
                activeColor: AppTheme.ink,
                onChanged: (v) {
                  f.journeeActive = v;
                  f.touch();
                },
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Proposer aussi la location à la journée (day-use)',
                    style: TextStyle(fontSize: 13)),
              ),
            ]),
            if (f.journeeActive)
              SizedBox(
                width: 220,
                child: _Field(
                  initial:
                      f.prixJournee == 0 ? '' : f.prixJournee.toStringAsFixed(0),
                  keyboardType: TextInputType.number,
                  hintText: 'Prix journée (FCFA)',
                  onChanged: (v) {
                    f.prixJournee =
                        double.tryParse(v.trim().replaceAll(' ', '')) ?? 0;
                    f.touch();
                  },
                ),
              ),
          ],
          const SizedBox(height: 20),
          const _Label('Description', hint: 'Au moins 20 caractères'),
          _Field(
            initial: f.description,
            maxLines: 5,
            hintText:
                'Décrivez le logement, le quartier, ce qui le rend agréable…',
            onChanged: (v) {
              f.description = v;
              f.touch();
            },
          ),
          const SizedBox(height: 14),
          const _Label('Accroche', hint: 'Optionnel — une phrase courte'),
          _Field(
            initial: f.accroche,
            hintText: 'Ex. Appartement lumineux à 5 min de la plage',
            onChanged: (v) {
              f.accroche = v;
              f.touch();
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Étape 7 — Récapitulatif
// ─────────────────────────────────────────────────────────────────────────────

class _StepRecap extends StatefulWidget {
  const _StepRecap(this.f);
  final AnnonceForm f;
  @override
  State<_StepRecap> createState() => _StepRecapState();
}

class _StepRecapState extends State<_StepRecap> {
  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final fmt = NumberFormat.decimalPattern('fr');
    final quartierLabel = kQuartiers
        .firstWhere((q) => q.key == f.quartier,
            orElse: () => (label: f.quartier, key: f.quartier))
        .label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (f.photos.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.memory(f.photos.first.bytes,
                        fit: BoxFit.cover),
                  ),
                ),
              const SizedBox(height: 14),
              _row('Type', '${f.type} · ${f.locationtype}'),
              _row('Lieu', '$quartierLabel — ${f.cite}'),
              if (f.emplacement.isNotEmpty) _row('Étage', f.emplacement),
              _row('Pièces',
                  '${f.nbchambre} ch · ${f.nbsalon} sal · ${f.nbbain} sdb'),
              if (f.surface > 0) _row('Surface', '${f.surface} m²'),
              if (f.isJournalier) _row('Capacité', '${f.capacite} voyageurs'),
              if (f.isJournalier) _row('N° du bien', '#${f.numbien}'),
              _row(
                  f.isJournalier ? 'Prix / nuit' : 'Loyer',
                  '${fmt.format(f.prix.round())} FCFA'),
              if (!f.isJournalier)
                _row('Caution',
                    '${fmt.format(f.cautionCalculee.round())} FCFA (${f.cautionMois} mois)'),
              if (f.isJournalier && f.journeeActive)
                _row('Prix journée', '${fmt.format(f.prixJournee.round())} FCFA'),
              _row('Photos', '${f.photos.length}'),
              _row('Commodités', '${f.comodites.length} cochées'),
              _row('Concierge', '${f.conciergeNom} · ${f.conciergeNum}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.line),
          ),
          child: const Text(
            'En soumettant, l\'annonce part en validation. Un membre de l\'équipe '
            'Zappart la vérifie (photos, prix, cohérence) puis la met en ligne. '
            'Vous serez notifié. Les marges et commissions Zappart sont ajoutées '
            'à la validation.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
