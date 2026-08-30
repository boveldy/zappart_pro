import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/functions.dart';

/// Une ligne d'encaissement (`wallet_ledger`) — part partenaire captée en ligne
/// (journalier / service).
class LedgerEntry {
  LedgerEntry({
    required this.montant,
    required this.type,
    required this.statut,
    required this.methode,
    required this.reference,
    required this.date,
  });

  final double montant;
  final String type; // 'journalier' | 'service'
  final String statut; // 'en_attente' | 'disponible' | 'annulee'
  final String methode;
  final String reference;
  final DateTime? date;

  bool get enAttente => statut == 'en_attente';
  bool get actif => statut != 'annulee';

  String get typeLabel => switch (type) {
        'journalier' => 'Séjour journalier',
        'service' => 'Prestation',
        _ => type.isEmpty ? 'Encaissement' : type,
      };

  static LedgerEntry fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return LedgerEntry(
      montant: (m['montant'] as num?)?.toDouble() ?? 0,
      type: (m['type'] as String?)?.trim() ?? '',
      statut: (m['statut'] as String?)?.trim() ?? 'en_attente',
      methode: (m['methode'] as String?)?.trim() ?? '',
      reference: (m['reference_paiement'] as String?)?.trim() ?? '',
      date: m['date_encaissement'] is Timestamp
          ? (m['date_encaissement'] as Timestamp).toDate()
          : null,
    );
  }
}

/// Une demande de retrait (`retraits_partenaires`).
class RetraitEntry {
  RetraitEntry({
    required this.montant,
    required this.methode,
    required this.numero,
    required this.status,
    required this.preuve,
    required this.motif,
    required this.date,
  });

  final int montant;
  final String methode;
  final String numero;
  final String status; // a_payer | paye | rejete
  final String preuve;
  final String motif;
  final DateTime? date;

  String get methodeLabel => switch (methode) {
        'wave' => 'Wave',
        'orange_money' => 'Orange Money',
        _ => methode,
      };

  String get numeroMasque {
    final n = numero.replaceAll(' ', '');
    return n.length < 4 ? numero : '••• ${n.substring(n.length - 4)}';
  }

  ({String label, String tone}) get badge => switch (status) {
        'paye' => (label: 'Payé', tone: 'ok'),
        'rejete' => (label: 'Rejeté', tone: 'muted'),
        _ => (label: 'En cours', tone: 'wait'),
      };

  static RetraitEntry fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return RetraitEntry(
      montant: (m['montant'] as num?)?.toInt() ?? 0,
      methode: (m['methode'] as String?)?.trim() ?? '',
      numero: (m['numero'] as String?)?.trim() ?? '',
      status: (m['status'] as String?)?.trim() ?? 'a_payer',
      preuve: (m['preuve'] as String?)?.trim() ?? '',
      motif: (m['motif_rejet'] as String?)?.trim() ?? '',
      date: m['date'] is Timestamp ? (m['date'] as Timestamp).toDate() : null,
    );
  }
}

class RevenusRepository {
  RevenusRepository(this.partenaireRef);
  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final _db = FirebaseFirestore.instance;

  Stream<int> soldeDisponible() => partenaireRef.snapshots().map(
      (s) => ((s.data() ?? const {})['solde_disponible'] as num?)?.toInt() ?? 0);

  Stream<List<LedgerEntry>> ledger() => _db
      .collection('wallet_ledger')
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map(LedgerEntry.fromDoc).toList());

  Stream<List<RetraitEntry>> retraits() => _db
      .collection('retraits_partenaires')
      .where('partenaire_ref', isEqualTo: partenaireRef)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(RetraitEntry.fromDoc).toList());

  /// Demande de retrait via le callable `partenaire_wallet` (le backend valide
  /// le solde et réserve le montant).
  Future<({bool ok, String message})> demanderRetrait({
    required int montant,
    required String methode,
    required String numero,
  }) async {
    try {
      final res = await cloudFunction('partenaire_wallet').call({
        'action': 'demander_retrait',
        'montant': montant,
        'methode': methode,
        'numero': numero,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return (
        ok: data['statut'] == 'succes',
        message: (data['message'] ?? '').toString(),
      );
    } catch (e) {
      return (ok: false, message: 'Une erreur est survenue. Réessayez.');
    }
  }
}
