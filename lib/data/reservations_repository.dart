import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/functions.dart';

/// Une réservation sur un logement de l'hôte (`proprietaire_ref`).
class ResaFull {
  ResaFull({
    required this.id,
    required this.type,
    required this.status,
    required this.accordHote,
    required this.clientNom,
    required this.prix,
    required this.dateDebut,
    required this.dateSorti,
    required this.dateCreated,
    required this.houseId,
    required this.signature,
    required this.decisionClient,
  });

  final String id;
  final String type; // 'Reservation visite' | 'Reservation journalière' | 'Reservation mensuelle' | 'Reservation service'
  final String status; // 'En attente' | 'Réservée' | 'Soldée' | 'Terminée' | 'Annulée'
  final String accordHote; // 'en_attente' | 'accepte' | 'refuse' | ''
  final String clientNom;
  final double? prix;
  final DateTime? dateDebut;
  final DateTime? dateSorti;
  final DateTime? dateCreated;
  final String? houseId;
  final bool signature;
  final String decisionClient; // '' | 'accepte' | 'refuser' | 'reflechir'

  static const _accordables = {'Reservation visite', 'Reservation journalière'};
  static const _clos = {'Terminée', 'Annulée'};

  bool get demandeAccord =>
      accordHote == 'en_attente' && _accordables.contains(type);

  bool get clos => _clos.contains(status);

  bool get aVenir {
    if (clos) return false;
    final ref = dateSorti ?? dateDebut;
    return ref != null && ref.isAfter(DateTime.now());
  }

  String get typeCourt => switch (type) {
        'Reservation visite' => 'Visite',
        'Reservation journalière' => 'Journalier',
        'Reservation mensuelle' => 'Mensuel',
        'Reservation service' => 'Service',
        _ => type.replaceFirst('Reservation ', ''),
      };

  ({String label, String tone}) get statutBadge {
    if (demandeAccord) return (label: "Demande d'accord", tone: 'wait');
    return switch (status) {
      'En attente' => (label: 'En attente', tone: 'wait'),
      'Réservée' => (label: 'Réservée', tone: 'ink'),
      'Soldée' => (label: 'Soldée', tone: 'ok'),
      'Terminée' => (label: 'Terminée', tone: 'muted'),
      'Annulée' => (label: 'Annulée', tone: 'danger'),
      _ => (label: status.isEmpty ? '—' : status, tone: 'muted'),
    };
  }

  static ResaFull fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    final hr = m['HouseRef'];
    return ResaFull(
      id: d.id,
      type: (m['Types'] as String?)?.trim() ?? '',
      status: (m['Status'] as String?)?.trim() ?? '',
      accordHote: (m['accord_hote'] as String?)?.trim() ?? '',
      clientNom: (m['client_nom'] as String?)?.trim() ?? 'Client',
      prix: (m['prix'] as num?)?.toDouble(),
      dateDebut: ts(m['dateDebut']),
      dateSorti: ts(m['dateSorti']),
      dateCreated: ts(m['datecreated']),
      houseId: hr is DocumentReference ? hr.id : null,
      signature: m['signature'] == true,
      decisionClient: (m['decision_client'] as String?)?.trim() ?? '',
    );
  }
}

class ReservationsRepository {
  ReservationsRepository(this.partenaireRef);
  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final _db = FirebaseFirestore.instance;

  Stream<List<ResaFull>> reservations() => _db
      .collection('Reservation')
      .where('proprietaire_ref', isEqualTo: partenaireRef)
      .limit(200)
      .snapshots()
      .map((s) {
        final list = s.docs.map(ResaFull.fromDoc).toList();
        list.sort((a, b) => (b.dateCreated ?? DateTime(2000))
            .compareTo(a.dateCreated ?? DateTime(2000)));
        return list;
      });

  /// Titre lisible par bien (pour la colonne « Logement »).
  Stream<Map<String, String>> houseTitles() => _db
      .collection('house')
      .where('partenaireId', isEqualTo: partenaireRef)
      .limit(500)
      .snapshots()
      .map((s) => {
            for (final d in s.docs)
              d.id: _titre(d.data()),
          });

  static String _titre(Map<String, dynamic> m) {
    final q = (m['quartier'] as String?)?.trim() ?? '';
    final c = (m['cite'] as String?)?.trim() ?? '';
    final n = (m['numbien'] as num?)?.toInt();
    final lieu = [q, c].where((e) => e.isNotEmpty).join(' — ');
    return (lieu.isEmpty ? 'Logement' : lieu) + (n != null ? ' · #$n' : '');
  }

  /// Répond à une demande d'accord de disponibilité. [reponse] = 'accepte' |
  /// 'refuse'. Retourne `null` si succès, sinon un message d'erreur.
  Future<String?> repondre(String reservationId, String reponse) async {
    try {
      final res = await cloudFunction('reservations').call({
        'action': 'repondre_disponibilite',
        'reservation_id': reservationId,
        'reponse': reponse,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      final statut = data['statut']?.toString() ?? '';
      if (statut == 'succès' || statut == 'succes') return null;
      return data['message']?.toString() ?? 'Échec de la réponse.';
    } catch (_) {
      return 'Erreur de connexion. Vérifiez votre réseau.';
    }
  }
}
