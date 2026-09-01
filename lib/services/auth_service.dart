import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// État d'accès d'un compte à Zappart Pro.
enum ProAccess {
  /// Pas connecté.
  loggedOut,

  /// Connecté mais le doc `users/{uid}` n'a pas encore chargé.
  loading,

  /// Connecté, aucun `partenaire_ref` → aucune fiche partenaire : il faut
  /// remplir la demande d'inscription.
  notPartner,

  /// Connecté, fiche partenaire créée mais pas encore activée par l'admin
  /// (`actif: false` → `est_hote`/`est_prestataire` encore faux). Demande en
  /// cours de validation, ou fiche archivée.
  pending,

  /// Connecté + fiche partenaire liée ET activée → accès autorisé.
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

  User? _user;
  Map<String, dynamic>? _userDoc;
  bool _userDocLoaded = false;

  User? get user => _user;
  DocumentReference<Map<String, dynamic>>? get partenaireRef {
    final raw = _userDoc?['partenaire_ref'];
    return raw is DocumentReference<Map<String, dynamic>> ? raw : null;
  }

  bool get estHote => _userDoc?['est_hote'] == true;
  bool get estPrestataire => _userDoc?['est_prestataire'] == true;

  String get displayName =>
      (_userDoc?['display_name'] as String?)?.trim().isNotEmpty == true
          ? _userDoc!['display_name'] as String
          : (_user?.email ?? '');

  ProAccess get access {
    if (_user == null) return ProAccess.loggedOut;
    if (!_userDocLoaded) return ProAccess.loading;
    if (partenaireRef == null) return ProAccess.notPartner;
    // `est_hote` / `est_prestataire` ne passent à true que quand l'admin active
    // la fiche (`actif: true`) — cf. trigger `partenaire_link.py`. Tant que
    // c'est faux, la demande est en cours de validation (ou la fiche a été
    // archivée).
    if (!estHote && !estPrestataire) return ProAccess.pending;
    return ProAccess.partner;
  }

  String get email => _user?.email ?? '';

  /// Crée la demande de partenariat en self-service (web). Écrit directement
  /// dans Firestore, exactement comme le wizard mobile
  /// (`devenir_partenaire_model.dart`) : fiche `Partenaires` toujours
  /// `statut_demande: 'en_attente'` / `actif: false`, avec `user_ref` vers le
  /// compte connecté (c'est ce lien que le trigger `link_user_from_partenaire`
  /// suit pour poser `users.partenaire_ref`). L'admin valide ensuite dans
  /// zappart_admin (`actif: true` → accès complet).
  ///
  /// Retourne `null` si succès, sinon un message d'erreur lisible.
  Future<String?> submitPartenaireRequest({
    required bool service,
    required String typePartenaire, // 'Agence' | 'Gérant' | ... ou 'Prestataire'
    String? typeService, // code métier si service (Demenageur, Plombier, …)
    required String nom,
    required String prenom,
    String nomAgence = '',
    required String telephone,
    required String ville,
    int nombreBiens = 1,
    int nombreAgent = 1,
    String descriptionCourte = '',
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
        'typepartenaire': service ? 'Prestataire' : typePartenaire,
        if (service && (typeService ?? '').isNotEmpty) 'typeservice': typeService,
        'nom': nom.trim(),
        'prenom': prenom.trim(),
        if (nomAgence.trim().isNotEmpty) 'nomAgence': nomAgence.trim(),
        'telephone': telephone.trim(),
        if (email.isNotEmpty) 'email': email.trim(),
        'localisationTexte': ville.trim(),
        if (!service) 'nombreBiens': nombreBiens,
        if (service) 'descriptionCourte': descriptionCourte.trim(),
        if (service && nombreAgent > 1) 'nombreAgent': nombreAgent,
        'type_activite': service ? 'service' : 'hote',
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

    if (u != null) {
      _userDocSub = _db
          .collection('users')
          .doc(u.uid)
          .snapshots()
          .listen((snap) {
        _userDoc = snap.data();
        _userDocLoaded = true;
        notifyListeners();
      }, onError: (_) {
        _userDocLoaded = true;
        notifyListeners();
      });
    }
    notifyListeners();
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
    super.dispose();
  }
}
