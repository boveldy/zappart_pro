import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Modèle « Baux & loyers » (couche 2) — collections Firestore `baux` et
/// `echeances`, écrites en direct par l'hôte (aucune Cloud Function).
///
/// - `baux/{id}` : le contrat (locataire, bien, conditions).
/// - `echeances/{id}` : un loyer dû par mois, généré à la création du bail.
///
/// Le statut « retard » / « dû » / « à venir » est **dérivé de la date**
/// (`statutAffiche`) tant que le loyer n'est pas explicitement `paye` /
/// `partiel` — pas besoin de cron pour l'affichage.

/// Canonicalise un numéro sénégalais vers `221XXXXXXXXX` (indicatif SANS `+`).
/// Sert de clé de liaison avec le `phone_number` (vérifié OTP) du locataire.
/// ⚠️ DOIT rester strictement identique à `_normaliser` (backend
/// `services/otp.py`) et `normalizePhone` (app officielle `core/constants.dart`).
String canonPhone(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 9 && d.startsWith('7')) d = '221$d';
  return d;
}

enum EncaissementMode { direct, zappart }

String encaissementModeKey(EncaissementMode m) => m.name;
EncaissementMode encaissementModeFrom(String s) =>
    s == 'zappart' ? EncaissementMode.zappart : EncaissementMode.direct;
String encaissementModeLabel(EncaissementMode m) => switch (m) {
      EncaissementMode.direct => 'Encaissement direct par l\'agence',
      EncaissementMode.zappart => 'Paiement en ligne via Zappart',
    };

enum ChargesMode { forfait, incluses, aPart }

String chargesModeLabel(ChargesMode m) => switch (m) {
      ChargesMode.forfait => 'Forfait mensuel',
      ChargesMode.incluses => 'Comprises dans le loyer',
      ChargesMode.aPart => 'À la charge du locataire',
    };

ChargesMode chargesModeFrom(String s) => switch (s) {
      'incluses' => ChargesMode.incluses,
      'a_part' => ChargesMode.aPart,
      _ => ChargesMode.forfait,
    };

String chargesModeKey(ChargesMode m) => switch (m) {
      ChargesMode.forfait => 'forfait',
      ChargesMode.incluses => 'incluses',
      ChargesMode.aPart => 'a_part',
    };

class Bail {
  Bail({
    required this.id,
    required this.houseRefId,
    required this.locataireNom,
    required this.locataireTel,
    required this.locataireLie,
    required this.proprietaireNom,
    required this.loyer,
    required this.charges,
    required this.chargesMode,
    required this.cautionMois,
    required this.dateEntree,
    required this.dureeMois,
    required this.jourEcheance,
    required this.commissionMode,
    required this.commissionValeur,
    required this.statut,
    required this.bienTitre,
    this.finDate,
    this.finMotif = '',
    this.cautionStatut = '',
    this.cautionRestitue = 0,
    this.cautionRetenue = 0,
    this.cautionNote = '',
    this.encaissementMode = EncaissementMode.direct,
    this.locataireTelCanonique = '',
  });

  final String id;
  final String? houseRefId;
  final String locataireNom;
  final String locataireTel;
  final bool locataireLie; // le locataire a un compte Zappart
  final String proprietaireNom;
  final double loyer;
  final double charges;
  final ChargesMode chargesMode;
  final int cautionMois;
  final DateTime? dateEntree;
  final int dureeMois;
  final int jourEcheance;
  final String commissionMode; // 'pourcentage' | 'fixe' | 'aucune'
  final double commissionValeur;
  final String statut; // 'actif' | 'termine' | 'resilie'
  final String bienTitre;
  final DateTime? finDate;
  final String finMotif;
  final String cautionStatut; // '' | 'restituee' | 'retenue' | 'partielle'
  final double cautionRestitue;
  final double cautionRetenue;
  final String cautionNote;
  final EncaissementMode encaissementMode;
  final String locataireTelCanonique;

  double get loyerCharges =>
      chargesMode == ChargesMode.forfait ? loyer + charges : loyer;
  double get caution => cautionMois * loyer;
  bool get actif => statut == 'actif';
  bool get termine => statut == 'termine' || statut == 'resilie';

  /// Date de la dernière échéance non annulée (fin effective du bail).
  DateTime? finEffective(List<Echeance> ech) {
    final dates = ech
        .where((e) => e.statutBrut != 'annule' && e.dateEcheance != null)
        .map((e) => e.dateEcheance!);
    return dates.isEmpty ? null : dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Le bail actif arrive à son terme (dernière échéance dans moins de
  /// `seuilJours`, ou déjà dépassée) → à prolonger ou clôturer.
  bool arriveATerme(List<Echeance> ech, {int seuilJours = 45}) {
    if (!actif) return false;
    final fin = finEffective(ech);
    if (fin == null) return false;
    return DateTime.now()
        .isAfter(fin.subtract(Duration(days: seuilJours)));
  }

  String get finMotifLabel => switch (finMotif) {
        'Résiliation' => 'Résilié',
        'Départ anticipé' => 'Départ anticipé',
        'Fin de bail' => 'Bail arrivé à terme',
        _ => finMotif.isEmpty ? 'Clôturé' : finMotif,
      };

  String get cautionStatutLabel => switch (cautionStatut) {
        'restituee' => 'Caution restituée intégralement',
        'retenue' => 'Caution retenue intégralement',
        'partielle' => 'Caution restituée partiellement',
        _ => 'Caution non soldée',
      };

  String get commissionLabel => switch (commissionMode) {
        'pourcentage' => '${commissionValeur.toStringAsFixed(
            commissionValeur % 1 == 0 ? 0 : 1)} % du loyer',
        'fixe' =>
          '${NumberFormat('#,###', 'fr_FR').format(commissionValeur.round())} FCFA / mois',
        _ => 'Aucune',
      };

  double commissionSur(double loyersEncaisses) => switch (commissionMode) {
        'pourcentage' => loyersEncaisses * commissionValeur / 100,
        'fixe' => commissionValeur, // par mois — l'appelant multiplie si besoin
        _ => 0,
      };

  static Bail fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Bail(
      id: d.id,
      houseRefId:
          m['house_ref'] is DocumentReference ? (m['house_ref'] as DocumentReference).id : null,
      locataireNom: (m['locataire_nom'] as String?)?.trim() ?? '',
      locataireTel: (m['locataire_tel'] as String?)?.trim() ?? '',
      locataireLie: m['locataire_user_ref'] is DocumentReference,
      proprietaireNom: (m['proprietaire_nom'] as String?)?.trim() ?? '',
      loyer: (m['loyer'] as num?)?.toDouble() ?? 0,
      charges: (m['charges'] as num?)?.toDouble() ?? 0,
      chargesMode: chargesModeFrom((m['charges_mode'] as String?) ?? 'forfait'),
      cautionMois: (m['caution_mois'] as num?)?.toInt() ?? 1,
      dateEntree:
          m['date_entree'] is Timestamp ? (m['date_entree'] as Timestamp).toDate() : null,
      dureeMois: (m['duree_mois'] as num?)?.toInt() ?? 12,
      jourEcheance: (m['jour_echeance'] as num?)?.toInt() ?? 5,
      commissionMode: (m['commission_mode'] as String?) ?? 'aucune',
      commissionValeur: (m['commission_valeur'] as num?)?.toDouble() ?? 0,
      statut: (m['statut'] as String?)?.trim() ?? 'actif',
      bienTitre: (m['bien_titre'] as String?)?.trim() ?? '',
      finDate:
          m['fin_date'] is Timestamp ? (m['fin_date'] as Timestamp).toDate() : null,
      finMotif: (m['fin_motif'] as String?)?.trim() ?? '',
      cautionStatut: (m['caution_statut'] as String?)?.trim() ?? '',
      cautionRestitue: (m['caution_restitue'] as num?)?.toDouble() ?? 0,
      cautionRetenue: (m['caution_retenue'] as num?)?.toDouble() ?? 0,
      cautionNote: (m['caution_note'] as String?)?.trim() ?? '',
      encaissementMode:
          encaissementModeFrom((m['encaissement_mode'] as String?) ?? 'direct'),
      locataireTelCanonique:
          (m['locataire_tel_canonique'] as String?)?.trim() ?? '',
    );
  }
}

// ── Dépenses & réparations imputées à un bail ──────────────────────────────

enum DepenseCharge { proprietaire, agence, locataire }

String depenseChargeLabel(DepenseCharge c) => switch (c) {
      DepenseCharge.proprietaire => 'À la charge du propriétaire',
      DepenseCharge.agence => 'À la charge de l\'agence',
      DepenseCharge.locataire => 'Refacturée au locataire',
    };

String depenseChargeCourt(DepenseCharge c) => switch (c) {
      DepenseCharge.proprietaire => 'Propriétaire',
      DepenseCharge.agence => 'Agence',
      DepenseCharge.locataire => 'Locataire',
    };

DepenseCharge depenseChargeFrom(String s) => DepenseCharge.values
    .firstWhere((c) => c.name == s, orElse: () => DepenseCharge.proprietaire);

const kDepenseCategories = <String>[
  'Réparation',
  'Entretien',
  'Plomberie',
  'Électricité',
  'Peinture',
  'Ménage',
  'Taxe / impôt',
  'Charges copropriété',
  'Autre',
];

class Depense {
  Depense({
    required this.id,
    required this.bailRefId,
    required this.montant,
    required this.categorie,
    required this.libelle,
    required this.charge,
    required this.date,
  });

  final String id;
  final String? bailRefId;
  final double montant;
  final String categorie;
  final String libelle;
  final DepenseCharge charge;
  final DateTime? date;

  bool get imputeeProprietaire => charge == DepenseCharge.proprietaire;

  static Depense fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return Depense(
      id: d.id,
      bailRefId: m['bail_ref'] is DocumentReference
          ? (m['bail_ref'] as DocumentReference).id
          : null,
      montant: (m['montant'] as num?)?.toDouble() ?? 0,
      categorie: (m['categorie'] as String?)?.trim() ?? 'Autre',
      libelle: (m['libelle'] as String?)?.trim() ?? '',
      charge: depenseChargeFrom((m['charge'] as String?) ?? 'proprietaire'),
      date: m['date'] is Timestamp ? (m['date'] as Timestamp).toDate() : null,
    );
  }
}

enum EStatut { aVenir, du, retard, paye, partiel, annule }

({String label, String tone}) eStatutBadge(EStatut s) => switch (s) {
      EStatut.paye => (label: 'Payé', tone: 'ok'),
      EStatut.partiel => (label: 'Partiel', tone: 'wait'),
      EStatut.du => (label: 'Loyer dû', tone: 'wait'),
      EStatut.retard => (label: 'En retard', tone: 'danger'),
      EStatut.annule => (label: 'Annulé', tone: 'muted'),
      EStatut.aVenir => (label: 'À venir', tone: 'muted'),
    };

class Echeance {
  Echeance({
    required this.id,
    required this.bailRefId,
    required this.houseRefId,
    required this.periode,
    required this.dateEcheance,
    required this.montantLoyer,
    required this.montantCharges,
    required this.montantDu,
    required this.statutBrut,
    required this.montantPaye,
    required this.datePaiement,
    required this.methode,
  });

  final String id;
  final String bailRefId;
  final String? houseRefId;
  final String periode; // 'yyyy-MM'
  final DateTime? dateEcheance;
  final double montantLoyer;
  final double montantCharges;
  final double montantDu;
  final String statutBrut; // 'ouvert' | 'paye' | 'partiel' | 'annule'
  final double montantPaye;
  final DateTime? datePaiement;
  final String methode;

  static final _moisFmt = DateFormat('MMMM yyyy', 'fr');

  String get periodeLabel {
    final p = DateTime.tryParse('$periode-01');
    return p == null ? periode : _cap(_moisFmt.format(p));
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  EStatut statutAffiche([DateTime? now]) {
    if (statutBrut == 'paye') return EStatut.paye;
    if (statutBrut == 'partiel') return EStatut.partiel;
    if (statutBrut == 'annule') return EStatut.annule;
    final n = now ?? DateTime.now();
    final e = dateEcheance;
    if (e == null) return EStatut.aVenir;
    final finJour = DateTime(e.year, e.month, e.day, 23, 59, 59);
    if (n.isAfter(finJour)) return EStatut.retard;
    if (n.isAfter(finJour.subtract(const Duration(days: 7)))) return EStatut.du;
    return EStatut.aVenir;
  }

  int? joursDeRetard([DateTime? now]) {
    final e = dateEcheance;
    if (e == null || statutBrut == 'paye') return null;
    final n = now ?? DateTime.now();
    final d = n.difference(DateTime(e.year, e.month, e.day)).inDays;
    return d > 0 ? d : null;
  }

  static Echeance fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return Echeance(
      id: d.id,
      bailRefId:
          m['bail_ref'] is DocumentReference ? (m['bail_ref'] as DocumentReference).id : '',
      houseRefId:
          m['house_ref'] is DocumentReference ? (m['house_ref'] as DocumentReference).id : null,
      periode: (m['periode'] as String?)?.trim() ?? '',
      dateEcheance: ts(m['date_echeance']),
      montantLoyer: (m['montant_loyer'] as num?)?.toDouble() ?? 0,
      montantCharges: (m['montant_charges'] as num?)?.toDouble() ?? 0,
      montantDu: (m['montant_du'] as num?)?.toDouble() ?? 0,
      statutBrut: (m['statut'] as String?)?.trim() ?? 'ouvert',
      montantPaye: (m['montant_paye'] as num?)?.toDouble() ?? 0,
      datePaiement: ts(m['date_paiement']),
      methode: (m['methode'] as String?)?.trim() ?? '',
    );
  }
}

// ── Signalements de paiement de loyer (côté locataire mobile) ──────────────

class SignalementLoyer {
  SignalementLoyer({
    required this.id,
    required this.bailRefId,
    required this.echeanceRefId,
    required this.periode,
    required this.montant,
    required this.methode,
    required this.canal,
    required this.statut,
    required this.locataireNom,
    required this.date,
  });

  final String id;
  final String? bailRefId;
  final String? echeanceRefId;
  final String periode;
  final double montant;
  final String methode;
  final String canal; // 'direct' | 'en_ligne'
  final String statut; // 'signale' | 'valide' | 'rejete'
  final String locataireNom;
  final DateTime? date;

  bool get enAttente => statut == 'signale';
  String get periodeLabel {
    final p = DateTime.tryParse('$periode-01');
    return p == null
        ? periode
        : Echeance._cap(DateFormat('MMMM yyyy', 'fr').format(p));
  }

  static SignalementLoyer fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return SignalementLoyer(
      id: d.id,
      bailRefId: m['bail_ref'] is DocumentReference
          ? (m['bail_ref'] as DocumentReference).id
          : null,
      echeanceRefId: m['echeance_ref'] is DocumentReference
          ? (m['echeance_ref'] as DocumentReference).id
          : null,
      periode: (m['periode'] as String?)?.trim() ?? '',
      montant: (m['montant'] as num?)?.toDouble() ?? 0,
      methode: (m['methode'] as String?)?.trim() ?? '',
      canal: (m['canal'] as String?)?.trim() ?? 'direct',
      statut: (m['statut'] as String?)?.trim() ?? 'signale',
      locataireNom: (m['locataire_nom'] as String?)?.trim() ?? '',
      date: m['date_signale'] is Timestamp
          ? (m['date_signale'] as Timestamp).toDate()
          : null,
    );
  }
}

class BailRepository {
  BailRepository(this.partenaireRef);
  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _baux => _db.collection('baux');
  CollectionReference<Map<String, dynamic>> get _echeances =>
      _db.collection('echeances');
  CollectionReference<Map<String, dynamic>> get _depenses =>
      _db.collection('depenses');

  Stream<List<Bail>> baux() => _baux
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(Bail.fromDoc).toList());

  Stream<Bail?> bail(String id) =>
      _baux.doc(id).snapshots().map((d) => d.exists ? Bail.fromDoc(d) : null);

  /// Toutes les échéances du partenaire (pour le dashboard + les retards).
  Stream<List<Echeance>> echeances() => _echeances
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(800)
      .snapshots()
      .map((s) => s.docs.map(Echeance.fromDoc).toList()
        ..sort((a, b) => (a.dateEcheance ?? DateTime(2100))
            .compareTo(b.dateEcheance ?? DateTime(2100))));

  // ⚠️ Firestore refuse une requête `list` dont le filtre ne colle pas à la
  // règle de sécurité (règle = `partenaire_ref == moi`). On filtre donc sur
  // `partenaire_ref` (autorisé) puis on garde le bail voulu côté client.
  Stream<List<Echeance>> echeancesDuBail(String bailId) => _echeances
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(1000)
      .snapshots()
      .map((s) => s.docs
          .map(Echeance.fromDoc)
          .where((e) => e.bailRefId == bailId)
          .toList()
        ..sort((a, b) => a.periode.compareTo(b.periode)));

  /// Crée le bail + ses échéances (batch unique).
  Future<String> creerBail({
    required DocumentReference<Map<String, dynamic>>? houseRef,
    required String bienTitre,
    required String locataireNom,
    required String locataireTel,
    required String proprietaireNom,
    required double loyer,
    required double charges,
    required ChargesMode chargesMode,
    required int cautionMois,
    required DateTime dateEntree,
    required int dureeMois,
    required int jourEcheance,
    required String commissionMode,
    required double commissionValeur,
    EncaissementMode encaissementMode = EncaissementMode.direct,
  }) async {
    final batch = _db.batch();
    final bailRef = _baux.doc();

    batch.set(bailRef, {
      'partenaire_ref': partenaireRef,
      if (houseRef != null) 'house_ref': houseRef,
      'bien_titre': bienTitre,
      'locataire_nom': locataireNom.trim(),
      'locataire_tel': locataireTel.trim(),
      'locataire_tel_canonique': canonPhone(locataireTel),
      'encaissement_mode': encaissementMode.name,
      'proprietaire_nom': proprietaireNom.trim(),
      'loyer': loyer,
      'charges': chargesMode == ChargesMode.forfait ? charges : 0,
      'charges_mode': chargesModeKey(chargesMode),
      'caution_mois': cautionMois,
      'date_entree': Timestamp.fromDate(dateEntree),
      'duree_mois': dureeMois,
      'jour_echeance': jourEcheance,
      'commission_mode': commissionMode,
      'commission_valeur': commissionValeur,
      'statut': 'actif',
      'created_at': FieldValue.serverTimestamp(),
    });

    final loyerCharges =
        chargesMode == ChargesMode.forfait ? loyer + charges : loyer;
    final nb = dureeMois.clamp(1, 36);
    for (var i = 0; i < nb; i++) {
      final d = DateTime(
          dateEntree.year, dateEntree.month + i, jourEcheance.clamp(1, 28));
      final per =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
      batch.set(_echeances.doc(), {
        'partenaire_ref': partenaireRef,
        'bail_ref': bailRef,
        if (houseRef != null) 'house_ref': houseRef,
        'locataire_tel_canonique': canonPhone(locataireTel),
        'periode': per,
        'date_echeance': Timestamp.fromDate(d),
        'montant_loyer': loyer,
        'montant_charges':
            chargesMode == ChargesMode.forfait ? charges : 0,
        'montant_du': loyerCharges,
        'statut': 'ouvert',
        'montant_paye': 0,
      });
    }

    await batch.commit();
    return bailRef.id;
  }

  Future<void> marquerPaye({
    required String echeanceId,
    required double montant,
    required bool partiel,
    required DateTime date,
    required String methode,
  }) =>
      _echeances.doc(echeanceId).update({
        'statut': partiel ? 'partiel' : 'paye',
        'montant_paye': montant,
        'date_paiement': Timestamp.fromDate(date),
        'methode': methode,
      });

  // ── Dépenses ──────────────────────────────────────────────────────────────

  Stream<List<Depense>> depensesDuBail(String bailId) => _depenses
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(1000)
      .snapshots()
      .map((s) => s.docs
          .map(Depense.fromDoc)
          .where((d) => d.bailRefId == bailId)
          .toList()
        ..sort((a, b) =>
            (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000))));

  Future<void> ajouterDepense({
    required String bailId,
    DocumentReference<Map<String, dynamic>>? houseRef,
    required double montant,
    required String categorie,
    required String libelle,
    required DepenseCharge charge,
    required DateTime date,
  }) =>
      _depenses.add({
        'partenaire_ref': partenaireRef,
        'bail_ref': _baux.doc(bailId),
        if (houseRef != null) 'house_ref': houseRef,
        'montant': montant,
        'categorie': categorie,
        'libelle': libelle.trim(),
        'charge': charge.name,
        'date': Timestamp.fromDate(date),
        'created_at': FieldValue.serverTimestamp(),
      });

  /// Toutes les dépenses du partenaire (relevé par propriétaire).
  Stream<List<Depense>> depenses() => _depenses
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(1000)
      .snapshots()
      .map((s) => s.docs.map(Depense.fromDoc).toList());

  Future<void> supprimerDepense(String id) => _depenses.doc(id).delete();

  /// Retire / remet un bien sur le marketplace (bascule `active`). Best-effort :
  /// échoue silencieusement pour un bien « privé » (jamais publié).
  Future<void> setBienActif(String houseId, bool actif) async {
    try {
      await _db.collection('house').doc(houseId).update({'active': actif});
    } catch (_) {/* bien privé ou déjà dans cet état */}
  }

  Future<void> setEncaissementMode(String bailId, EncaissementMode mode) =>
      _baux.doc(bailId).update({'encaissement_mode': mode.name});

  /// Prolonge un bail : ajoute `moisEnPlus` échéances à la suite de la dernière
  /// période existante (loyer révisable), et met à jour `duree_mois`.
  Future<void> prolongerBail({
    required Bail bail,
    required List<Echeance> echeancesActuelles,
    required int moisEnPlus,
    double? nouveauLoyer,
    double? nouvellesCharges,
  }) async {
    final nb = moisEnPlus.clamp(1, 36);
    final derniere = echeancesActuelles
        .map((e) => e.periode)
        .fold<String>('0000-00', (a, b) => b.compareTo(a) > 0 ? b : a);
    final p = derniere.split('-');
    var y = int.tryParse(p.first) ?? DateTime.now().year;
    var m = int.tryParse(p.last) ?? DateTime.now().month;

    final loyer = nouveauLoyer ?? bail.loyer;
    final charges = nouvellesCharges ?? bail.charges;
    final forfait = bail.chargesMode == ChargesMode.forfait;
    final loyerCharges = forfait ? loyer + charges : loyer;

    final batch = _db.batch();
    for (var i = 0; i < nb; i++) {
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
      final d = DateTime(y, m, bail.jourEcheance.clamp(1, 28));
      batch.set(_echeances.doc(), {
        'partenaire_ref': partenaireRef,
        'bail_ref': _baux.doc(bail.id),
        if (bail.houseRefId != null)
          'house_ref': _db.collection('house').doc(bail.houseRefId),
        'locataire_tel_canonique': bail.locataireTelCanonique,
        'periode': '$y-${m.toString().padLeft(2, '0')}',
        'date_echeance': Timestamp.fromDate(d),
        'montant_loyer': loyer,
        'montant_charges': forfait ? charges : 0,
        'montant_du': loyerCharges,
        'statut': 'ouvert',
        'montant_paye': 0,
      });
    }
    batch.update(_baux.doc(bail.id), {
      'duree_mois': bail.dureeMois + nb,
      if (nouveauLoyer != null) 'loyer': nouveauLoyer,
      if (nouvellesCharges != null && forfait) 'charges': nouvellesCharges,
      'prolonge_le': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  // ── Signalements de paiement de loyer ────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _signalements =>
      _db.collection('paiements_loyers');

  /// Tous les signalements en attente pour le partenaire (file de validation).
  Stream<List<SignalementLoyer>> signalementsEnAttente() => _signalements
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(200)
      .snapshots()
      .map((s) => s.docs
          .map(SignalementLoyer.fromDoc)
          .where((x) => x.statut == 'signale')
          .toList()
        ..sort((a, b) =>
            (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000))));

  Stream<List<SignalementLoyer>> signalementsDuBail(String bailId) =>
      _signalements
          .where('partenaire_ref', isEqualTo: partenaireRef)
          .limit(500)
          .snapshots()
          .map((s) => s.docs
              .map(SignalementLoyer.fromDoc)
              .where((x) => x.bailRefId == bailId)
              .toList()
            ..sort((a, b) =>
                (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000))));

  /// Rejette un signalement (le loyer n'a pas été reçu).
  Future<void> rejeterSignalement(String id) =>
      _signalements.doc(id).update({'statut': 'rejete'});

  /// Valide un signalement : marque l'échéance payée + clôt le signalement.
  Future<void> validerSignalement({
    required String signalementId,
    required String echeanceId,
    required double montant,
    required DateTime date,
    required String methode,
  }) async {
    final batch = _db.batch();
    batch.update(_echeances.doc(echeanceId), {
      'statut': 'paye',
      'montant_paye': montant,
      'date_paiement': Timestamp.fromDate(date),
      'methode': methode,
    });
    batch.update(_signalements.doc(signalementId), {'statut': 'valide'});
    await batch.commit();
  }

  // ── Clôture de bail + solde de caution ────────────────────────────────────

  /// Termine un bail : pose le statut, la date de fin, le sort de la caution,
  /// et annule les échéances postérieures listées (batch unique).
  Future<void> cloturerBail({
    required String bailId,
    required DateTime finDate,
    required String motif,
    required double cautionRestitue,
    required double cautionRetenue,
    required String cautionNote,
    required List<String> echeancesAAnnuler,
  }) async {
    final batch = _db.batch();
    final resilie = motif == 'Résiliation' || motif == 'Départ anticipé';
    batch.update(_baux.doc(bailId), {
      'statut': resilie ? 'resilie' : 'termine',
      'fin_date': Timestamp.fromDate(finDate),
      'fin_motif': motif,
      'caution_statut': cautionRetenue <= 0
          ? 'restituee'
          : cautionRestitue <= 0
              ? 'retenue'
              : 'partielle',
      'caution_restitue': cautionRestitue,
      'caution_retenue': cautionRetenue,
      'caution_note': cautionNote.trim(),
      'cloture_le': FieldValue.serverTimestamp(),
    });
    for (final id in echeancesAAnnuler) {
      batch.update(_echeances.doc(id), {'statut': 'annule'});
    }
    await batch.commit();
  }
}
