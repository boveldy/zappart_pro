/// Système de rôles & permissions de l'équipe d'une agence (Zappart Pro).
///
/// Source de vérité UNIQUE, partagée par :
///  - `AuthService` (résolution des droits du membre connecté) ;
///  - la page Équipe (préréglages + interrupteurs) ;
///  - le script de migration (`membres_pro` des agences existantes).
///
/// Un membre est un doc `membres_pro/{uid}` portant :
///  - `role`                  : l'un de [ProRole] ;
///  - `permissions_override`  : map (clé vers bool) — seulement ce que l'Admin
///                              a modifié à la main ;
///  - `permissions`           : map (clé vers bool) RÉSOLUE (= préréglage du rôle
///                              écrasé par l'override). C'est la SEULE que
///                              lisent les règles Firestore et l'UI.
///
/// À chaque changement de `role` ou d'`override`, l'app réécrit `permissions`
/// via [resolvePermissions].
library;

/// Rôles de base. Chacun n'est qu'un **préréglage** de permissions.
enum ProRole {
  admin('admin', 'Admin agence'),
  gerant('gerant', 'Gérant'),
  comptable('comptable', 'Comptable'),
  agent('agent', 'Agent');

  const ProRole(this.code, this.label);
  final String code;
  final String label;

  static ProRole fromCode(String? code) => ProRole.values.firstWhere(
        (r) => r.code == code,
        orElse: () => ProRole.agent,
      );
}

/// Clés de permission actives en V1. Convention : `domaine.action`.
///
/// ⚠️ Espace de noms réservé pour la suite (NE PAS réutiliser autrement) :
///   `finances.reversement`, `compta.export`, `honoraires.emettre`,
///   `caution.gerer`.
class ProPerm {
  static const biensCreer = 'biens.creer';
  static const biensPublier = 'biens.publier';
  static const biensArchiver = 'biens.archiver';
  static const bauxCreer = 'baux.creer';
  static const bauxEncaisser = 'baux.encaisser';
  static const bauxDepenses = 'baux.depenses';
  static const bauxCloturer = 'baux.cloturer';
  static const bauxProlonger = 'baux.prolonger';
  static const proprietairesGerer = 'proprietaires.gerer';
  static const immeublesGerer = 'immeubles.gerer';
  static const financesVoir = 'finances.voir';
  static const journalVoir = 'journal.voir';
  static const equipeGerer = 'equipe.gerer';
  static const facturationGerer = 'facturation.gerer';

  /// Toutes les clés, dans l'ordre d'affichage.
  static const all = <String>[
    biensCreer,
    biensPublier,
    biensArchiver,
    bauxCreer,
    bauxEncaisser,
    bauxDepenses,
    bauxCloturer,
    bauxProlonger,
    proprietairesGerer,
    immeublesGerer,
    financesVoir,
    journalVoir,
    equipeGerer,
    facturationGerer,
  ];

  /// Non délégables : réservées à l'Admin, jamais proposées comme interrupteur.
  static const nonDelegables = <String>{equipeGerer, facturationGerer};

  /// Libellé lisible pour la page Équipe.
  static const labels = <String, String>{
    biensCreer: 'Créer / modifier une annonce (brouillon)',
    biensPublier: 'Publier une annonce',
    biensArchiver: 'Archiver / retirer un bien',
    bauxCreer: 'Créer un bail',
    bauxEncaisser: 'Encaisser un loyer, valider un signalement',
    bauxDepenses: 'Saisir des dépenses',
    bauxCloturer: 'Clôturer un bail',
    bauxProlonger: 'Prolonger un bail',
    proprietairesGerer: 'Gérer les propriétaires',
    immeublesGerer: 'Gérer les immeubles',
    financesVoir: 'Voir les montants, relevés et reversements',
    journalVoir: 'Consulter l\'historique de l\'agence',
    equipeGerer: 'Gérer l\'équipe (inviter / rôles / révoquer)',
    facturationGerer: 'Gérer l\'abonnement et la facturation',
  };
}

/// Préréglage de chaque rôle : la valeur de départ de chaque clé.
/// (Toute clé absente de la map = `false`.)
const Map<ProRole, Set<String>> _presets = {
  ProRole.admin: {
    ProPerm.biensCreer,
    ProPerm.biensPublier,
    ProPerm.biensArchiver,
    ProPerm.bauxCreer,
    ProPerm.bauxEncaisser,
    ProPerm.bauxDepenses,
    ProPerm.bauxCloturer,
    ProPerm.bauxProlonger,
    ProPerm.proprietairesGerer,
    ProPerm.immeublesGerer,
    ProPerm.financesVoir,
    ProPerm.journalVoir,
    ProPerm.equipeGerer,
    ProPerm.facturationGerer,
  },
  ProRole.gerant: {
    ProPerm.biensCreer,
    ProPerm.biensPublier,
    ProPerm.biensArchiver,
    ProPerm.bauxCreer,
    ProPerm.bauxEncaisser,
    ProPerm.bauxDepenses,
    ProPerm.bauxCloturer,
    ProPerm.bauxProlonger,
    ProPerm.proprietairesGerer,
    ProPerm.immeublesGerer,
    ProPerm.financesVoir,
  },
  ProRole.comptable: {
    ProPerm.bauxEncaisser,
    ProPerm.bauxDepenses,
    ProPerm.proprietairesGerer,
    ProPerm.financesVoir,
  },
  ProRole.agent: {
    ProPerm.biensCreer,
  },
};

/// Préréglage brut d'un rôle (map complète clé → bool), sans override.
Map<String, bool> presetFor(ProRole role) {
  final on = _presets[role] ?? const <String>{};
  return {for (final k in ProPerm.all) k: on.contains(k)};
}

/// Permissions EFFECTIVES d'un membre = préréglage du rôle, écrasé par les
/// surcharges de l'Admin. Les clés non délégables ignorent toute surcharge.
Map<String, bool> resolvePermissions(
  ProRole role,
  Map<String, dynamic>? override,
) {
  final base = presetFor(role);
  if (override != null) {
    override.forEach((k, v) {
      if (!ProPerm.all.contains(k)) return;
      if (ProPerm.nonDelegables.contains(k)) return;
      base[k] = v == true;
    });
  }
  return base;
}

// Le plafond de sièges vit sur `Abonnement.plafondSieges` (il dépend de la
// formule réelle : Agence + = 8, Réseau = 50, mono-utilisateur = 1).
