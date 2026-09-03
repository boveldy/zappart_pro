import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/journal_pro.dart';
import '../data/permissions.dart';
import 'abonnement.dart';

/// État d'accès d'un compte à Zappart Pro.
enum ProAccess {
  /// Pas connecté.
  loggedOut,

  /// Connecté mais le doc `users/{uid}` n'a pas encore chargé.
  loading,

  /// Connecté, aucun `partenaire_ref` → aucune fiche partenaire : il faut
  /// remplir la demande d'inscription.
  notPartner,

  /// Connecté, aucune fiche partenaire À SOI mais une invitation d'équipe
  /// ouverte porte cet e-mail → écran « Rejoindre {agence} ».
  invitePending,

  /// Connecté, fiche partenaire créée mais pas encore activée par l'admin
  /// (`actif: false` → `est_hote`/`est_prestataire` encore faux). Demande en
  /// cours de validation, ou fiche archivée.
  pending,

  /// Connecté + fiche partenaire liée ET activée, OU membre d'équipe actif
  /// (`membres_pro`) → accès autorisé.
  partner,
}

/// Source de vérité de l'authentification web. Écoute `FirebaseAuth` puis,
/// pour un utilisateur connecté, le document `users/{uid}` pour en extraire
/// `partenaire_ref` (le même champ que l'app officielle — cf.
/// `users_record.dart:210`). Rôle `admin` : hors périmètre semaine 1, on
/// lira `users.admin` plus tard.
class AuthService extends ChangeNotifier {
  AuthService() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  final _db = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _partDocSub;

  User? _user;
  Map<String, dynamic>? _userDoc;
  bool _userDocLoaded = false;
  Map<String, dynamic>? _partDoc;
  String? _partDocPath;

  // ── Équipe (multi-utilisateur) ────────────────────────────────────────────
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _membreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _inviteSub;
  Map<String, dynamic>? _membreDoc;
  bool _membreDocLoaded = false;
  QueryDocumentSnapshot<Map<String, dynamic>>? _inviteDoc;
  bool _bootstrapTried = false;

  User? get user => _user;

  /// Fiche partenaire pointée par `users.partenaire_ref` (compte hôte
  /// « propriétaire » du compte). `null` pour un employé invité.
  DocumentReference<Map<String, dynamic>>? get partenaireRef {
    final raw = _userDoc?['partenaire_ref'];
    return raw is DocumentReference<Map<String, dynamic>> ? raw : null;
  }

  bool get estHote => _userDoc?['est_hote'] == true;
  bool get estPrestataire => _userDoc?['est_prestataire'] == true;

  // ── Rôle & permissions du membre connecté ─────────────────────────────────

  /// Doc `membres_pro/{uid}` en statut `actif`, sinon `null`.
  bool get isMembreActif => _membreDoc?['statut'] == 'actif';

  /// Rôle du membre connecté. `admin` par défaut pour un hôte historique
  /// (compte mono-utilisateur : tous les droits).
  ProRole get membreRole => isMembreActif
      ? ProRole.fromCode(_membreDoc?['role'] as String?)
      : ProRole.admin;

  /// Fiche agence effective : celle du membre actif, sinon celle de l'hôte.
  DocumentReference<Map<String, dynamic>>? get agenceRef {
    if (isMembreActif) {
      final raw = _membreDoc?['partenaire_ref'];
      if (raw is DocumentReference<Map<String, dynamic>>) return raw;
    }
    return partenaireRef;
  }

  /// Permissions effectives. Membre actif → sa map résolue ; hôte historique
  /// sans `membres_pro` → tous les droits (aucune régression) ; sinon aucun.
  Map<String, bool> get perms {
    if (isMembreActif) {
      final raw = (_membreDoc?['permissions'] as Map?) ?? const {};
      return {for (final k in ProPerm.all) k: raw[k] == true};
    }
    if (estHote || estPrestataire) {
      return {for (final k in ProPerm.all) k: true};
    }
    return {for (final k in ProPerm.all) k: false};
  }

  /// Le membre connecté détient-il la permission `key` ?
  bool can(String key) => perms[key] == true;

  /// A accès à l'espace de gérance (hôte historique OU employé d'équipe actif).
  /// Un prestataire pur reste `false`.
  bool get aGerance => isMembreActif || estHote;

  /// Invitation d'équipe ouverte pour cet e-mail (écran « Rejoindre »).
  bool get hasInvitePending => _inviteDoc != null;
  String get inviteAgenceNom =>
      (_inviteDoc?.data()['agence_nom'] as String?)?.trim() ?? 'une agence';
  String get inviteRoleLabel =>
      ProRole.fromCode(_inviteDoc?.data()['role'] as String?).label;

  /// Abonnement du partenaire (champs `abo_*` sur la fiche `Partenaires`).
  /// « Découverte » tant que la fiche n'est pas chargée.
  Abonnement get abonnement => Abonnement.fromPartenaire(_partDoc);
  Map<String, dynamic>? get partenaireDoc => _partDoc;

  /// Abonnement payant expiré depuis > 30 j → la gérance passe en consultation
  /// seule (aucune écriture : loyers, dépenses, prolongation, clôture…). Tant
  /// que la fiche partenaire n'est pas chargée, on ne bloque rien.
  bool get lectureSeule => _partDoc != null && abonnement.lectureSeule;

  String get displayName =>
      (_userDoc?['display_name'] as String?)?.trim().isNotEmpty == true
          ? _userDoc!['display_name'] as String
          : (_user?.email ?? '');

  ProAccess get access {
    if (_user == null) return ProAccess.loggedOut;
    if (!_userDocLoaded || !_membreDocLoaded) return ProAccess.loading;

    // Employé d'équipe actif (`membres_pro`) → accès, quel que soit `est_hote`.
    if (isMembreActif) return ProAccess.partner;

    if (partenaireRef == null) {
      // Pas de fiche à soi : soit on a été invité dans une agence, soit rien.
      return hasInvitePending ? ProAccess.invitePending : ProAccess.notPartner;
    }
    // `est_hote` / `est_prestataire` ne passent à true que quand l'admin active
    // la fiche (`actif: true`) — cf. trigger `partenaire_link.py`. Tant que
    // c'est faux, la demande est en cours de validation (ou la fiche a été
    // archivée).
    if (!estHote && !estPrestataire) return ProAccess.pending;
    return ProAccess.partner;
  }

  String get email => _user?.email ?? '';

  /// Crée la demande de partenariat en self-service (web). Écrit directement
  /// dans Firestore, comme le wizard mobile (`devenir_partenaire_model.dart`) :
  /// fiche `Partenaires` toujours `statut_demande: 'en_attente'` /
  /// `actif: false`, avec `user_ref` vers le compte connecté (c'est ce lien que
  /// le trigger `link_user_from_partenaire` suit pour poser
  /// `users.partenaire_ref`). L'admin valide ensuite dans zappart_admin
  /// (`actif: true` → accès complet).
  ///
  /// Zappart Pro = logiciel de gérance → uniquement des hôtes
  /// (`type_activite: 'hote'`). Les prestataires de services passent par le
  /// wizard mobile / l'admin, pas par cette inscription web.
  ///
  /// Retourne `null` si succès, sinon un message d'erreur lisible.
  Future<String?> submitPartenaireRequest({
    required String typePartenaire, // 'Agence' | 'Gérant' | 'Propriétaire' | ...
    required String nom,
    required String prenom,
    String nomAgence = '',
    required String telephone,
    required String ville,
    int nombreBiens = 1,
  }) async {
    final u = _user;
    if (u == null) return 'Votre session a expiré. Reconnectez-vous.';
    try {
      final userRef = _db.collection('users').doc(u.uid);
      // S'assure que le profil existe (compte Google tout neuf sur le web).
      await userRef.set({
        if ((u.email ?? '').isNotEmpty) 'email': u.email,
        if ((u.displayName ?? '').isNotEmpty) 'display_name': u.displayName,
      }, SetOptions(merge: true));

      await _db.collection('Partenaires').add(<String, dynamic>{
        'typepartenaire': typePartenaire,
        'nom': nom.trim(),
        'prenom': prenom.trim(),
        if (nomAgence.trim().isNotEmpty) 'nomAgence': nomAgence.trim(),
        'telephone': telephone.trim(),
        if (email.isNotEmpty) 'email': email.trim(),
        'localisationTexte': ville.trim(),
        'nombreBiens': nombreBiens,
        'type_activite': 'hote',
        'user_ref': userRef,
        'statut_demande': 'en_attente',
        'actif': false,
        'canal': 'web',
        'createdDate': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Demande refusée par le serveur. Reconnectez-vous et réessayez.';
      }
      return 'Erreur (${e.code}). Vérifiez votre connexion et réessayez.';
    } catch (_) {
      return 'Une erreur est survenue. Vérifiez votre connexion et réessayez.';
    }
  }

  void _onAuthChanged(User? u) {
    _user = u;
    _userDoc = null;
    _userDocLoaded = false;
    _userDocSub?.cancel();
    _userDocSub = null;
    _partDocSub?.cancel();
    _partDocSub = null;
    _partDoc = null;
    _partDocPath = null;
    _membreSub?.cancel();
    _membreSub = null;
    _membreDoc = null;
    _membreDocLoaded = false;
    _inviteSub?.cancel();
    _inviteSub = null;
    _inviteDoc = null;
    _bootstrapTried = false;

    if (u != null) {
      _userDocSub = _db
          .collection('users')
          .doc(u.uid)
          .snapshots()
          .listen((snap) {
        _userDoc = snap.data();
        _userDocLoaded = true;
        Journal.configure(uid: u.uid, nom: displayName);
        _syncPartenaireSub();
        _maybeBootstrapMembre();
        notifyListeners();
      }, onError: (_) {
        _userDocLoaded = true;
        notifyListeners();
      });

      // Rôle & permissions de l'employé (doc indexé par l'uid).
      _membreSub = _db
          .collection('membres_pro')
          .doc(u.uid)
          .snapshots()
          .listen((snap) {
        _membreDoc = snap.data();
        _membreDocLoaded = true;
        _syncPartenaireSub();
        _maybeBootstrapMembre();
        notifyListeners();
      }, onError: (_) {
        _membreDocLoaded = true;
        notifyListeners();
      });

      // Invitation d'équipe ouverte pour cet e-mail (écran « Rejoindre »).
      // Filtre mono-champ (pas d'index composite) ; `statut` filtré côté client.
      final mail = (u.email ?? '').trim().toLowerCase();
      if (mail.isNotEmpty) {
        _inviteSub = _db
            .collection('invitations_pro')
            .where('email', isEqualTo: mail)
            .snapshots()
            .listen((snap) {
          final open = snap.docs
              .where((d) => d.data()['statut'] == 'ouverte')
              .toList();
          _inviteDoc = open.isEmpty ? null : open.first;
          notifyListeners();
        }, onError: (_) {});
      }
    }
    notifyListeners();
  }

  /// Auto-réparation : un hôte historique (`est_hote`, fiche à lui) sans
  /// `membres_pro` se crée sa fiche `admin` — pour que rôles & journal
  /// fonctionnent sans migration préalable. Une seule tentative par session.
  Future<void> _maybeBootstrapMembre() async {
    if (_bootstrapTried) return;
    final u = _user;
    if (u == null || !_userDocLoaded || !_membreDocLoaded) return;
    if (_membreDoc != null) return; // déjà membre
    if (!estHote) return; // employé non lié / demande en attente : rien à faire
    final pref = partenaireRef;
    if (pref == null) return;
    _bootstrapTried = true;
    try {
      await _db.collection('membres_pro').doc(u.uid).set(<String, dynamic>{
        'partenaire_ref': pref,
        'role': ProRole.admin.code,
        'statut': 'actif',
        'email': (u.email ?? '').trim().toLowerCase(),
        'nom': displayName,
        'permissions': resolvePermissions(ProRole.admin, null),
        'permissions_override': <String, dynamic>{},
        'created_at': FieldValue.serverTimestamp(),
        'joined_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _bootstrapTried = false; // on retentera au prochain changement
    }
  }

  /// L'invité rejoint l'agence : crée son `membres_pro/{uid}` à partir de
  /// l'invitation ouverte et marque celle-ci acceptée. Retourne `null` si
  /// succès, sinon un message lisible.
  Future<String?> acceptInvitation() async {
    final u = _user;
    final inv = _inviteDoc;
    if (u == null) return 'Votre session a expiré. Reconnectez-vous.';
    if (inv == null) return 'Aucune invitation en attente.';
    final data = inv.data();
    try {
      final batch = _db.batch()
        ..set(_db.collection('membres_pro').doc(u.uid), <String, dynamic>{
          'partenaire_ref': data['partenaire_ref'],
          'role': data['role'],
          'statut': 'actif',
          'email': (u.email ?? '').trim().toLowerCase(),
          'nom': displayName,
          'permissions': data['permissions'] ?? <String, dynamic>{},
          'permissions_override': data['permissions_override'] ?? <String, dynamic>{},
          'invitation_id': inv.id,
          'created_at': FieldValue.serverTimestamp(),
          'joined_at': FieldValue.serverTimestamp(),
        })
        ..update(inv.reference, <String, dynamic>{
          'statut': 'acceptee',
          'accepte_le': FieldValue.serverTimestamp(),
        });
      await batch.commit();
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return 'Invitation refusée par le serveur. Elle a peut-être été annulée.';
      }
      return 'Erreur (${e.code}). Réessayez.';
    } catch (_) {
      return 'Une erreur est survenue. Réessayez.';
    }
  }

  /// (Re)abonne au doc `Partenaires` de l'agence effective (`agenceRef` : la
  /// fiche de l'employé si membre, sinon celle de l'hôte) — pour lire
  /// l'abonnement (`abo_*`) en temps réel. Ne resouscrit que si la référence
  /// a changé.
  void _syncPartenaireSub() {
    final ref = agenceRef;
    if (ref?.path == _partDocPath) return;
    _partDocSub?.cancel();
    _partDocSub = null;
    _partDocPath = ref?.path;
    _partDoc = null;
    if (ref == null) return;
    _partDocSub = ref.snapshots().listen((snap) {
      _partDoc = snap.data();
      notifyListeners();
    }, onError: (_) {});
  }

  Future<void> signInWithEmail(String email, String password) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Connexion Google — via popup web. Même provider que l'app mobile → même
  /// `uid`, donc le `partenaire_ref` déjà posé par le wizard reste valable.
  Future<void> signInWithGoogle() {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});
    return FirebaseAuth.instance.signInWithPopup(provider);
  }

  /// Connexion Apple — nécessite la config Service ID côté portail Apple +
  /// Firebase. Tant qu'elle n'est pas faite, le bouton renverra une erreur
  /// explicite (gérée par l'écran de connexion).
  Future<void> signInWithApple() {
    final provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    return FirebaseAuth.instance.signInWithPopup(provider);
  }

  Future<void> sendPasswordReset(String email) {
    return FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  @override
  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
    _partDocSub?.cancel();
    _membreSub?.cancel();
    _inviteSub?.cancel();
    super.dispose();
  }
}
