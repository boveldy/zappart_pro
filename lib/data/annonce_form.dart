import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'annonce_catalog.dart';
import 'house.dart';
import 'immeuble.dart';

/// Une photo dans le wizard : soit **nouvelle** (octets en mémoire, à uploader),
/// soit **déjà en ligne** (URL Storage — cas de la modification d'annonce, on
/// la conserve telle quelle).
class PickedPhoto {
  PickedPhoto.bytes(this.bytes, this.mime) : url = null;
  PickedPhoto.existante(this.url)
      : bytes = null,
        mime = 'image/jpeg';

  final Uint8List? bytes;
  final String? url;
  final String mime;

  bool get estExistante => url != null;
  bool get tropLourde =>
      bytes != null && bytes!.lengthInBytes >= 10 * 1024 * 1024;
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

  /// Non nul → mode « compléter et publier » OU « modifier » : `submit()` met à
  /// jour CE document `house` au lieu d'en créer un neuf (préserve le lien
  /// `bail.house_ref`, les stats, le boost…).
  DocumentReference<Map<String, dynamic>>? editRef;

  /// `true` → on modifie une annonce **déjà remplie et validée** : on pré-remplit
  /// TOUT (photos comprises), on assouplit « une photo par pièce », et
  /// l'enregistrement la renvoie en validation.
  bool editionComplete = false;

  /// `true` → on édite un **brouillon** (jamais soumis) : l'hôte peut ré-enregistrer
  /// le brouillon ou le publier.
  bool estBrouillon = false;

  /// Le wizard peut-il proposer « Enregistrer le brouillon » ? (création neuve
  /// ou édition d'un brouillon — jamais pour « compléter un privé » ni pour
  /// modifier une annonce validée).
  bool get brouillonPossible =>
      !editionComplete && (editRef == null || estBrouillon);

  /// Pré-remplit le formulaire depuis un bien privé de gérance (« Compléter et
  /// publier ») — ne reprend que ce qui est fiable.
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

  /// Pré-remplit le formulaire depuis un document `house` **complet** pour le
  /// modifier. Reprend tous les champs saisissables + les photos déjà en ligne
  /// (`photos_categories`, sinon la liste `image` sous la 1ʳᵉ catégorie).
  void loadFromDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? const <String, dynamic>{};
    editRef = snap.reference;
    final sv = (m['statut_validation'] as String?)?.trim() ?? '';
    estBrouillon = sv == 'brouillon';
    editionComplete = !estBrouillon;

    String s(String k) => (m[k] as String?)?.trim() ?? '';
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;

    locationtype = s('locationtype') == 'Journalier' ? 'Journalier' : 'Mensuel';
    if (kTypesLogement.contains(s('types'))) type = s('types');
    if (quartierInfoFor(s('quartier')) != null) quartier = s('quartier');
    zone = s('zone');
    cite = s('cite');
    adresse = s('localisation');
    emplacement = s('emplacement');
    final geo = parseLatLng(s('geolocalisation'));
    if (geo != null) {
      geoLat = geo.$1;
      geoLng = geo.$2;
    }

    if (i('nbchambre') > 0) nbchambre = i('nbchambre');
    if (d('nbsalon') > 0) nbsalon = d('nbsalon').round();
    if (i('nbbain') > 0) nbbain = i('nbbain');
    if (i('nbcuisine') > 0) nbcuisine = i('nbcuisine');
    if (i('surface') > 0) surface = i('surface');
    if (int.tryParse(s('maximal')) != null) capacite = int.parse(s('maximal'));
    if (i('numbien') > 0) numbien = i('numbien');
    heureArriveeMin = _minutesDe(m['heureRegle1']) ?? heureArriveeMin;
    heureDepartMin = _minutesDe(m['heureRegle2']) ?? heureDepartMin;
    regles
      ..clear()
      ..addAll((m['regleMaison'] as List?)?.whereType<String>() ?? const []);

    comodites
      ..clear()
      ..addAll((m['Comodite'] as List?)?.whereType<String>() ?? const []);

    conciergeNom = s('conciergenom');
    conciergeNum = s('conciergenum');
    conciergePhotoUrl = s('conciergephoto');
    final imm = m['immeuble_ref'];
    if (imm is DocumentReference<Map<String, dynamic>>) {
      immeubleRef = imm;
      immeubleNom = s('immeuble_nom');
    }

    if (d('prix') > 0) prix = d('prix');
    if (i('caution_mois') > 0) cautionMois = i('caution_mois');
    if (s('charges_incluses').isNotEmpty) chargesIncluses = s('charges_incluses');
    chargesPrecision = s('charges_precision');
    if (i('bail_min_mois') > 0) bailMinMois = i('bail_min_mois');
    journeeActive = m['journee_active'] == true;
    if (d('prix_journee') > 0) prixJournee = d('prix_journee');
    description = s('description');
    accroche = s('specifications');

    // Photos déjà en ligne.
    photos.clear();
    final cats = m['photos_categories'];
    if (cats is Map && cats.isNotEmpty) {
      cats.forEach((k, v) {
        final urls = (v as List?)?.whereType<String>() ?? const <String>[];
        if (urls.isNotEmpty) {
          photos['$k'] = [for (final u in urls) PickedPhoto.existante(u)];
        }
      });
    } else {
      final imgs = (m['image'] as List?)?.whereType<String>().toList() ??
          const <String>[];
      if (imgs.isNotEmpty) {
        final cible =
            categoriesPieces.isNotEmpty ? categoriesPieces.first : 'Photos';
        photos[cible] = [for (final u in imgs) PickedPhoto.existante(u)];
      }
    }
    notifyListeners();
  }

  static int? _minutesDe(dynamic v) {
    if (v is Timestamp) {
      final t = v.toDate();
      return t.hour * 60 + t.minute;
    }
    return null;
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

  // ── Immeuble / résidence (optionnel) ──
  // Rattaché → quartier / zone / cité / adresse / GPS / concierge viennent de
  // l'immeuble et ne sont plus saisis. Restent dénormalisés sur `house`.
  DocumentReference<Map<String, dynamic>>? immeubleRef;
  String immeubleNom = '';
  String immeubleDetail = '';
  bool get hasImmeuble => immeubleRef != null;

  void applyImmeuble(Immeuble im) {
    immeubleRef =
        FirebaseFirestore.instance.collection('immeubles').doc(im.id);
    immeubleNom = im.nom;
    immeubleDetail = im.sousTitre;
    quartier = im.quartier;
    zone = im.zone;
    cite = im.cite;
    adresse = im.localisation;
    final geo = parseLatLng(im.geolocalisation);
    geoLat = geo?.$1;
    geoLng = geo?.$2;
    conciergeNom = im.conciergenom;
    conciergeNum = im.conciergenum;
    conciergePhotoUrl = im.conciergephoto;
    notifyListeners();
  }

  void clearImmeuble() {
    immeubleRef = null;
    immeubleNom = '';
    immeubleDetail = '';
    quartier = '';
    zone = '';
    cite = '';
    adresse = '';
    geoLat = null;
    geoLng = null;
    conciergeNom = '';
    conciergeNum = '';
    conciergePhotoUrl = '';
    notifyListeners();
  }

  // ── Étape 5 — concierge ──
  String conciergeNom = '';
  String conciergeNum = '';
  String conciergePhotoUrl = '';

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
  bool get step4Ok => totalPhotos >= 3 &&
      toutesLesPhotosOk &&
      // En modification on fait confiance au jeu de photos déjà validé ; en
      // création chaque pièce doit avoir sa photo.
      (editionComplete || piecesSansPhoto.isEmpty);
  bool get step5Ok =>
      hasImmeuble ||
      (conciergeNom.trim().isNotEmpty && conciergeNum.trim().length >= 6);

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

  /// [publier] `true` → l'annonce part en `en_attente` (file de validation).
  /// `false` → elle reste un `brouillon` (visible du seul hôte, éditable et
  /// supprimable) — les champs incomplets sont tolérés.
  Future<bool> submit({bool publier = true}) async {
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

      // Upload par catégorie (séquentiel → ordre stable). Les photos déjà en
      // ligne (modification) sont conservées telles quelles.
      final urlsParCat = <String, List<String>>{};
      for (final entry in photos.entries) {
        if (entry.value.isEmpty) continue;
        final slug = _slug(entry.key);
        final urls = <String>[];
        for (var i = 0; i < entry.value.length; i++) {
          final p = entry.value[i];
          if (p.estExistante) {
            urls.add(p.url!);
            continue;
          }
          final ext = p.mime.contains('png') ? 'png' : 'jpg';
          final ref = FirebaseStorage.instance.ref().child(
              'House/$uid/${doc.id}/img_${slug}_${stamp}_$i.$ext');
          await ref.putData(p.bytes!, SettableMetadata(contentType: p.mime));
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
        if (hasPosition) 'geolocalisation': mapsLink(geoLat!, geoLng!),
        'prix': prix,
        'nbchambre': nbchambre,
        'nbsalon': nbsalon.toDouble(),
        'nbbain': nbbain,
        'nbcuisine': nbcuisine,
        'surface': surface,
        'nombredepiece': '$nbpiece',
        'conciergenom': conciergeNom.trim(),
        'conciergenum': conciergeNum.trim(),
        'conciergephoto': conciergePhotoUrl,
        'immeuble_ref': immeubleRef,
        'immeuble_nom': immeubleNom,
        'active': false,
        'sur_marketplace': true,
        'statut_validation': publier ? 'en_attente' : 'brouillon',
        'motif_rejet': '',
        'image': image,
        'photos_categories': urlsParCat,
        'Comodite': comodites.toList(),
        if (publier) 'soumis_le': FieldValue.serverTimestamp(),
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
        editRef = doc; // enchaîner brouillon → publier sans créer un 2ᵉ doc
        if (!publier) estBrouillon = true;
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
