import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Paiement en ligne de l'abonnement Zappart Pro (via le callable `paiement`,
/// même plomberie GeniusPay que l'app officielle). 100 % revenu Zappart.
class PaiementService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'europe-west3');
  static final _db = FirebaseFirestore.instance;

  /// Flag `app_settings/global_data.paiement_en_ligne_actif` (lecture publique).
  /// Tant qu'il est faux, l'abonnement se règle hors ligne (WhatsApp).
  static Stream<bool> paiementActif() => _db
      .collection('app_settings')
      .where('name', isEqualTo: 'global_data')
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isNotEmpty &&
          s.docs.first.data()['paiement_en_ligne_actif'] == true);

  /// Ouvre une page de paiement pour l'abonnement. Retourne l'URL GeniusPay
  /// (à ouvrir dans un nouvel onglet). Lève une [Exception] lisible sinon.
  static Future<String> initierAbonnement({
    required String formule, // 'gerant' | 'agence' | 'agence_plus'
    required String periode, // 'mensuel' | 'annuel'
    required String moyen, // 'wave' | 'orange_money' | 'carte'
    String numero = '',
  }) async {
    final HttpsCallableResult res;
    try {
      res = await _fn.httpsCallable('paiement').call(<String, dynamic>{
        'action': 'initier_abonnement',
        'formule': formule,
        'periode': periode,
        'moyen': moyen,
        'numero': numero,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Paiement impossible (${e.code}).');
    }
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['statut'] != 'succes') {
      throw Exception(data['message'] ?? 'Paiement impossible.');
    }
    final url = data['payment_url'] as String?;
    if (data['en_ligne'] != true || url == null || url.isEmpty) {
      throw Exception(
          data['message'] ?? 'Le paiement en ligne est indisponible.');
    }
    return url;
  }
}
