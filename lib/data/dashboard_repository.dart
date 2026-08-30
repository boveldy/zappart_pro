import 'package:cloud_firestore/cloud_firestore.dart';

/// Accès Firestore du tableau de bord — scopé à une fiche partenaire.
/// Requêtes mono-champ + tri/filtre côté client (comme l'espace partenaire
/// mobile) → aucun index composite requis.
class DashboardRepository {
  DashboardRepository(
    this.partenaireRef, {
    this.estHote = false,
    this.estPrestataire = false,
  });

  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final bool estHote;
  final bool estPrestataire;
  final _db = FirebaseFirestore.instance;

  /// Fiche partenaire (nom, solde disponible dénormalisé).
  Stream<PartenaireLite> partenaire() => partenaireRef.snapshots().map((s) {
        final m = s.data() ?? const {};
        return PartenaireLite(
          nom: (m['nom'] as String?)?.trim() ?? '',
          soldeDisponible: (m['solde_disponible'] as num?)?.toInt() ?? 0,
        );
      });

  /// Lignes du wallet (encaissements en ligne — journalier/service).
  Stream<List<WalletLine>> walletLedger() => _db
      .collection('wallet_ledger')
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(WalletLine.fromDoc).toList());

  /// Demandes de retrait de ce partenaire.
  Stream<List<RetraitLine>> retraits() => _db
      .collection('retraits_partenaires')
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(RetraitLine.fromDoc).toList());

  Stream<List<HouseLite>> houses() {
    if (!estHote) return Stream.value(const []);
    return _db
        .collection('house')
        .where('partenaireId', isEqualTo: partenaireRef)
        .limit(300)
        .snapshots()
        .map((s) => s.docs.map(HouseLite.fromDoc).toList());
  }

  /// Réservations sur les logements de l'hôte (`proprietaire_ref`).
  /// Collection **`Reservation`** (R majuscule — cf. règles Firestore).
  /// Le volet prestataire (missions) fera l'objet d'un écran dédié.
  Stream<List<ResaLite>> reservations() {
    if (!estHote) return Stream.value(const []);
    return _db
        .collection('Reservation')
        .where('proprietaire_ref', isEqualTo: partenaireRef)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map(ResaLite.fromDoc).toList());
  }
}

class PartenaireLite {
  PartenaireLite({required this.nom, required this.soldeDisponible});
  final String nom;
  final int soldeDisponible;
}

class WalletLine {
  WalletLine({
    required this.montant,
    required this.type,
    required this.statut,
    required this.dateEncaissement,
  });
  final double montant;
  final String type; // 'journalier' | 'service'
  final String statut; // 'en_attente' | 'disponible' | 'annulee'
  final DateTime? dateEncaissement;

  bool get enAttente => statut == 'en_attente';
  bool get actif => statut != 'annulee';

  static WalletLine fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return WalletLine(
      montant: (m['montant'] as num?)?.toDouble() ?? 0,
      type: (m['type'] as String?)?.trim() ?? '',
      statut: (m['statut'] as String?)?.trim() ?? 'en_attente',
      dateEncaissement: m['date_encaissement'] is Timestamp
          ? (m['date_encaissement'] as Timestamp).toDate()
          : null,
    );
  }
}

class RetraitLine {
  RetraitLine({required this.montant, required this.status, required this.date});
  final int montant;
  final String status; // a_payer | paye | rejete
  final DateTime? date;

  static RetraitLine fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return RetraitLine(
      montant: (m['montant'] as num?)?.toInt() ?? 0,
      status: (m['status'] as String?)?.trim() ?? 'a_payer',
      date: m['date'] is Timestamp ? (m['date'] as Timestamp).toDate() : null,
    );
  }
}

class HouseLite {
  HouseLite({
    required this.id,
    required this.quartier,
    required this.cite,
    required this.type,
    required this.locationType,
    required this.numBien,
    required this.active,
    required this.statutValidation,
    required this.image,
  });

  final String id;
  final String quartier;
  final String cite;
  final String type;
  final String locationType;
  final int? numBien;
  final bool active;
  final String statutValidation; // en_attente | validee | rejetee | supprimee
  final String? image;

  bool get enLigne => active && statutValidation == 'validee';
  bool get enValidation => statutValidation == 'en_attente';
  bool get rejetee => statutValidation == 'rejetee';

  String get titre {
    final n = numBien != null ? ' · #$numBien' : '';
    final lieu = [quartier, cite].where((e) => e.isNotEmpty).join(' — ');
    return lieu.isEmpty ? 'Logement$n' : '$lieu$n';
  }

  static HouseLite fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final imgs = (m['image'] as List?)?.whereType<String>().toList() ?? const [];
    return HouseLite(
      id: d.id,
      quartier: (m['quartier'] as String?)?.trim() ?? '',
      cite: (m['cite'] as String?)?.trim() ?? '',
      type: (m['types'] as String?)?.trim() ?? '',
      locationType: (m['locationtype'] as String?)?.trim() ?? '',
      numBien: (m['numbien'] as num?)?.toInt(),
      active: m['active'] == true,
      statutValidation: (m['statut_validation'] as String?)?.trim() ?? '',
      image: imgs.isNotEmpty ? imgs.first : null,
    );
  }
}

class ResaLite {
  ResaLite({
    required this.id,
    required this.type,
    required this.status,
    required this.accordHote,
    required this.clientNom,
    required this.prix,
    required this.dateDebut,
    required this.dateSorti,
    required this.dateCreated,
    required this.houseId,
  });

  final String id;
  final String type; // 'Reservation visite' | 'Reservation journalière' | ...
  final String status; // 'En attente' | 'Réservée' | 'Soldée' | 'Terminée' | 'Annulée'
  final String accordHote; // 'en_attente' | 'accepte' | 'refuse' | ''
  final String clientNom;
  final double? prix;
  final DateTime? dateDebut;
  final DateTime? dateSorti;
  final DateTime? dateCreated;
  final String? houseId;

  static const _accordables = {'Reservation visite', 'Reservation journalière'};
  static const _clos = {'Terminée', 'Annulée'};

  bool get demandeAccord =>
      accordHote == 'en_attente' && _accordables.contains(type);

  bool get aVenir {
    if (_clos.contains(status)) return false;
    final ref = dateSorti ?? dateDebut;
    return ref != null && ref.isAfter(DateTime.now());
  }

  /// Libellé court du type.
  String get typeCourt {
    switch (type) {
      case 'Reservation visite':
        return 'Visite';
      case 'Reservation journalière':
        return 'Journalier';
      case 'Reservation mensuelle':
        return 'Mensuel';
      case 'Reservation service':
        return 'Service';
      default:
        return type.replaceFirst('Reservation ', '');
    }
  }

  static ResaLite fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    final hr = m['HouseRef'];
    return ResaLite(
      id: d.id,
      type: (m['Types'] as String?)?.trim() ?? '',
      status: (m['Status'] as String?)?.trim() ?? '',
      accordHote: (m['accord_hote'] as String?)?.trim() ?? '',
      clientNom: (m['client_nom'] as String?)?.trim() ?? '',
      prix: (m['prix'] as num?)?.toDouble(),
      dateDebut: ts(m['dateDebut']),
      dateSorti: ts(m['dateSorti']),
      dateCreated: ts(m['datecreated']),
      houseId: hr is DocumentReference ? hr.id : null,
    );
  }
}
