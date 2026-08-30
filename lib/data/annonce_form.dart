import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'annonce_catalog.dart';

/// Une photo choisie dans le wizard (octets en mémoire, pas encore uploadée).
class PickedPhoto {
  PickedPhoto({required this.bytes, required this.name, required this.mime});
  final Uint8List bytes;
  final String name;
  final String mime;

  int get sizeMo => (bytes.lengthInBytes / (1024 * 1024)).ceil();
  bool get tropLourde => bytes.lengthInBytes >= 10 * 1024 * 1024;
}

/// État + soumission du wizard d'annonce (Zappart Pro web).
///
/// Écrit un document `house` en `statut_validation: 'en_attente'` /
/// `active: false` → l'annonce part en file de validation admin (mêmes règles
/// Firestore que le wizard mobile de l'espace hôte). Le partenaire ne fixe pas
/// les marges Zappart (`prixzap`/`prixpar`/`comission`) : l'admin les renseigne
/// à la validation.
class AnnonceForm extends ChangeNotifier {
  AnnonceForm(this.partenaireRef);

  final DocumentReference<Map<String, dynamic>> partenaireRef;

  // ── Étape 1 — type & localisation ──
  String locationtype = ''; // 'Journalier' | 'Mensuel'
  String type = '';
  String quartier = ''; // clé backend
  String zone = '';
  String cite = '';
  String adresse = '';
  String emplacement = '';
  double? geoLat;
  double? geoLng;
  bool get hasPosition => geoLat != null && geoLng != null;

  // ── Étape 2 — caractéristiques ──
  int nbchambre = 1;
  int nbsalon = 1;
  int nbbain = 1;
  int nbcuisine = 1;
  int capacite = 2; // journalier
  int surface = 0;
  int numbien = 0; // journalier
  int heureArriveeMin = 14 * 60; // journalier — minutes depuis minuit
  int heureDepartMin = 11 * 60;
  final Set<String> regles = {};

  // ── Étape 3 — commodités ──
  final Set<String> comodites = {};

  // ── Étape 4 — photos ──
  final List<PickedPhoto> photos = [];

  // ── Étape 5 — concierge ──
  String conciergeNom = '';
  String conciergeNum = '';

  // ── Étape 6 — prix & description ──
  double prix = 0;
  int cautionMois = 1; // mensuel
  String chargesIncluses = 'a_part'; // mensuel
  String chargesPrecision = '';
  int bailMinMois = 12; // mensuel
  bool journeeActive = false; // journalier
  double prixJournee = 0;
  String description = '';
  String accroche = '';

  bool get isJournalier => locationtype == 'Journalier';
  int get nbpiece => nbchambre + nbsalon;
  double get cautionCalculee => cautionMois * prix;

  bool get autoriseSalon => !kSansSalon.contains(type);
  bool get autoriseCuisine => !kSansCuisine.contains(type);
  bool get chambreFigee => kUneChambre.contains(type);

  /// Normalise les compteurs selon le type (à appeler à chaque changement).
  void appliquerContraintesType() {
    if (chambreFigee) nbchambre = 1;
    if (!autoriseSalon) nbsalon = 0;
    if (!autoriseCuisine) nbcuisine = 0;
  }

  void touch() => notifyListeners();

  // ── Validation par étape (bouton « Suivant ») ──
  bool get step1Ok =>
      locationtype.isNotEmpty &&
      type.isNotEmpty &&
      quartier.isNotEmpty &&
      cite.trim().isNotEmpty &&
      adresse.trim().isNotEmpty &&
      hasPosition;

  bool get step2Ok {
    if (nbchambre < 1 || nbbain < 1) return false;
    if (isJournalier && (capacite < 1 || numbien < 1 || regles.isEmpty)) {
      return false;
    }
    return true;
  }

  bool get step3Ok => true; // commodités optionnelles
  bool get step4Ok => photos.length >= 3 && photos.every((p) => !p.tropLourde);
  bool get step5Ok =>
      conciergeNom.trim().isNotEmpty && conciergeNum.trim().length >= 6;

  bool get step6Ok {
    if (prix <= 0) return false;
    if (isJournalier && journeeActive && prixJournee <= 0) return false;
    if (!isJournalier && cautionMois < 1) return false;
    if (description.trim().length < 20) return false;
    return true;
  }

  bool okForStep(int i) => switch (i) {
        0 => step1Ok,
        1 => step2Ok,
        2 => step3Ok,
        3 => step4Ok,
        4 => step5Ok,
        5 => step6Ok,
        _ => true,
      };

  // ── Lien Google Maps collé → (lat, lng) ──
  static (double, double)? parseLatLng(String raw) {
    final s = raw.trim();
    final patterns = [
      RegExp(r'query=(-?\d+\.\d+),\s*(-?\d+\.\d+)'),
      RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
      RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'(-?\d{1,2}\.\d{3,}),\s*(-?\d{1,3}\.\d{3,})'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(s);
      if (m != null) {
        final lat = double.tryParse(m.group(1)!);
        final lng = double.tryParse(m.group(2)!);
        if (lat != null && lng != null) return (lat, lng);
      }
    }
    return null;
  }

  static String mapsLink(double lat, double lng) =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  DateTime _heure(int minutes) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
  }

  // ── Soumission ──
  bool submitting = false;
  String? erreur;

  Future<bool> submit() async {
    submitting = true;
    erreur = null;
    notifyListeners();
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        erreur = 'Session expirée. Reconnectez-vous.';
        return false;
      }
      final col = FirebaseFirestore.instance.collection('house');
      final doc = col.doc();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      // Upload des photos (séquentiel → ordre stable ; 1re = couverture).
      final urls = <String>[];
      for (var i = 0; i < photos.length; i++) {
        final p = photos[i];
        final ext = p.mime.contains('png') ? 'png' : 'jpg';
        final ref = FirebaseStorage.instance
            .ref()
            .child('House/$uid/${doc.id}/img_${stamp}_$i.$ext');
        await ref.putData(
          p.bytes,
          SettableMetadata(contentType: p.mime),
        );
        urls.add(await ref.getDownloadURL());
      }

      final data = <String, dynamic>{
        'description': description.trim(),
        'specifications': accroche.trim(),
        'quartier': quartier,
        'zone': zone.trim(),
        'types': type,
        'locationtype': isJournalier ? 'Journalier' : 'Mensuel',
        'partenaireId': partenaireRef,
        'cite': cite.trim(),
        'localisation': adresse.trim(),
        'emplacement': emplacement,
        'geolocalisation': mapsLink(geoLat!, geoLng!),
        'prix': prix,
        'nbchambre': nbchambre,
        'nbsalon': nbsalon.toDouble(),
        'nbbain': nbbain,
        'nbcuisine': nbcuisine,
        'surface': surface,
        'nombredepiece': '$nbpiece',
        'conciergenom': conciergeNom.trim(),
        'conciergenum': conciergeNum.trim(),
        'conciergephoto': '',
        'active': false,
        'statut_validation': 'en_attente',
        'motif_rejet': '',
        'image': urls,
        'Comodite': comodites.toList(),
        'soumis_le': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      };

      if (isJournalier) {
        data['maximal'] = '$capacite';
        data['numbien'] = numbien;
        data['heureRegle1'] = Timestamp.fromDate(_heure(heureArriveeMin));
        data['heureRegle2'] = Timestamp.fromDate(_heure(heureDepartMin));
        data['journee_active'] = journeeActive;
        if (journeeActive) data['prix_journee'] = prixJournee;
        data['regleMaison'] = regles.toList();
      } else {
        data['caution_mois'] = cautionMois;
        data['caution'] = cautionMois * prix;
        data['charges_incluses'] = chargesIncluses;
        data['charges_precision'] =
            chargesIncluses == 'partiel' ? chargesPrecision.trim() : '';
        data['bail_min_mois'] = bailMinMois;
      }

      await doc.set(data);
      return true;
    } catch (e) {
      debugPrint('AnnonceForm.submit échec : $e');
      erreur = "L'envoi a échoué. Vérifiez votre connexion et réessayez.";
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
