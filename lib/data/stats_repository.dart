import 'package:cloud_firestore/cloud_firestore.dart';

/// Statistiques d'audience d'une annonce — doc `annonce_stats/{houseId}`,
/// alimenté par un `increment` direct depuis l'app mobile (pas de Cloud
/// Function). `jours` = { 'yyyy-MM-dd': nb_vues }.
class AnnonceStats {
  AnnonceStats(this.vuesTotal, this.jours);
  final int vuesTotal;
  final Map<String, int> jours;

  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int vuesDepuis(int days) {
    final cut = DateTime.now().subtract(Duration(days: days - 1));
    final cutDay = DateTime(cut.year, cut.month, cut.day);
    var s = 0;
    jours.forEach((k, v) {
      final d = DateTime.tryParse(k);
      if (d != null && !d.isBefore(cutDay)) s += v;
    });
    return s;
  }

  /// Série journalière des `days` derniers jours (du plus ancien au plus récent).
  List<int> serie(int days) {
    final now = DateTime.now();
    return [
      for (var i = days - 1; i >= 0; i--)
        jours[key(now.subtract(Duration(days: i)))] ?? 0,
    ];
  }

  static AnnonceStats? fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    if (!d.exists) return null;
    final m = d.data() ?? const {};
    final j = <String, int>{};
    (m['jours'] as Map?)?.forEach((k, v) {
      if (v is num) j[k.toString()] = v.toInt();
    });
    return AnnonceStats((m['vues_total'] as num?)?.toInt() ?? 0, j);
  }
}

class ResaStat {
  ResaStat({
    required this.houseId,
    required this.status,
    required this.type,
    required this.prix,
  });
  final String houseId;
  final String status;
  final String type;
  final double prix;

  bool get annulee => status == 'Annulée';
  bool get compteConversion => !annulee && type != 'Reservation visite';
  bool get aRapporte =>
      status == 'Réservée' || status == 'Soldée' || status == 'Terminée';

  static ResaStat fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final hr = m['HouseRef'];
    return ResaStat(
      houseId: hr is DocumentReference ? hr.id : '',
      status: (m['Status'] as String?)?.trim() ?? '',
      type: (m['Types'] as String?)?.trim() ?? '',
      prix: (m['prix'] as num?)?.toDouble() ?? 0,
    );
  }
}

class StatsRepository {
  StatsRepository(this.partenaireRef);
  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final _db = FirebaseFirestore.instance;

  Stream<AnnonceStats?> statsFor(String houseId) => _db
      .collection('annonce_stats')
      .doc(houseId)
      .snapshots()
      .map(AnnonceStats.fromDoc);

  /// Toutes les stats du parc du partenaire, indexées par houseId.
  /// `where partenaire_ref ==` satisfait la règle Firestore (lecture hôte).
  Stream<Map<String, AnnonceStats>> allStats() => _db
      .collection('annonce_stats')
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(500)
      .snapshots()
      .map((s) => {
            for (final d in s.docs)
              d.id: AnnonceStats.fromDoc(d) ?? AnnonceStats(0, const {}),
          });

  Stream<List<ResaStat>> allReservations() => _db
      .collection('Reservation')
      .where('proprietaire_ref', isEqualTo: partenaireRef)
      .limit(400)
      .snapshots()
      .map((s) => s.docs.map(ResaStat.fromDoc).toList());

  Stream<List<ResaStat>> reservationsFor(String houseId) => _db
      .collection('Reservation')
      .where('proprietaire_ref', isEqualTo: partenaireRef)
      .limit(300)
      .snapshots()
      .map((s) => s.docs
          .map(ResaStat.fromDoc)
          .where((r) => r.houseId == houseId)
          .toList());
}
