import 'package:cloud_firestore/cloud_firestore.dart';

/// Journal d'activité d'une agence (`journal_pro`) — qui a fait quoi, quand.
///
/// Append-only (les règles interdisent update/delete). Écrit en « best effort »
/// juste après l'action : si l'écriture du journal échoue, l'action reste faite
/// (limite assumée V1 — l'inviolabilité totale demanderait de passer toute la
/// gérance par des Cloud Functions).
///
/// [configure] est appelé une fois par `AuthService` dès que l'identité du
/// membre est connue.
class Journal {
  static String _uid = '';
  static String _nom = '';

  static void configure({required String uid, required String nom}) {
    _uid = uid;
    _nom = nom;
  }

  static Future<void> log({
    required DocumentReference<Map<String, dynamic>> agenceRef,
    required String action,
    required String cibleType,
    required String cibleLibelle,
    DocumentReference<Map<String, dynamic>>? cibleRef,
    num? montant,
    Map<String, dynamic>? detail,
  }) async {
    if (_uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('journal_pro')
          .add(<String, dynamic>{
        'partenaire_ref': agenceRef,
        'acteur_uid': _uid,
        'acteur_nom': _nom,
        'action': action,
        'cible_type': cibleType,
        'cible_libelle': cibleLibelle,
        if (cibleRef != null) 'cible_ref': cibleRef,
        if (montant != null) 'montant': montant,
        if (detail != null) 'detail': detail,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // best effort
    }
  }

  static Stream<List<JournalEntry>> stream(
    DocumentReference<Map<String, dynamic>> agenceRef, {
    int limit = 200,
  }) =>
      FirebaseFirestore.instance
          .collection('journal_pro')
          .where('partenaire_ref', isEqualTo: agenceRef)
          .orderBy('created_at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(JournalEntry.fromDoc).toList());
}

class JournalEntry {
  JournalEntry({
    required this.id,
    required this.acteurNom,
    required this.action,
    required this.cibleType,
    required this.cibleLibelle,
    this.montant,
    this.date,
  });

  final String id;
  final String acteurNom;
  final String action;
  final String cibleType;
  final String cibleLibelle;
  final num? montant;
  final DateTime? date;

  static JournalEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return JournalEntry(
      id: d.id,
      acteurNom: (m['acteur_nom'] as String?)?.trim() ?? 'Quelqu\'un',
      action: (m['action'] as String?) ?? '',
      cibleType: (m['cible_type'] as String?) ?? '',
      cibleLibelle: (m['cible_libelle'] as String?) ?? '',
      montant: m['montant'] as num?,
      date: (m['created_at'] as Timestamp?)?.toDate(),
    );
  }

  /// Libellé lisible de l'action.
  String get actionLabel => _actionLabels[action] ?? action;

  static const _actionLabels = <String, String>{
    'bail.cree': 'a créé un bail',
    'bail.prolonge': 'a prolongé un bail',
    'bail.cloture': 'a clôturé un bail',
    'bail.supprime': 'a supprimé un bail (créé par erreur)',
    'echeance.payee': 'a marqué un loyer payé',
    'echeance.annulee': 'a annulé une échéance',
    'signalement.valide': 'a confirmé un paiement déclaré',
    'signalement.rejete': 'a rejeté un paiement déclaré',
    'depense.ajoutee': 'a ajouté une dépense',
    'depense.supprimee': 'a supprimé une dépense',
    'encaissement.change': 'a changé le mode d\'encaissement',
    'bien.cree': 'a créé une annonce',
    'bien.modifie': 'a modifié une annonce',
    'bien.publie': 'a (re)mis une annonce en ligne',
    'bien.retire': 'a retiré une annonce',
    'bien.archive': 'a archivé un bien',
    'proprietaire.cree': 'a ajouté un propriétaire',
    'proprietaire.modifie': 'a modifié un propriétaire',
    'proprietaire.supprime': 'a supprimé un propriétaire',
    'immeuble.cree': 'a créé un immeuble',
    'immeuble.modifie': 'a modifié un immeuble',
    'immeuble.supprime': 'a supprimé un immeuble',
    'membre.invite': 'a invité un collaborateur',
    'membre.invitation_annulee': 'a annulé une invitation',
    'membre.role_modifie': 'a modifié un rôle',
    'membre.revoque': 'a révoqué un accès',
    'membre.reactive': 'a réactivé un accès',
  };
}
