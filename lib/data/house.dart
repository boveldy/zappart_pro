import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle complet d'un bien (`house`) — pour l'écran Parc + la fiche.
/// Champs alignés sur `HouseRecord` de l'app officielle.
class House {
  House({
    required this.id,
    required this.quartier,
    required this.cite,
    required this.zone,
    required this.type,
    required this.locationType,
    required this.prix,
    required this.prixJournee,
    required this.journeeActive,
    required this.numBien,
    required this.nbChambre,
    required this.nbBain,
    required this.nbSalon,
    required this.surface,
    required this.caution,
    required this.cautionMois,
    required this.comission,
    required this.images,
    required this.noteMoyenne,
    required this.nbAvis,
    required this.description,
    required this.comodites,
    required this.regles,
    required this.active,
    required this.statutValidation,
    required this.motifRejet,
    required this.soumisLe,
    required this.valideLe,
    required this.boostActif,
    required this.icalUrls,
    required this.immeubleRefId,
    required this.createdAt,
  });

  final String id;
  final String quartier;
  final String cite;
  final String zone;
  final String type;
  final String locationType; // 'Journalier' | 'Mensuel'
  final double? prix;
  final double? prixJournee;
  final bool journeeActive;
  final int? numBien;
  final int? nbChambre;
  final int? nbBain;
  final double? nbSalon;
  final int? surface;
  final double? caution;
  final int? cautionMois;
  final double? comission;
  final List<String> images;
  final double? noteMoyenne;
  final int? nbAvis;
  final String description;
  final List<String> comodites;
  final List<String> regles;
  final bool active;
  final String statutValidation; // brouillon|en_attente|validee|rejetee|supprimee
  final String motifRejet;
  final DateTime? soumisLe;
  final DateTime? valideLe;
  final bool boostActif;
  final List<String> icalUrls;
  final String? immeubleRefId;
  final DateTime? createdAt;

  bool get prive => statutValidation == 'prive';
  bool get enLigne => active && statutValidation == 'validee';
  bool get horsLigne => !active && statutValidation == 'validee';
  bool get enValidation => statutValidation == 'en_attente';
  bool get rejetee => statutValidation == 'rejetee';
  bool get brouillon => statutValidation == 'brouillon';
  bool get archivee => statutValidation == 'supprimee';

  /// Libellé d'état affiché.
  ({String label, String tone}) get badge {
    if (prive) return (label: 'Loué · privé', tone: 'muted');
    if (enLigne) return (label: 'En ligne', tone: 'ok');
    if (horsLigne) return (label: 'Hors ligne', tone: 'muted');
    if (enValidation) return (label: 'En validation', tone: 'wait');
    if (rejetee) return (label: 'Rejetée', tone: 'danger');
    if (brouillon) return (label: 'Brouillon', tone: 'muted');
    return (label: 'Archivée', tone: 'muted');
  }

  String get titre {
    final lieu = [quartier, cite].where((e) => e.isNotEmpty).join(' — ');
    final n = numBien != null ? ' · #$numBien' : '';
    return lieu.isEmpty ? 'Logement$n' : '$lieu$n';
  }

  /// Prix affiché selon le type (journalier ou mensuel).
  double? get prixAffiche =>
      locationType == 'Journalier' ? (prixJournee ?? prix) : prix;

  String get uniteLabel => locationType == 'Journalier' ? '/ nuit' : '/ mois';

  static House fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    List<String> strs(dynamic v) =>
        (v as List?)?.whereType<String>().toList() ?? const [];
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    final imm = m['immeuble_ref'];
    return House(
      id: d.id,
      quartier: (m['quartier'] as String?)?.trim() ?? '',
      cite: (m['cite'] as String?)?.trim() ?? '',
      zone: (m['zone'] as String?)?.trim() ?? '',
      type: (m['types'] as String?)?.trim() ?? '',
      locationType: (m['locationtype'] as String?)?.trim() ?? '',
      prix: (m['prix'] as num?)?.toDouble(),
      prixJournee: (m['prix_journee'] as num?)?.toDouble(),
      journeeActive: m['journee_active'] == true,
      numBien: (m['numbien'] as num?)?.toInt(),
      nbChambre: (m['nbchambre'] as num?)?.toInt(),
      nbBain: (m['nbbain'] as num?)?.toInt(),
      nbSalon: (m['nbsalon'] as num?)?.toDouble(),
      surface: (m['surface'] as num?)?.toInt(),
      caution: (m['caution'] as num?)?.toDouble(),
      cautionMois: (m['caution_mois'] as num?)?.toInt(),
      comission: (m['comission'] as num?)?.toDouble(),
      images: strs(m['image']),
      noteMoyenne: (m['note_moyenne'] as num?)?.toDouble(),
      nbAvis: (m['nb_avis'] as num?)?.toInt(),
      description: (m['description'] as String?)?.trim() ?? '',
      comodites: strs(m['Comodite']),
      regles: strs(m['regleMaison']),
      active: m['active'] == true,
      statutValidation: (m['statut_validation'] as String?)?.trim() ?? '',
      motifRejet: (m['motif_rejet'] as String?)?.trim() ?? '',
      soumisLe: ts(m['soumis_le']),
      valideLe: ts(m['valide_le']),
      boostActif: m['boost_actif'] == true,
      icalUrls: strs(m['ical_urls']),
      immeubleRefId: imm is DocumentReference ? imm.id : null,
      createdAt: ts(m['created_at']),
    );
  }
}

/// Requêtes + écritures sur le parc d'un partenaire.
/// Les règles Firestore autorisent l'hôte à basculer `active` seul sur une
/// annonce `validee`, et à archiver (`statut_validation: supprimee`).
class HouseRepository {
  HouseRepository(this.partenaireRef);
  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final _col = FirebaseFirestore.instance.collection('house');

  Stream<List<House>> mine() => _col
      .where('partenaireId', isEqualTo: partenaireRef)
      .limit(500)
      .snapshots()
      .map((s) => s.docs
          .map(House.fromDoc)
          .where((h) => !h.archivee)
          .toList());

  /// Les biens archivés du partenaire, plus récent d'abord.
  Stream<List<House>> archives() => _col
      .where('partenaireId', isEqualTo: partenaireRef)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map(House.fromDoc).where((h) => h.archivee).toList()
        ..sort((a, b) =>
            (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000))));

  Stream<House?> one(String id) =>
      _col.doc(id).snapshots().map((d) => d.exists ? House.fromDoc(d) : null);

  Future<void> setActive(String id, bool value) =>
      _col.doc(id).update({'active': value});

  Future<void> archive(String id) => _col.doc(id).update({
        'statut_validation': 'supprimee',
        'active': false,
        'supprimee_le': FieldValue.serverTimestamp(),
      });

  /// Sort un bien des archives → repart en file de validation (jamais direct en
  /// ligne).
  Future<void> restore(String id) => _col.doc(id).update({
        'statut_validation': 'en_attente',
        'active': false,
        'motif_rejet': '',
        'soumis_le': FieldValue.serverTimestamp(),
        'supprimee_le': FieldValue.delete(),
      });

  /// Un bail `actif` est-il rattaché à ce bien ? La règle Firestore impose de
  /// requêter sur `partenaire_ref` (pas `house_ref`) → on filtre côté client.
  Future<bool> aUnBailActif(String houseId) async {
    final snap = await FirebaseFirestore.instance
        .collection('baux')
        .where('partenaire_ref', isEqualTo: partenaireRef)
        .get();
    return snap.docs.any((d) {
      final m = d.data();
      final hr = m['house_ref'];
      final id = hr is DocumentReference ? hr.id : null;
      return id == houseId && (m['statut'] ?? 'actif') == 'actif';
    });
  }
}
