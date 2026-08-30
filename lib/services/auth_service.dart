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

  /// Connecté, aucun `partenaire_ref` → compte non habilité (particulier, ou
  /// fiche partenaire pas encore liée par le trigger backend).
  notPartner,

  /// Connecté + fiche partenaire liée → accès autorisé.
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

  String get displayName =>
      (_userDoc?['display_name'] as String?)?.trim().isNotEmpty == true
          ? _userDoc!['display_name'] as String
          : (_user?.email ?? '');

  ProAccess get access {
    if (_user == null) return ProAccess.loggedOut;
    if (!_userDocLoaded) return ProAccess.loading;
    return partenaireRef != null ? ProAccess.partner : ProAccess.notPartner;
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
