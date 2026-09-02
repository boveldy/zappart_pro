import 'package:cloud_firestore/cloud_firestore.dart';

/// Immeuble / résidence : ce qui est **commun** à plusieurs logements du même
/// bâtiment (quartier, cité, adresse, position GPS, concierge). L'hôte le saisit
/// une fois, puis chaque annonce s'y rattache (`house.immeuble_ref`) et reprend
/// ces champs — ils restent **dénormalisés sur la maison** (aucun impact sur la
/// vue client / l'admin / le déménagement).
class Immeuble {
  Immeuble({
    required this.id,
    required this.nom,
    required this.quartier,
    required this.zone,
    required this.cite,
    required this.localisation,
    required this.geolocalisation,
    required this.conciergenom,
    required this.conciergenum,
    required this.conciergephoto,
  });

  final String id;
  final String nom;
  final String quartier;
  final String zone;
  final String cite;
  final String localisation;
  final String geolocalisation;
  final String conciergenom;
  final String conciergenum;
  final String conciergephoto;

  String get sousTitre => [
        if (quartier.isNotEmpty) quartier,
        if (cite.isNotEmpty) cite,
      ].join(' · ');

  static Immeuble fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    String s(String k) => (m[k] as String?)?.trim() ?? '';
    return Immeuble(
      id: d.id,
      nom: s('nom'),
      quartier: s('quartier'),
      zone: s('zone'),
      cite: s('cite'),
      localisation: s('localisation'),
      geolocalisation: s('geolocalisation'),
      conciergenom: s('conciergenom'),
      conciergenum: s('conciergenum'),
      conciergephoto: s('conciergephoto'),
    );
  }
}

class ImmeubleRepository {
  ImmeubleRepository(this.partenaireRef);
  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final _col = FirebaseFirestore.instance.collection('immeubles');

  Stream<List<Immeuble>> mine() => _col
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(Immeuble.fromDoc).toList()
        ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase())));

  Future<Immeuble?> one(String id) async {
    final d = await _col.doc(id).get();
    return d.exists ? Immeuble.fromDoc(d) : null;
  }

  /// Met à jour un immeuble. Le trigger backend `propager_immeuble` re-propage
  /// les champs modifiés sur les `house` rattachées (sans toucher au statut de
  /// validation).
  Future<void> update(
    String id, {
    required String nom,
    required String quartier,
    required String zone,
    required String cite,
    required String localisation,
    required String geolocalisation,
    required String conciergenom,
    required String conciergenum,
  }) =>
      _col.doc(id).update({
        'nom': nom.trim(),
        'quartier': quartier.trim(),
        'zone': zone,
        'cite': cite.trim(),
        'localisation': localisation.trim(),
        'geolocalisation': geolocalisation,
        'conciergenom': conciergenom.trim(),
        'conciergenum': conciergenum.trim(),
      });

  Future<void> delete(String id) => _col.doc(id).delete();

  /// Crée un immeuble et renvoie sa référence.
  Future<DocumentReference<Map<String, dynamic>>> create({
    required String nom,
    required String quartier,
    required String zone,
    required String cite,
    required String localisation,
    required String geolocalisation,
    required String conciergenom,
    required String conciergenum,
    required String conciergephoto,
  }) async {
    final ref = _col.doc();
    await ref.set({
      'nom': nom,
      'partenaire_ref': partenaireRef,
      'quartier': quartier,
      'zone': zone,
      'cite': cite,
      'localisation': localisation,
      'geolocalisation': geolocalisation,
      'conciergenom': conciergenom,
      'conciergenum': conciergenum,
      'conciergephoto': conciergephoto,
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref;
  }
}
