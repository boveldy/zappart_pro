import 'package:cloud_firestore/cloud_firestore.dart';

/// Plage de dates occupées (bornes incluses).
class DateRangeInc {
  DateRangeInc(this.start, this.end);
  final DateTime start;
  final DateTime end; // inclus

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(_d(start)) && !d.isAfter(_d(end));
  }

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
}

/// Un bien pour la vue calendrier.
class CalBien {
  CalBien({
    required this.id,
    required this.titre,
    required this.locationType,
    required this.image,
    required this.statutValidation,
    required this.active,
    required this.blocked,
    required this.icalUrls,
  });

  final String id;
  final String titre;
  final String locationType; // 'Journalier' | 'Mensuel'
  final String? image;
  final String statutValidation;
  final bool active;

  bool get enLigne => active && statutValidation == 'validee';
  bool get archivee => statutValidation == 'supprimee';

  /// `house.blockedRanges` — déjà fusionné backend (réservations Zappart
  /// internes + calendriers externes Airbnb/Booking). Borne `fin` = veille du
  /// départ, incluse.
  final List<DateRangeInc> blocked;
  final List<String> icalUrls;

  bool get isJournalier => locationType == 'Journalier';

  bool occupeLe(DateTime day) => blocked.any((r) => r.contains(day));

  static CalBien fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    final ranges = <DateRangeInc>[];
    for (final raw in (m['blockedRanges'] as List? ?? const [])) {
      if (raw is Map) {
        final a = ts(raw['debut']);
        final b = ts(raw['fin']);
        if (a != null && b != null) ranges.add(DateRangeInc(a, b));
      }
    }
    final imgs =
        (m['image'] as List?)?.whereType<String>().toList() ?? const [];
    final q = (m['quartier'] as String?)?.trim() ?? '';
    final c = (m['cite'] as String?)?.trim() ?? '';
    final n = (m['numbien'] as num?)?.toInt();
    final lieu = [q, c].where((e) => e.isNotEmpty).join(' — ');
    return CalBien(
      id: d.id,
      titre: (lieu.isEmpty ? 'Logement' : lieu) + (n != null ? ' · #$n' : ''),
      locationType: (m['locationtype'] as String?)?.trim() ?? '',
      image: imgs.isNotEmpty ? imgs.first : null,
      statutValidation: (m['statut_validation'] as String?)?.trim() ?? '',
      active: m['active'] == true,
      blocked: ranges,
      icalUrls:
          (m['ical_urls'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

/// Un séjour Zappart sur un bien (superposé au calendrier pour montrer le
/// client et le statut). Journalier + mensuel, hors annulé/terminé.
class CalSejour {
  CalSejour({
    required this.houseId,
    required this.clientNom,
    required this.start,
    required this.end,
    required this.status,
    required this.mensuel,
  });

  final String houseId;
  final String clientNom;
  final DateTime? start;
  final DateTime? end; // dateSorti (départ, exclu pour le journalier)
  final String status;
  final bool mensuel;

  bool couvre(DateTime day) {
    if (start == null) return false;
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(start!.year, start!.month, start!.day);
    if (d.isBefore(s)) return false;
    if (end == null) return true; // mensuel en cours, pas de fin
    final e = DateTime(end!.year, end!.month, end!.day);
    return d.isBefore(e); // départ exclu
  }

  static CalSejour? fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final type = (m['Types'] as String?)?.trim() ?? '';
    final status = (m['Status'] as String?)?.trim() ?? '';
    if (type == 'Reservation visite' || type == 'Reservation service') {
      return null;
    }
    if (status == 'Annulée' || status == 'Terminée') return null;
    DateTime? tsd(dynamic v) => v is Timestamp ? v.toDate() : null;
    final hr = m['HouseRef'];
    return CalSejour(
      houseId: hr is DocumentReference ? hr.id : '',
      clientNom: (m['client_nom'] as String?)?.trim() ?? 'Client',
      start: tsd(m['dateDebut']),
      end: tsd(m['dateSorti']),
      status: status,
      mensuel: type == 'Reservation mensuelle',
    );
  }
}

class CalendarRepository {
  CalendarRepository(this.partenaireRef);
  final DocumentReference<Map<String, dynamic>> partenaireRef;
  final _db = FirebaseFirestore.instance;

  Stream<List<CalBien>> biens() => _db
      .collection('house')
      .where('partenaireId', isEqualTo: partenaireRef)
      .limit(500)
      .snapshots()
      .map((s) =>
          s.docs.map(CalBien.fromDoc).where((b) => !b.archivee).toList());

  Stream<List<CalSejour>> sejours() => _db
      .collection('Reservation')
      .where('proprietaire_ref', isEqualTo: partenaireRef)
      .limit(300)
      .snapshots()
      .map((s) =>
          s.docs.map(CalSejour.fromDoc).whereType<CalSejour>().toList());

  /// Calendriers externes (Airbnb/Booking) — l'hôte gère SES liens .ics, max 4.
  /// Règle Firestore : modification de `ical_urls` seul, quel que soit le statut.
  Future<void> setIcalUrls(String houseId, List<String> urls) => _db
      .collection('house')
      .doc(houseId)
      .update({'ical_urls': urls.where((u) => u.trim().isNotEmpty).toList()});
}
