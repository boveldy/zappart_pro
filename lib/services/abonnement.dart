import 'package:cloud_firestore/cloud_firestore.dart';

/// Abonnement Zappart Pro — porté par des champs sur la fiche `Partenaires`
/// (pas de collection dédiée : l'hôte lit déjà sa fiche, et seul l'admin peut
/// écrire ces champs — cf. `firestore.rules` § Partenaires, l'hôte ne peut
/// modifier que `logo`).
///
/// Champs lus sur `Partenaires/{id}` :
///  - `abo_formule`     : 'decouverte' | 'gerant' | 'agence' | 'agence_plus' | 'reseau'
///                        (absent → 'decouverte')
///  - `abo_actif_jusqu` : Timestamp — échéance du forfait payant (absent pour
///                        Découverte = illimité)
///  - `abo_fondateur`   : bool — tarif Fondateur (−40 % à vie)
///
/// L'admin ne saisit que `abo_formule` (+ `abo_actif_jusqu` au paiement) ; le
/// quota et les fonctionnalités en découlent.
enum Formule { decouverte, gerant, agence, agencePlus, reseau }

class Abonnement {
  const Abonnement(
    this.formule, {
    this.actifJusqu,
    this.fondateur = false,
  });

  final Formule formule;
  final DateTime? actifJusqu;
  final bool fondateur;

  // ── Barème (aligné sur zappart-pro.html § Tarifs) ──
  static const _quota = <Formule, int>{
    Formule.decouverte: 3,
    Formule.gerant: 15,
    Formule.agence: 40,
    Formule.agencePlus: 100,
    Formule.reseau: 1000000,
  };
  static const _prixLancement = <Formule, int>{
    Formule.decouverte: 0,
    Formule.gerant: 9000,
    Formule.agence: 25000,
    Formule.agencePlus: 55000,
    Formule.reseau: 120000,
  };

  int get quotaBaux => _quota[formule]!;
  int get prixMensuel {
    final p = _prixLancement[formule]!;
    return fondateur ? (p * 0.6).round() : p;
  }

  String get label => switch (formule) {
        Formule.decouverte => 'Découverte',
        Formule.gerant => 'Gérant',
        Formule.agence => 'Agence',
        Formule.agencePlus => 'Agence +',
        Formule.reseau => 'Réseau',
      };

  /// Vues d'annonces + page Statistiques : réservées à Agence et plus (évite de
  /// consommer des lectures Firestore pour les petits forfaits).
  bool get statsIncluses => formule.index >= Formule.agence.index;

  /// Plusieurs comptes agents : Agence + et Réseau.
  bool get multiUtilisateur => formule.index >= Formule.agencePlus.index;

  bool get estPayant => formule != Formule.decouverte;

  // ── Cycle de vie (grâce 7 j → lecture seule à J+30) ──
  DateTime? get _grace => actifJusqu?.add(const Duration(days: 7));
  DateTime? get _finGrace => actifJusqu?.add(const Duration(days: 30));

  bool get expire =>
      estPayant && actifJusqu != null && DateTime.now().isAfter(actifJusqu!);
  bool get enGrace =>
      expire && _grace != null && DateTime.now().isBefore(_grace!);
  bool get bloqueCreation =>
      expire && _grace != null && DateTime.now().isAfter(_grace!);
  bool get lectureSeule =>
      expire && _finGrace != null && DateTime.now().isAfter(_finGrace!);

  int? get joursRestants {
    if (actifJusqu == null) return null;
    return actifJusqu!.difference(DateTime.now()).inDays;
  }

  static Formule parseFormule(String? s) => switch (s) {
        'gerant' => Formule.gerant,
        'agence' => Formule.agence,
        'agence_plus' => Formule.agencePlus,
        'reseau' => Formule.reseau,
        _ => Formule.decouverte,
      };

  static Abonnement fromPartenaire(Map<String, dynamic>? m) {
    final d = m ?? const {};
    return Abonnement(
      parseFormule(d['abo_formule'] as String?),
      actifJusqu: d['abo_actif_jusqu'] is Timestamp
          ? (d['abo_actif_jusqu'] as Timestamp).toDate()
          : null,
      fondateur: d['abo_fondateur'] == true,
    );
  }

  /// Forfait « Découverte » par défaut (fiche partenaire pas encore chargée).
  static const Abonnement decouverte = Abonnement(Formule.decouverte);
}

/// Description d'un plan pour la page « Mon abonnement ».
class PlanInfo {
  const PlanInfo(this.formule, this.quota, this.prix, this.avantages);
  final Formule formule;
  final String quota;
  final int prix; // 0 = gratuit / -1 = sur devis
  final List<String> avantages;

  static const tous = <PlanInfo>[
    PlanInfo(Formule.decouverte, "Jusqu'à 3 baux actifs", 0, [
      'Toutes les fonctions de gérance',
      'Quittances & reçus PDF',
      'Espace locataire dans l\'app',
    ]),
    PlanInfo(Formule.gerant, "Jusqu'à 15 baux actifs", 9000, [
      'Relevé de gérance PDF / Excel',
      'Dépenses & réparations imputées',
      'Clôture de bail + solde de caution',
    ]),
    PlanInfo(Formule.agence, "Jusqu'à 40 baux actifs", 25000, [
      'Tout le plan Gérant',
      'Statistiques & vues d\'annonces',
      'Relevés consolidés par propriétaire',
      'Support prioritaire WhatsApp',
    ]),
    PlanInfo(Formule.agencePlus, "Jusqu'à 100 baux actifs", 55000, [
      'Tout le plan Agence',
      'Plusieurs comptes agents',
      'Accompagnement à la mise en route',
    ]),
    PlanInfo(Formule.reseau, '100+ baux — multi-agences', -1, [
      'Tout le plan Agence +',
      'Multi-agences / franchise',
      'Interlocuteur dédié',
    ]),
  ];
}
