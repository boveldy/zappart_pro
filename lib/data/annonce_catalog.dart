/// Catalogues figés du wizard d'annonce web — repris à l'identique de l'app
/// officielle (`quartiers_catalog.dart`, `amenity_icon.dart`,
/// `nouvelle_annonce_model.dart`). Doivent rester alignés : ce sont les mêmes
/// valeurs que celles écrites dans `house` par le mobile.
library;

/// (libellé affiché, clé backend stockée dans `house.quartier`)
const List<({String label, String key})> kQuartiers = [
  (label: 'Ouakam', key: 'Ouakam'),
  (label: 'Mamelles', key: 'Mamelles'),
  (label: 'Almadies', key: 'Almadies'),
  (label: 'Medina', key: 'Medina'),
  (label: 'Sacré-coeur', key: 'Sacré-coeur'),
  (label: 'Ngor', key: 'Ngor'),
  (label: 'Grand-Dakar', key: 'Grand-Dakar'),
  (label: 'Liberté', key: 'Liberté'),
  (label: 'Ouest-foire', key: 'Ouest-foire'),
  (label: 'Plateaux', key: 'Plateaux'),
  (label: 'Fann', key: 'Fann'),
  (label: 'Mermoz', key: 'Mermoz'),
  (label: 'Scat-Urban', key: 'Scat-Urban'),
  (label: 'HLM', key: 'HLM'),
  (label: 'Mariste', key: 'Mariste'),
  (label: 'Baobab', key: 'Baobab'),
  (label: 'Keur Gorgui', key: 'Coeur gorgui'),
  (label: 'Bel Aire', key: 'Bel Aire'),
  (label: 'Castor', key: 'Castor'),
  (label: 'Captage', key: 'Captage'),
  (label: 'Keur Massar', key: 'Keur Massar'),
];

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
