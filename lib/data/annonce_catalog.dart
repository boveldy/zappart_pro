/// Catalogues figés du wizard d'annonce web — repris à l'identique de l'app
/// officielle (`quartiers_catalog.dart`, `amenity_icon.dart`,
/// `nouvelle_annonce_model.dart`). Doivent rester alignés : ce sont les mêmes
/// valeurs que celles écrites dans `house` par le mobile.
library;

/// (libellé affiché, clé backend stockée dans `house.quartier`, centre GPS
/// approximatif — sert à cadrer la carte). Coords reprises de
/// `quartiers_catalog.dart` (officiel).
typedef QuartierInfo = ({String label, String key, double lat, double lng});

const List<QuartierInfo> kQuartiers = [
  (label: 'Ouakam', key: 'Ouakam', lat: 14.7206, lng: -17.4906),
  (label: 'Mamelles', key: 'Mamelles', lat: 14.7297, lng: -17.4967),
  (label: 'Almadies', key: 'Almadies', lat: 14.7442, lng: -17.5119),
  (label: 'Medina', key: 'Medina', lat: 14.6797, lng: -17.4497),
  (label: 'Sacré-coeur', key: 'Sacré-coeur', lat: 14.7047, lng: -17.4631),
  (label: 'Ngor', key: 'Ngor', lat: 14.7494, lng: -17.5122),
  (label: 'Grand-Dakar', key: 'Grand-Dakar', lat: 14.7006, lng: -17.4453),
  (label: 'Liberté', key: 'Liberté', lat: 14.7139, lng: -17.4592),
  (label: 'Ouest-foire', key: 'Ouest-foire', lat: 14.7439, lng: -17.4767),
  (label: 'Plateaux', key: 'Plateaux', lat: 14.6686, lng: -17.4358),
  (label: 'Fann', key: 'Fann', lat: 14.6903, lng: -17.4692),
  (label: 'Mermoz', key: 'Mermoz', lat: 14.7069, lng: -17.4756),
  (label: 'Scat-Urban', key: 'Scat-Urban', lat: 14.7181, lng: -17.4489),
  (label: 'HLM', key: 'HLM', lat: 14.6953, lng: -17.4472),
  (label: 'Mariste', key: 'Mariste', lat: 14.7358, lng: -17.4247),
  (label: 'Baobab', key: 'Baobab', lat: 14.6892, lng: -17.4536),
  (label: 'Keur Gorgui', key: 'Coeur gorgui', lat: 14.7100, lng: -17.4620),
  (label: 'Bel Aire', key: 'Bel Aire', lat: 14.6772, lng: -17.4189),
  (label: 'Castor', key: 'Castor', lat: 14.6931, lng: -17.4442),
  (label: 'Captage', key: 'Captage', lat: 14.7338, lng: -17.4432),
  (label: 'Keur Massar', key: 'Keur Massar', lat: 14.7853, lng: -17.3106),
];

QuartierInfo? quartierInfoFor(String key) {
  final k = key.trim().toLowerCase();
  for (final q in kQuartiers) {
    if (q.key.trim().toLowerCase() == k) return q;
  }
  return null;
}

const List<String> kTypesLogement = [
  'Appartement',
  'Villa',
  'Mini studio',
  'Chambre',
  'Maison',
  'Duplex',
];

/// Types sans salon / sans cuisine / limités à une chambre (cohérence Dakar).
const Set<String> kSansSalon = {'Mini studio', 'Chambre'};
const Set<String> kSansCuisine = {'Chambre'};
const Set<String> kUneChambre = {'Mini studio', 'Chambre'};

const List<String> kEmplacements = [
  'RDC',
  '1er étage',
  '2e étage',
  '3e étage',
  '4e étage',
  '5e étage',
  '6e étage',
  '7e étage',
  '8e étage',
  '9e étage et +',
];

const List<String> kReglesMaison = [
  'Non fumeur',
  'Fêtes interdites',
  'Animaux non admis',
  'Silence après 22h',
  'Pas de visiteurs',
  'Enfants bienvenus',
];

/// valeur stockée (`house.charges_incluses`) → libellé
const Map<String, String> kChargesOptions = {
  'incluses': 'Incluses dans le loyer',
  'partiel': 'Partiellement incluses',
  'a_part': 'À la charge du locataire',
};

const List<int> kBailOptions = [1, 3, 6, 12, 24];

const Map<String, List<String>> kComoditesMensuelGroupes = {
  'Privatif': [
    'Cuisine personnelle',
    'Salle de bain personnelle',
    'Entrée indépendante',
  ],
  'Eau & électricité': [
    'Groupe électrogène',
    "Château d'eau",
    'Compteur électrique individuel',
  ],
  'Confort': [
    'Climatisation',
    'Eau chaude',
    'Wifi',
    'Meublé',
    'Balcon',
    'Espace pour sécher le linge',
  ],
  'Immeuble': [
    'Sécurité',
    'Parking',
    'Ascenseur',
    'Cour intérieure',
  ],
};

const Map<String, List<String>> kComoditesJournalierGroupes = {
  'Connexion & divertissement': [
    'Wifi',
    'Télévision',
    'Espace de travail',
  ],
  'Énergie & eau': [
    'Groupe électrogène',
    "Château d'eau",
    'Eau chaude',
    'Climatisation',
  ],
  'Chambre & salle de bain': [
    'Linge fourni',
    'Moustiquaire',
    'Sèche-cheveux',
    'Fer à repasser',
  ],
  'Cuisine': [
    'Cuisine équipée',
    'Réfrigérateur',
    'Micro-ondes',
    'Bouilloire / cafetière',
    'Machine à laver',
  ],
  'Arrivée & sécurité': [
    'Arrivée autonome',
    'Sécurité',
    'Parking',
    'Ascenseur',
  ],
  'Extérieur': [
    'Piscine',
    'Balcon',
    'Terrasse / Jardin',
    'Vue sur mer',
    'Accès plage',
  ],
};

Map<String, List<String>> comoditesGroupes({required bool journalier}) =>
    journalier ? kComoditesJournalierGroupes : kComoditesMensuelGroupes;

/// Libellés historiques en base → libellé canonique (repris de `amenity_icon.dart`).
const Map<String, String> _alias = {
  'WI-FI': 'Wifi',
  'Gardien': 'Sécurité',
  'Cuisine': 'Cuisine équipée',
  'Salle de bain personelle': 'Salle de bain personnelle',
  'Cuisine personelle': 'Cuisine personnelle',
  'Espace pour secher le linge': 'Espace pour sécher le linge',
};

String amenityCanonique(String item) => _alias[item] ?? item;

/// Commodités qui reçoivent une **photo dédiée** dans le wizard (sous-ensemble
/// qui se photographie vraiment) — repris de `amenity_icon.dart`.
const List<String> kComoditesPhotoMensuel = [
  'Cuisine personnelle',
  'Salle de bain personnelle',
  'Entrée indépendante',
  'Groupe électrogène',
  "Château d'eau",
  'Balcon',
  'Espace pour sécher le linge',
  'Parking',
  'Ascenseur',
  'Cour intérieure',
];

const List<String> kComoditesPhotoJournalier = [
  'Cuisine équipée',
  'Groupe électrogène',
  "Château d'eau",
  'Parking',
  'Ascenseur',
  'Piscine',
  'Balcon',
  'Terrasse / Jardin',
  'Vue sur mer',
  'Accès plage',
];

List<String> comoditesAvecPhoto({required bool journalier}) =>
    journalier ? kComoditesPhotoJournalier : kComoditesPhotoMensuel;

bool comoditeAPhoto(String item, {required bool journalier}) =>
    comoditesAvecPhoto(journalier: journalier).contains(amenityCanonique(item));
