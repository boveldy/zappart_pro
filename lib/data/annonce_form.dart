import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'annonce_catalog.dart';
import 'house.dart';

/// Une photo choisie dans le wizard (octets en mémoire, pas encore uploadée).
class PickedPhoto {
  PickedPhoto({required this.bytes, required this.mime});
  final Uint8List bytes;
  final String mime;

  bool get tropLourde => bytes.lengthInBytes >= 10 * 1024 * 1024;
}

/// État + soumission du wizard d'annonce (Zappart Pro web).
///
/// Écrit un document `house` en `statut_validation: 'en_attente'` /
/// `active: false` → file de validation admin (mêmes règles Firestore que le
/// wizard mobile de l'espace hôte). Le partenaire ne fixe pas les marges Zappart
/// (`prixzap`/`prixpar`/`comission`) : l'admin les renseigne à la validation.
///
/// Les photos sont **classées par pièce** (« Chambre 1 », « Salon »…) puis par
/// commodité photographiable cochée — mêmes catégories que le mobile → le
/// document `photos_categories` et l'ordre du carrousel `image` sont identiques.
class AnnonceForm extends ChangeNotifier {
  AnnonceForm(this.partenaireRef);

  final DocumentReference<Map<String, dynamic>> partenaireRef;

  /// Non nul → mode « compléter et publier » : `submit()` met à jour CE document
  /// `house` (bien privé de la gérance) au lieu d'en créer un neuf, ce qui
  /// préserve le lien `bail.house_ref`.
  DocumentReference<Map<String, dynamic>>? editRef;

  /// Pré-remplit le formulaire depuis un bien existant (bien privé de gérance).
  /// Ne reprend que ce qui est fiable : type de location, prix (= loyer), caution.
  /// Le quartier d'un bien privé est un texte libre → laissé à ressaisir.
  void seedFromHouse(House h) {
    editRef = FirebaseFirestore.instance.collection('house').doc(h.id);
    locationtype =
        h.locationType == 'Journalier' ? 'Journalier' : 'Mensuel';
    if (kTypesLogement.contains(h.type)) type = h.type;
    if (quartierInfoFor(h.quartier) != null) quartier = h.quartier;
    zone = h.zone;
    cite = h.cite;
    if (h.nbChambre != null && h.nbChambre! > 0) nbchambre = h.nbChambre!;
    if (h.nbBain != null && h.nbBain! > 0) nbbain = h.nbBain!;
    if (h.nbSalon != null && h.nbSalon! > 0) nbsalon = h.nbSalon!.round();
    if ((h.prix ?? 0) > 0) prix = h.prix!;
    if (h.cautionMois != null && h.cautionMois! > 0) {
      cautionMois = h.cautionMois!;
    }
    if (h.description.isNotEmpty) description = h.description;
    notifyListeners();
  }

  // ── Étape 1 — type & localisation ──
  String locationtype = '';
  String type = '';
  String quartier = '';
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
  int capacite = 2;
  int surface = 0;
  int numbien = 0;
  int heureArriveeMin = 14 * 60;
  int heureDepartMin = 11 * 60;
  final Set<String> regles = {};

  // ── Étape 3 — commodités ──
  final Set<String> comodites = {};

  // ── Étape 4 — photos par catégorie ──
  final Map<String, List<PickedPhoto>> photos = {};

  // ── Étape 5 — concierge ──
  String conciergeNom = '';
  String conciergeNum = '';

  // ── Étape 6 — prix & description ──
  double prix = 0;
  int cautionMois = 1;
  String chargesIncluses = 'a_part';
  String chargesPrecision = '';
  int bailMinMois = 12;
  bool journeeActive = false;
  double prixJournee = 0;
  String description = '';
  String accroche = '';

  bool get isJournalier => locationtype == 'Journalier';
  int get nbpiece => nbchambre + nbsalon;
  double get cautionCalculee => cautionMois * prix;

  bool get autoriseSalon => !kSansSalon.contains(type);
  bool get autoriseCuisine => !kSansCuisine.contains(type);
  bool get chambreFigee => kUneChambre.contains(type);

  void appliquerContraintesType() {
    if (chambreFigee) nbchambre = 1;
    if (!autoriseSalon) nbsalon = 0;
    if (!autoriseCuisine) nbcuisine = 0;
  }

  void touch() => notifyListeners();

  // ── Catégories photo ──
  static List<String> _labels(String nom, int n) {
    if (n <= 0) return const [];
    if (n == 1) return [nom];
    return [for (var i = 1; i <= n; i++) '$nom $i'];
  }

  /// Pièces à photographier — **obligatoires** (≥ 1 photo chacune).
  List<String> get categoriesPieces => [
        ..._labels('Chambre', nbchambre),
        if (autoriseSalon) ..._labels('Salon', nbsalon),
        if (autoriseCuisine) ..._labels('Cuisine', nbcuisine),
        ..._labels('Salle de bain', nbbain),
      ];

  /// Commodités cochées qui reçoivent une catégorie photo — **optionnelles**.
  List<String> get categoriesCommodites {
    final out = <String>[];
    for (final c in comodites) {
      if (!comoditeAPhoto(c, journalier: isJournalier)) continue;
      final l = amenityCanonique(c);
      if (!out.contains(l)) out.add(l);
    }
    return out;
  }

  List<String> get categoriesPhotos =>
      [...categoriesPieces, ...categoriesCommodites];

  int photosDe(String cat) => photos[cat]?.length ?? 0;
  int get totalPhotos => photos.values.fold(0, (a, l) => a + l.length);

  List<String> get piecesSansPhoto =>
      categoriesPieces.where((c) => photosDe(c) == 0).toList();

  bool get toutesLesPhotosOk =>
      photos.values.every((l) => l.every((p) => !p.tropLourde));

  // ── Validation par étape ──
  bool get step1Ok =>
      locationtype.isNotEmpty &&
      type.isNotEmpty &&
      quartier.isNotEmpty &&
      (!quartierADesZones(quartier) || zone.trim().isNotEmpty) &&
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

  bool get step3Ok => true;
  bool get step4Ok =>
      piecesSansPhoto.isEmpty && totalPhotos >= 3 && toutesLesPhotosOk;
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
      final doc =
          editRef ?? FirebaseFirestore.instance.collection('house').doc();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      // Upload par catégorie (séquentiel → ordre stable).
      final urlsParCat = <String, List<String>>{};
      for (final entry in photos.entries) {
        if (entry.value.isEmpty) continue;
        final slug = _slug(entry.key);
        final urls = <String>[];
        for (var i = 0; i < entry.value.length; i++) {
          final p = entry.value[i];
          final ext = p.mime.contains('png') ? 'png' : 'jpg';
          final ref = FirebaseStorage.instance.ref().child(
              'House/$uid/${doc.id}/img_${slug}_${stamp}_$i.$ext');
          await ref.putData(p.bytes, SettableMetadata(contentType: p.mime));
          urls.add(await ref.getDownloadURL());
        }
        urlsParCat[entry.key] = urls;
      }
      // Carrousel `image` : ordre déterministe (pièces puis commodités).
      final ordre = [
        ...categoriesPhotos,
        ...urlsParCat.keys.where((k) => !categoriesPhotos.contains(k)),
      ];
      final image = [for (final c in ordre) ...?urlsParCat[c]];

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
        'sur_marketplace': true,
        'statut_validation': 'en_attente',
        'motif_rejet': '',
        'image': image,
        'photos_categories': urlsParCat,
        'Comodite': comodites.toList(),
        'soumis_le': FieldValue.serverTimestamp(),
        if (editRef == null) 'created_at': FieldValue.serverTimestamp(),
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

      if (editRef != null) {
        await doc.update(data);
      } else {
        await doc.set(data);
      }
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

  static String _slug(String s) {
    const accents = 'àâäéèêëîïôöùûüç';
    const sans = 'aaaeeeeiioouuuc';
    var out = s.toLowerCase();
    for (var i = 0; i < accents.length; i++) {
      out = out.replaceAll(accents[i], sans[i]);
    }
    return out
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
