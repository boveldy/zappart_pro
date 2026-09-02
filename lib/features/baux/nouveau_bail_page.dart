import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/bail.dart';
import '../../data/house.dart';
import '../../data/proprietaire.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../proprietaires/proprietaire_picker.dart';

/// Création d'un bail (formulaire unique) : locataire, bien (du parc ou bien
/// privé hors marketplace), conditions. À la validation : 1 doc `baux` +
/// N échéances générées (batch).
class NouveauBailPage extends StatefulWidget {
  const NouveauBailPage({super.key});

  @override
  State<NouveauBailPage> createState() => _NouveauBailPageState();
}

class _NouveauBailPageState extends State<NouveauBailPage> {
  // locataire
  final _nom = TextEditingController();
  final _tel = TextEditingController();
  Proprietaire? _proprio;
  // bien
  String? _houseId; // existant
  bool _bienPrive = false;
  bool _retirerMarketplace = true;
  final _bienPriveTitre = TextEditingController();
  // conditions
  final _loyer = TextEditingController();
  final _charges = TextEditingController(text: '0');
  ChargesMode _chargesMode = ChargesMode.forfait;
  int _cautionMois = 2;
  int _duree = 24;
  int _jour = 5;
  DateTime _entree = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _commMode = 'pourcentage';
  final _commValeur = TextEditingController(text: '8');
  EncaissementMode _encaissement = EncaissementMode.direct;

  bool _busy = false;
  final _fmt = NumberFormat('#,###', 'fr_FR');
  static final _df = DateFormat('d MMMM yyyy', 'fr');

  @override
  void dispose() {
    for (final c in [
      _nom, _tel, _bienPriveTitre, _loyer, _charges, _commValeur
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _loyerV =>
      double.tryParse(_loyer.text.trim().replaceAll(' ', '')) ?? 0;
  double get _chargesV =>
      double.tryParse(_charges.text.trim().replaceAll(' ', '')) ?? 0;

  bool _valide(List<House> parc) {
    if (_nom.text.trim().isEmpty || _tel.text.trim().length < 6) return false;
    if (_bienPrive) {
      if (_bienPriveTitre.text.trim().isEmpty) return false;
    } else if (_houseId == null) {
      return false;
    }
    if (_loyerV <= 0) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null || !auth.estHote) {
      return const PageScaffold(
        title: 'Nouveau bail',
        child: EmptyState('Compte non hôte.'),
      );
    }
    final repo = HouseRepository(ref);

    return StreamBuilder<List<House>>(
      stream: repo.mine(),
      builder: (context, snap) {
        final parc = (snap.data ?? const <House>[])
            .where((h) => !h.archivee)
            .toList();
        final loyerCharges =
            _chargesMode == ChargesMode.forfait ? _loyerV + _chargesV : _loyerV;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: () => context.go('/baux'),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Baux'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.inkSoft,
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Nouveau bail', style: AppTheme.h1),
                  const SizedBox(height: 18),

                  // ── Locataire ──
                  AppCard(
                    title: 'Locataire',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row2(
                          _field(_nom, 'Nom complet', 'Ex. Awa Ndiaye'),
                          _field(_tel, 'Téléphone', '+221 77 000 00 00',
                              phone: true),
                        ),
                        const SizedBox(height: 12),
                        _lbl('Propriétaire du bien (pour le relevé)'),
                        _ProprioField(
                          proprio: _proprio,
                          onPick: () async {
                            final ref =
                                context.read<AuthService>().partenaireRef;
                            if (ref == null) return;
                            final p = await pickProprietaire(
                                context, ProprietaireRepository(ref));
                            if (p != null) setState(() => _proprio = p);
                          },
                          onClear: () => setState(() => _proprio = null),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Le locataire pourra être invité à créer un compte Zappart '
                          'pour suivre ses quittances et payer en ligne.',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Bien ──
                  AppCard(
                    title: 'Bien',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_bienPrive) ...[
                          _lbl('Choisir dans le parc'),
                          DropdownButtonFormField<String>(
                            value: _houseId,
                            isExpanded: true,
                            hint: const Text('Sélectionner un bien'),
                            items: [
                              for (final h in parc)
                                DropdownMenuItem(
                                    value: h.id,
                                    child: Text(h.titre,
                                        overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setState(() => _houseId = v),
                          ),
                          if (_houseId != null) ...[
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => setState(() =>
                                  _retirerMarketplace = !_retirerMarketplace),
                              child: Row(children: [
                                Icon(
                                    _retirerMarketplace
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 18,
                                    color: _retirerMarketplace
                                        ? AppTheme.ink
                                        : AppTheme.inkSoft),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                      'Retirer ce bien du marketplace (il est loué)',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ]),
                            ),
                          ],
                        ] else ...[
                          _lbl('Bien privé (hors marketplace)'),
                          _rawField(_bienPriveTitre,
                              'Ex. Ouakam — Studio 12'),
                          const SizedBox(height: 6),
                          const Text(
                            'Un bien loué que vous ne publiez pas. Il apparaîtra dans '
                            'le Parc avec le badge « Loué · privé ».',
                            style: TextStyle(
                                fontSize: 11.5, color: AppTheme.inkSoft),
                          ),
                        ],
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => setState(() {
                            _bienPrive = !_bienPrive;
                            _houseId = null;
                          }),
                          child: Row(children: [
                            Icon(
                                _bienPrive
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 18,
                                color: _bienPrive
                                    ? AppTheme.ink
                                    : AppTheme.inkSoft),
                            const SizedBox(width: 8),
                            const Text('Ce bien n\'est pas dans mon parc',
                                style: TextStyle(fontSize: 12.5)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Conditions ──
                  AppCard(
                    title: 'Conditions',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row2(
                          _field(_loyer, 'Loyer mensuel (FCFA)', 'Ex. 120000',
                              num: true),
                          _field(_charges, 'Charges (FCFA / mois)', '0',
                              num: true),
                        ),
                        const SizedBox(height: 14),
                        _lbl('Charges'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final m in ChargesMode.values)
                            _pill(chargesModeLabel(m), _chargesMode == m,
                                () => setState(() => _chargesMode = m)),
                        ]),
                        const SizedBox(height: 14),
                        _row2(
                          _stepper('Caution (mois)', _cautionMois, 1, 3,
                              (v) => setState(() => _cautionMois = v)),
                          _stepper('Jour d\'échéance', _jour, 1, 28,
                              (v) => setState(() => _jour = v)),
                        ),
                        const SizedBox(height: 14),
                        _row2(
                          _dureeField(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _lbl('Date d\'entrée'),
                              InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: _entree,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 90)),
                                  );
                                  if (d != null) setState(() => _entree = d);
                                },
                                child: _box(_df.format(_entree)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _lbl('Commission de gérance'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _pill('8 %', _commMode == 'pourcentage' &&
                              _commValeur.text == '8', () {
                            setState(() {
                              _commMode = 'pourcentage';
                              _commValeur.text = '8';
                            });
                          }),
                          _pill('10 %', _commMode == 'pourcentage' &&
                              _commValeur.text == '10', () {
                            setState(() {
                              _commMode = 'pourcentage';
                              _commValeur.text = '10';
                            });
                          }),
                          _pill('Montant fixe', _commMode == 'fixe',
                              () => setState(() => _commMode = 'fixe')),
                          _pill('Aucune', _commMode == 'aucune',
                              () => setState(() => _commMode = 'aucune')),
                        ]),
                        if (_commMode != 'aucune') ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 180,
                            child: _rawField(_commValeur,
                                _commMode == 'fixe' ? 'FCFA / mois' : '%',
                                num: true),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _lbl('Encaissement du loyer'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _pill('Direct (agence)',
                              _encaissement == EncaissementMode.direct,
                              () => setState(
                                  () => _encaissement = EncaissementMode.direct)),
                          _pill('En ligne (Zappart)',
                              _encaissement == EncaissementMode.zappart,
                              () => setState(() =>
                                  _encaissement = EncaissementMode.zappart)),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          _encaissement == EncaissementMode.direct
                              ? 'Le locataire paie l\'agence directement (Wave / OM / espèces). L\'app lui affiche vos numéros et vous notifie quand il déclare avoir payé.'
                              : 'Le locataire paie dans l\'app ; Zappart encaisse et vous reverse (loyer − commission). Nécessite l\'activation du paiement en ligne.',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Récap échéancier ──
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.panel,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.line),
                    ),
                    child: Text(
                      _loyerV <= 0
                          ? 'Renseignez le loyer pour voir l\'échéancier.'
                          : '${_duree.clamp(1, 36)} échéances de '
                              '${_fmt.format(loyerCharges.round())} FCFA — '
                              'la 1ʳᵉ le $_jour ${_df.format(_entree).split(' ').skip(1).join(' ')}. '
                              'Le locataire déjà en place ? Vous marquerez les mois '
                              'antérieurs « payés » sans ressaisir l\'historique.',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.inkSoft, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(children: [
                    TextButton(
                      onPressed: () => context.go('/baux'),
                      child: const Text('Annuler',
                          style: TextStyle(color: AppTheme.inkSoft)),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: !_valide(parc) || _busy
                          ? null
                          : () => _submit(ref, parc),
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Créer le bail'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(
      DocumentReference<Map<String, dynamic>> partenaireRef,
      List<House> parc) async {
    // Garde de quota : recompte les baux actifs au moment de créer (le forfait
    // peut avoir changé, ou l'onglet être resté ouvert).
    final abo = context.read<AuthService>().abonnement;
    if (abo.bloqueCreation) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Abonnement expiré — renouvelez pour créer un bail.')));
      return;
    }
    if (abo.quotaBaux < 1000) {
      final actifs = (await BailRepository(partenaireRef).baux().first)
          .where((b) => b.actif)
          .length;
      if (actifs >= abo.quotaBaux && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Quota de ${abo.quotaBaux} baux atteint (forfait '
              '${abo.label}).'),
          action: SnackBarAction(
            label: 'Forfaits',
            onPressed: () => context.go('/abonnement'),
          ),
        ));
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      DocumentReference<Map<String, dynamic>>? houseRef;
      String bienTitre;

      if (_bienPrive) {
        bienTitre = _bienPriveTitre.text.trim();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final doc = db.collection('house').doc();
        await doc.set({
          'partenaireId': partenaireRef,
          'types': '',
          'locationtype': 'Mensuel',
          'quartier': bienTitre,
          'cite': '',
          'active': false,
          'sur_marketplace': false,
          'statut_validation': 'prive',
          'prix': _loyerV,
          'image': <String>[],
          'created_at': FieldValue.serverTimestamp(),
          if (uid != null) 'cree_par': uid,
        });
        houseRef = doc;
      } else {
        houseRef = db.collection('house').doc(_houseId);
        final h = parc.firstWhere((h) => h.id == _houseId);
        bienTitre = h.titre;
        if (_retirerMarketplace && h.active) {
          try {
            await houseRef.update({'active': false});
          } catch (_) {/* non bloquant */}
        }
      }

      final repo = BailRepository(partenaireRef);
      final id = await repo.creerBail(
        houseRef: houseRef,
        bienTitre: bienTitre,
        locataireNom: _nom.text,
        locataireTel: _tel.text,
        proprietaireNom: _proprio?.nom ?? '',
        proprietaireRef: _proprio == null
            ? null
            : FirebaseFirestore.instance
                .collection('proprietaires')
                .doc(_proprio!.id),
        loyer: _loyerV,
        charges: _chargesV,
        chargesMode: _chargesMode,
        cautionMois: _cautionMois,
        dateEntree: _entree,
        dureeMois: _duree,
        jourEcheance: _jour,
        commissionMode: _commMode,
        commissionValeur:
            double.tryParse(_commValeur.text.trim().replaceAll(' ', '')) ?? 0,
        encaissementMode: _encaissement,
      );
      if (mounted) context.go('/baux/$id');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Création impossible : $e')));
      }
    }
  }

  // ── helpers UI ──
  Widget _row2(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 14),
          Expanded(child: b),
        ],
      );

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Text(t,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _field(TextEditingController c, String label, String hint,
      {bool num = false, bool phone = false, bool optional = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lbl(optional ? '$label · optionnel' : label),
        _rawField(c, hint, num: num, phone: phone),
      ],
    );
  }

  Widget _rawField(TextEditingController c, String hint,
      {bool num = false, bool phone = false}) {
    return TextField(
      controller: c,
      keyboardType: num
          ? TextInputType.number
          : phone
              ? TextInputType.phone
              : TextInputType.text,
      inputFormatters:
          num ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(hintText: hint, isDense: true),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _box(String t) => Container(
        height: 42,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(t, style: const TextStyle(fontSize: 13)),
      );

  Widget _pill(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: on ? AppTheme.ink : Colors.white,
            border: Border.all(color: on ? AppTheme.ink : AppTheme.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : AppTheme.ink)),
        ),
      );

  Widget _stepper(String label, int value, int min, int max,
      ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lbl(label),
        Row(children: [
          _rnd(Icons.remove, value > min ? () => onChanged(value - 1) : null),
          SizedBox(
              width: 44,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700))),
          _rnd(Icons.add, value < max ? () => onChanged(value + 1) : null),
        ]),
      ],
    );
  }

  Widget _dureeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lbl('Durée du bail'),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.line),
            borderRadius: BorderRadius.circular(11),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _duree,
              isExpanded: true,
              style: const TextStyle(fontSize: 13, color: AppTheme.ink),
              items: const [
                DropdownMenuItem(value: 12, child: Text('12 mois')),
                DropdownMenuItem(value: 24, child: Text('24 mois')),
                DropdownMenuItem(value: 36, child: Text('36 mois')),
              ],
              onChanged: (v) => setState(() => _duree = v ?? 24),
            ),
          ),
        ),
      ],
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

// ── Sélecteur de propriétaire ─────────────────────────────────────────────

class _ProprioField extends StatelessWidget {
  const _ProprioField({
    required this.proprio,
    required this.onPick,
    required this.onClear,
  });
  final Proprietaire? proprio;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (proprio == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
          label: const Text('Lier un propriétaire (optionnel)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.ink,
            side: const BorderSide(color: AppTheme.line),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppTheme.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(proprio!.nom,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                if (proprio!.sousTitre.isNotEmpty)
                  Text(proprio!.sousTitre,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.inkSoft)),
              ],
            ),
          ),
          TextButton(onPressed: onPick, child: const Text('Changer')),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppTheme.inkSoft,
          ),
        ],
      ),
    );
  }
}
