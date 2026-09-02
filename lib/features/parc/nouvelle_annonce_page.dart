import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/services/ai_description.dart';
import '../../core/ui.dart';
import '../../core/widgets/map_picker.dart';
import '../../data/annonce_catalog.dart';
import '../../data/annonce_form.dart';
import '../../data/house.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Wizard web d'ajout d'annonce (Zappart Pro). 7 écrans, navigation par boutons.
/// La fiche part en `statut_validation: 'en_attente'` → file de validation admin.
///
/// [completerId] non nul → mode « Compléter et publier » : on charge un bien de
/// gestion « privé » et on le complète (photos, description…) pour le mettre sur
/// la marketplace, sans changer de document (le lien `bail.house_ref` est
/// préservé).
class NouvelleAnnoncePage extends StatefulWidget {
  const NouvelleAnnoncePage({super.key, this.completerId, this.modifierId});

  /// Bien privé de gérance à compléter puis publier.
  final String? completerId;

  /// Annonce existante à modifier (repart en validation après enregistrement).
  final String? modifierId;

  @override
  State<NouvelleAnnoncePage> createState() => _NouvelleAnnoncePageState();
}

class _NouvelleAnnoncePageState extends State<NouvelleAnnoncePage> {
  AnnonceForm? _form;
  bool _seeding = false;
  int _step = 0;

  String? get _sourceId => widget.modifierId ?? widget.completerId;

  @override
  void initState() {
    super.initState();
    if (_sourceId != null) {
      _seeding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _seed());
    }
  }

  Future<void> _seed() async {
    final ref = context.read<AuthService>().partenaireRef;
    if (ref == null) {
      if (mounted) setState(() => _seeding = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('house')
          .doc(_sourceId)
          .get();
      final f = AnnonceForm(ref);
      if (snap.exists) {
        if (widget.modifierId != null) {
          f.loadFromDoc(snap);
        } else {
          f.seedFromHouse(House.fromDoc(snap));
        }
      }
      if (mounted) {
        setState(() {
          _form = f;
          _seeding = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _seeding = false);
    }
  }

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
          "Votre compte n'est pas un compte hôte — pas de parc immobilier.",
        ),
      );
    }
    final titrePage = widget.modifierId != null
        ? 'Modifier l\'annonce'
        : 'Compléter et publier';
    if (_seeding) {
      return PageScaffold(
        title: titrePage,
        child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink)),
      );
    }
    if (_sourceId == null) _form ??= AnnonceForm(ref);
    if (_form == null) {
      return PageScaffold(
        title: titrePage,
        child: const EmptyState('Bien introuvable.'),
      );
    }
    final modifier = _form!.editionComplete;
    final completer = _form!.editRef != null && !modifier;

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
                    if (completer || modifier) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF3FB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFD5E1F2)),
                        ),
                        child: Text(
                          modifier
                              ? 'Vous modifiez une annonce existante. À l\'enregistrement, '
                                  'elle repasse en validation par l\'équipe Zappart et sort '
                                  'du marketplace le temps de la revue.'
                              : 'Vous publiez un bien de votre gérance sur la marketplace. '
                                  'Le bail en cours reste lié à ce bien. Après validation par '
                                  'l\'équipe Zappart, il sera visible des clients.',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF2C4A73)),
                        ),
                      ),
                    ],
                    _TopBar(step: _step, total: _titres.length),
                    const SizedBox(height: 8),
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
                      submitLabel: modifier
                          ? 'Enregistrer et renvoyer en validation'
                          : 'Soumettre pour validation',
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
    if (context.read<AuthService>().lectureSeule) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Abonnement suspendu — renouvelez pour publier ou '
            'modifier une annonce.'),
      ));
      return;
    }
    final modifier = f.editionComplete;
    final aUnRef = f.editRef != null;
    final ok = await f.submit();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(modifier
            ? "Modifications envoyées. L'annonce repasse en validation."
            : aUnRef
                ? "Bien envoyé pour validation. Il rejoindra la marketplace dès son approbation."
                : "Annonce envoyée pour validation. Elle sera en ligne dès son approbation."),
      ));
      context.go(aUnRef ? '/parc/${f.editRef!.id}' : '/parc');
    }
  }
}

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
    this.submitLabel = 'Soumettre pour validation',
  });
  final int step, total;
  final bool canNext, submitting;
  final VoidCallback onBack, onNext, onSubmit;
  final String submitLabel;

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
          onPressed: submitting || !canNext
              ? null
              : (last ? onSubmit : onNext),
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(last ? submitLabel : 'Suivant'),
        ),
      ],
    );
  }
}

// ── Petits composants de saisie ─────────────────────────────────────────────

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
                        fontSize: 12, color: AppTheme.inkSoft, height: 1.35)),
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
  });
  final String initial;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initial,
      onChanged: onChanged,
      keyboardType: keyboardType,
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
  });
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;

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
                    color:
                        selected.contains(o) ? AppTheme.ink : AppTheme.line),
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

// ── Étape 1 — Localisation ─────────────────────────────────────────────────

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
              f.zone = ''; // changer de quartier invalide la zone
              f.touch();
            },
          ),
          if (quartierADesZones(f.quartier)) ...[
            const SizedBox(height: 14),
            const _Label('Zone / sous-quartier',
                hint: 'Ce quartier est découpé — précisez la zone'),
            DropdownButtonFormField<String>(
              value: zonesDuQuartier(f.quartier)
                      .any((z) => z.label == f.zone)
                  ? f.zone
                  : null,
              isExpanded: true,
              hint: const Text('Choisir la zone'),
              items: [
                for (final z in zonesDuQuartier(f.quartier))
                  DropdownMenuItem(value: z.label, child: Text(z.label)),
              ],
              onChanged: (v) {
                f.zone = v ?? '';
                f.touch();
              },
            ),
          ],
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
          const _Label('Position exacte sur la carte',
              hint:
                  'Recherchez l\'adresse ou touchez la carte. Obligatoire : la visite et le déménagement offert en dépendent.'),
          MapPicker(
            lat: f.geoLat,
            lng: f.geoLng,
            quartierKey: f.quartier,
            onChanged: (lat, lng) {
              f.geoLat = lat;
              f.geoLng = lng;
              f.touch();
            },
          ),
        ],
      ),
    );
  }
}

// ── Étape 2 — Caractéristiques ─────────────────────────────────────────────

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
                    style:
                        TextStyle(fontSize: 13.5, color: AppTheme.inkSoft))),
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

// ── Étape 3 — Commodités ───────────────────────────────────────────────────

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
              onTap: (v) {
                f.comodites.contains(v)
                    ? f.comodites.remove(v)
                    : f.comodites.add(v);
                f.touch();
              },
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Les commodités cochées qui se photographient (cuisine, balcon, '
            'piscine, groupe électrogène…) demanderont une photo à l\'étape suivante.',
            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ── Étape 4 — Photos par pièce ─────────────────────────────────────────────

class _StepPhotos extends StatefulWidget {
  const _StepPhotos(this.f);
  final AnnonceForm f;
  @override
  State<_StepPhotos> createState() => _StepPhotosState();
}

class _StepPhotosState extends State<_StepPhotos> {
  String? _loadingCat;

  Future<void> _pick(String cat) async {
    setState(() => _loadingCat = cat);
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 82);
      final list = widget.f.photos.putIfAbsent(cat, () => []);
      for (final x in picked) {
        final bytes = await x.readAsBytes();
        list.add(PickedPhoto.bytes(
          bytes,
          x.mimeType ??
              (x.name.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : 'image/jpeg'),
        ));
      }
      widget.f.touch();
    } finally {
      if (mounted) setState(() => _loadingCat = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final pieces = f.categoriesPieces;
    final comm = f.categoriesCommodites;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Photos par pièce',
              hint:
                  'Au moins une photo par pièce (obligatoire), 3 photos minimum au total. Max 10 Mo par image.'),
          const SizedBox(height: 6),
          for (final c in pieces)
            _CatBlock(
              titre: c,
              obligatoire: true,
              photos: f.photos[c] ?? const [],
              loading: _loadingCat == c,
              onAdd: () => _pick(c),
              onRemove: (i) {
                f.photos[c]!.removeAt(i);
                f.touch();
              },
            ),
          if (comm.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Commodités',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final c in comm)
              _CatBlock(
                titre: c,
                obligatoire: false,
                photos: f.photos[c] ?? const [],
                loading: _loadingCat == c,
                onAdd: () => _pick(c),
                onRemove: (i) {
                  f.photos[c]!.removeAt(i);
                  f.touch();
                },
              ),
          ],
          if (f.piecesSansPhoto.isNotEmpty && !f.editionComplete)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Pièces sans photo : ${f.piecesSansPhoto.join(', ')}',
                  style:
                      const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ),
          if (f.editionComplete)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  'Vos photos actuelles sont conservées. Ajoutez-en ou '
                  'retirez-en si besoin (3 minimum).',
                  style: TextStyle(color: AppTheme.inkSoft, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _CatBlock extends StatelessWidget {
  const _CatBlock({
    required this.titre,
    required this.obligatoire,
    required this.photos,
    required this.loading,
    required this.onAdd,
    required this.onRemove,
  });
  final String titre;
  final bool obligatoire;
  final List<PickedPhoto> photos;
  final bool loading;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(titre,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            if (!obligatoire)
              const Text('· optionnel',
                  style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                _Thumb(photo: photos[i], onRemove: () => onRemove(i)),
              InkWell(
                onTap: loading ? null : onAdd,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Center(
                    child: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_a_photo_outlined,
                            size: 20, color: AppTheme.inkSoft),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onRemove});
  final PickedPhoto photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: photo.estExistante
                ? Image.network(photo.url!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppTheme.panel))
                : Image.memory(photo.bytes!, fit: BoxFit.cover),
          ),
          if (photo.tropLourde)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('> 10 Mo',
                  style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          Positioned(
            top: 3,
            right: 3,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Étape 5 — Concierge ────────────────────────────────────────────────────

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

// ── Étape 6 — Prix & description ───────────────────────────────────────────

class _StepPrix extends StatefulWidget {
  const _StepPrix(this.f);
  final AnnonceForm f;
  @override
  State<_StepPrix> createState() => _StepPrixState();
}

class _StepPrixState extends State<_StepPrix> {
  final _descCtrl = TextEditingController();
  final _accCtrl = TextEditingController();
  bool _ai = false;
  String? _aiMsg;

  @override
  void initState() {
    super.initState();
    _descCtrl.text = widget.f.description;
    _accCtrl.text = widget.f.accroche;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _accCtrl.dispose();
    super.dispose();
  }

  Future<void> _generer() async {
    final f = widget.f;
    setState(() {
      _ai = true;
      _aiMsg = null;
    });
    final res = await AiDescription.generer(
      journalier: f.isJournalier,
      type: f.type,
      quartier: f.quartier,
      cite: f.cite,
      nbpiece: f.nbpiece,
      nbchambre: f.nbchambre,
      nbsalon: f.nbsalon,
      nbbain: f.nbbain,
      emplacement: f.emplacement,
      comodites: f.comodites.toList(),
      accrocheExistante: f.accroche,
      descriptionExistante: f.description,
    );
    if (!mounted) return;
    setState(() {
      _ai = false;
      if (res == null) {
        _aiMsg = 'Génération indisponible — écrivez le texte à la main.';
      } else {
        if (res.description.isNotEmpty) {
          f.description = res.description;
          _descCtrl.text = res.description;
        }
        if (res.accroche.isNotEmpty) {
          f.accroche = res.accroche;
          _accCtrl.text = res.accroche;
        }
        f.touch();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final fmt = NumberFormat.decimalPattern('fr');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
              f.isJournalier ? 'Prix par nuit (FCFA)' : 'Loyer mensuel (FCFA)',
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
            const _Label("Durée d'engagement minimale"),
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
                activeThumbColor: AppTheme.ink,
                onChanged: (v) {
                  f.journeeActive = v;
                  f.touch();
                },
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                    'Proposer aussi la location à la journée (day-use)',
                    style: TextStyle(fontSize: 13)),
              ),
            ]),
            if (f.journeeActive)
              SizedBox(
                width: 220,
                child: _Field(
                  initial: f.prixJournee == 0
                      ? ''
                      : f.prixJournee.toStringAsFixed(0),
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
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: _Label('Description', hint: 'Au moins 20 caractères')),
              OutlinedButton.icon(
                onPressed: _ai ? null : _generer,
                icon: _ai
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(_ai
                    ? 'Génération…'
                    : (f.description.isEmpty ? 'Générer avec l\'IA' : 'Améliorer avec l\'IA')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.ink,
                  side: const BorderSide(color: AppTheme.ink),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_aiMsg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_aiMsg!,
                  style:
                      const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ),
          TextField(
            controller: _descCtrl,
            maxLines: 5,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
                hintText:
                    'Décrivez le logement, le quartier, ce qui le rend agréable…'),
            onChanged: (v) {
              f.description = v;
              f.touch();
            },
          ),
          const SizedBox(height: 14),
          const _Label('Accroche', hint: 'Une phrase courte'),
          TextField(
            controller: _accCtrl,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
                hintText: 'Ex. Appartement lumineux à 5 min de la plage'),
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

// ── Étape 7 — Récapitulatif ────────────────────────────────────────────────

class _StepRecap extends StatelessWidget {
  const _StepRecap(this.f);
  final AnnonceForm f;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern('fr');
    final quartierLabel = quartierInfoFor(f.quartier)?.label ?? f.quartier;
    PickedPhoto? cover;
    for (final c in f.categoriesPhotos) {
      final l = f.photos[c];
      if (l != null && l.isNotEmpty) {
        cover = l.first;
        break;
      }
    }
    if (cover == null) {
      for (final l in f.photos.values) {
        if (l.isNotEmpty) {
          cover = l.first;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cover != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: cover.estExistante
                        ? Image.network(cover.url!, fit: BoxFit.cover)
                        : Image.memory(cover.bytes!, fit: BoxFit.cover),
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
              _row(f.isJournalier ? 'Prix / nuit' : 'Loyer',
                  '${fmt.format(f.prix.round())} FCFA'),
              if (!f.isJournalier)
                _row('Caution',
                    '${fmt.format(f.cautionCalculee.round())} FCFA (${f.cautionMois} mois)'),
              if (f.isJournalier && f.journeeActive)
                _row('Prix journée',
                    '${fmt.format(f.prixJournee.round())} FCFA'),
              _row('Photos', '${f.totalPhotos}'),
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
            "En soumettant, l'annonce part en validation. Un membre de l'équipe "
            "Zappart la vérifie (photos, prix, cohérence) puis la met en ligne. "
            "Vous serez notifié. Les marges et commissions Zappart sont ajoutées "
            "à la validation.",
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
