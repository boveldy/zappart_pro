import 'package:cloud_firestore/cloud_firestore.dart';

/// Propriétaire (bailleur) dont l'agence gère un ou plusieurs biens. Entité
/// légère, gérée par l'agence dans Zappart Pro — sert à lier les baux et à
/// consolider les relevés de gérance. Aucun compte / login (pas un portail).
class Proprietaire {
  Proprietaire({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.email,
    required this.note,
  });

  final String id;
  final String nom;
  final String telephone;
  final String email;
  final String note;

  String get sousTitre => [
        if (telephone.isNotEmpty) telephone,
        if (email.isNotEmpty) email,
      ].join(' · ');

  static Proprietaire fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    String s(String k) => (m[k] as String?)?.trim() ?? '';
    return Proprietaire(
      id: d.id,
      nom: s('nom'),
      telephone: s('telephone'),
      email: s('email'),
      note: s('note'),
    );
  }
}

class ProprietaireRepository {
  ProprietaireRepository(this.partenaireRef);
  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final _col = FirebaseFirestore.instance.collection('proprietaires');

  Stream<List<Proprietaire>> mine() => _col
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(Proprietaire.fromDoc).toList()
        ..sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase())));

  Future<Proprietaire?> one(String id) async {
    final d = await _col.doc(id).get();
    return d.exists ? Proprietaire.fromDoc(d) : null;
  }

  Future<DocumentReference<Map<String, dynamic>>> create({
    required String nom,
    String telephone = '',
    String email = '',
    String note = '',
  }) async {
    final ref = _col.doc();
    await ref.set({
      'nom': nom.trim(),
      'telephone': telephone.trim(),
      'email': email.trim(),
      'note': note.trim(),
      'partenaire_ref': partenaireRef,
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref;
  }

  Future<void> update(
    String id, {
    required String nom,
    required String telephone,
    required String email,
    required String note,
  }) =>
      _col.doc(id).update({
        'nom': nom.trim(),
        'telephone': telephone.trim(),
        'email': email.trim(),
        'note': note.trim(),
      });

  Future<void> delete(String id) => _col.doc(id).delete();
}
