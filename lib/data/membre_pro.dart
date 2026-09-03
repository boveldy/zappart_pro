import 'package:cloud_firestore/cloud_firestore.dart';

import 'journal_pro.dart';
import 'permissions.dart';

/// Un membre de l'équipe d'une agence — doc `membres_pro/{uid}`.
class MembrePro {
  MembrePro({
    required this.uid,
    required this.nom,
    required this.email,
    required this.role,
    required this.statut,
    required this.permissions,
    required this.override,
    this.joinedAt,
  });

  final String uid;
  final String nom;
  final String email;
  final ProRole role;
  final String statut; // 'actif' | 'revoque' (les invites vivent ailleurs)
  final Map<String, bool> permissions;
  final Map<String, dynamic> override;
  final DateTime? joinedAt;

  bool get actif => statut == 'actif';

  static MembrePro fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final rawPerms = (m['permissions'] as Map?) ?? const {};
    return MembrePro(
      uid: d.id,
      nom: (m['nom'] as String?)?.trim() ?? '',
      email: (m['email'] as String?)?.trim() ?? '',
      role: ProRole.fromCode(m['role'] as String?),
      statut: (m['statut'] as String?) ?? 'actif',
      permissions: {for (final k in ProPerm.all) k: rawPerms[k] == true},
      override: Map<String, dynamic>.from(
          (m['permissions_override'] as Map?) ?? const {}),
      joinedAt: (m['joined_at'] as Timestamp?)?.toDate(),
    );
  }
}

/// Une invitation en attente — doc `invitations_pro/{id}`.
class InvitationPro {
  InvitationPro({
    required this.id,
    required this.email,
    required this.role,
    required this.statut,
    this.createdAt,
  });

  final String id;
  final String email;
  final ProRole role;
  final String statut; // 'ouverte' | 'acceptee' | 'annulee'
  final DateTime? createdAt;

  static InvitationPro fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return InvitationPro(
      id: d.id,
      email: (m['email'] as String?)?.trim() ?? '',
      role: ProRole.fromCode(m['role'] as String?),
      statut: (m['statut'] as String?) ?? 'ouverte',
      createdAt: (m['created_at'] as Timestamp?)?.toDate(),
    );
  }
}

/// Accès Firestore à l'équipe d'UNE agence (`agenceRef`). Toutes les requêtes
/// filtrent sur `partenaire_ref` (= le champ testé par les règles).
class MembreRepository {
  MembreRepository(this.agenceRef, {required this.agenceNom, required this.parUid, required this.parNom});

  final DocumentReference<Map<String, dynamic>> agenceRef;
  final String agenceNom;
  final String parUid;
  final String parNom;

  final _db = FirebaseFirestore.instance;

  Stream<List<MembrePro>> membres() => _db
      .collection('membres_pro')
      .where('partenaire_ref', isEqualTo: agenceRef)
      .snapshots()
      .map((s) => s.docs.map(MembrePro.fromDoc).toList()
        ..sort((a, b) {
          if (a.actif != b.actif) return a.actif ? -1 : 1;
          return a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
        }));

  Stream<List<InvitationPro>> invitationsOuvertes() => _db
      .collection('invitations_pro')
      .where('partenaire_ref', isEqualTo: agenceRef)
      .snapshots()
      .map((s) => s.docs
          .map(InvitationPro.fromDoc)
          .where((i) => i.statut == 'ouverte')
          .toList()
        ..sort((a, b) => a.email.compareTo(b.email)));

  Future<void> _log(String action, String libelle) => Journal.log(
        agenceRef: agenceRef,
        action: action,
        cibleType: 'membre',
        cibleLibelle: libelle,
      );

  /// Crée une invitation. `permissions` est résolue ici (préréglage du rôle).
  Future<void> inviter(String email, ProRole role) async {
    await _db.collection('invitations_pro').add(<String, dynamic>{
      'email': email.trim().toLowerCase(),
      'agence_nom': agenceNom,
      'partenaire_ref': agenceRef,
      'role': role.code,
      'permissions': resolvePermissions(role, null),
      'permissions_override': <String, dynamic>{},
      'statut': 'ouverte',
      'invite_par': parUid,
      'invite_par_nom': parNom,
      'created_at': FieldValue.serverTimestamp(),
    });
    await _log('membre.invite', '${email.trim().toLowerCase()} · ${role.label}');
  }

  Future<void> annulerInvitation(String id, {String email = ''}) async {
    await _db
        .collection('invitations_pro')
        .doc(id)
        .update(<String, dynamic>{'statut': 'annulee'});
    await _log('membre.invitation_annulee', email);
  }

  /// Enregistre rôle + surcharges d'un membre en une écriture ; `permissions`
  /// (map lue par les règles + l'UI) est recalculée ici.
  Future<void> enregistrer(
    MembrePro m,
    ProRole role,
    Map<String, dynamic> override,
  ) async {
    await _db.collection('membres_pro').doc(m.uid).update(<String, dynamic>{
      'role': role.code,
      'permissions_override': override,
      'permissions': resolvePermissions(role, override),
    });
    final libelle = m.nom.isEmpty ? m.email : m.nom;
    if (m.role != role) {
      await _log('membre.role_modifie',
          '$libelle : ${m.role.label} → ${role.label}');
    } else {
      await _log('membre.role_modifie', '$libelle : permissions ajustées');
    }
  }

  /// Coche / décoche une permission surchargeable pour un membre.
  Future<void> definirPermission(MembrePro m, String cle, bool valeur) {
    final override = Map<String, dynamic>.from(m.override)..[cle] = valeur;
    return _db.collection('membres_pro').doc(m.uid).update(<String, dynamic>{
      'permissions_override': override,
      'permissions': resolvePermissions(m.role, override),
    });
  }

  /// Remet une permission sur la valeur du préréglage (retire la surcharge).
  Future<void> reinitPermission(MembrePro m, String cle) {
    final override = Map<String, dynamic>.from(m.override)..remove(cle);
    return _db.collection('membres_pro').doc(m.uid).update(<String, dynamic>{
      'permissions_override': override,
      'permissions': resolvePermissions(m.role, override),
    });
  }

  Future<void> revoquer(MembrePro m) async {
    await _db
        .collection('membres_pro')
        .doc(m.uid)
        .update(<String, dynamic>{'statut': 'revoque'});
    await _log('membre.revoque', m.nom.isEmpty ? m.email : m.nom);
  }

  Future<void> reactiver(MembrePro m) async {
    await _db
        .collection('membres_pro')
        .doc(m.uid)
        .update(<String, dynamic>{'statut': 'actif'});
    await _log('membre.reactive', m.nom.isEmpty ? m.email : m.nom);
  }
}
