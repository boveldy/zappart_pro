import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/download.dart';
import '../../data/bail.dart';

/// Relevé de gérance d'un bail sur une période : loyers encaissés − commission
/// d'agence − dépenses imputées au propriétaire = net à reverser. Généré à la
/// volée (PDF ou Excel), jamais stocké.
class BailReleve {
  static final _df = DateFormat('d MMM yyyy', 'fr');
  static final _dfLong = DateFormat('d MMMM yyyy', 'fr');
  static final _fmt = NumberFormat('#,###', 'fr_FR');

  /// Échéances réglées dont le paiement tombe dans [debut, fin].
  static List<Echeance> _encaissees(
      List<Echeance> echeances, DateTime debut, DateTime fin) {
    final f = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);
    return echeances.where((e) {
      if (e.statutBrut != 'paye' && e.statutBrut != 'partiel') return false;
      final d = e.datePaiement ?? e.dateEcheance;
      if (d == null) return false;
      return !d.isBefore(debut) && !d.isAfter(f);
    }).toList()
      ..sort((a, b) => a.periode.compareTo(b.periode));
  }

  static List<Depense> _depPeriode(
      List<Depense> depenses, DateTime debut, DateTime fin) {
    final f = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);
    return depenses.where((d) {
      final x = d.date;
      if (x == null) return false;
      return !x.isBefore(debut) && !x.isAfter(f);
    }).toList()
      ..sort((a, b) => (a.date ?? DateTime(2000)).compareTo(b.date ?? DateTime(2000)));
  }

  static double _montantEncaisse(Echeance e) =>
      e.montantPaye > 0 ? e.montantPaye : e.montantDu;

  static ({
    double loyers,
    double commission,
    double depProprio,
    double depLocataire,
    double net,
    int nbLoyers,
  }) _calc({
    required Bail bail,
    required List<Echeance> enc,
    required List<Depense> dep,
  }) {
    final loyers = enc.fold<double>(0, (a, e) => a + _montantEncaisse(e));
    final commission = switch (bail.commissionMode) {
      'pourcentage' => loyers * bail.commissionValeur / 100,
      'fixe' => bail.commissionValeur * enc.length,
      _ => 0.0,
    };
    final depProprio = dep
        .where((d) => d.charge == DepenseCharge.proprietaire)
        .fold<double>(0, (a, d) => a + d.montant);
    final depLocataire = dep
        .where((d) => d.charge == DepenseCharge.locataire)
        .fold<double>(0, (a, d) => a + d.montant);
    return (
      loyers: loyers,
      commission: commission,
      depProprio: depProprio,
      depLocataire: depLocataire,
      net: loyers - commission - depProprio,
      nbLoyers: enc.length,
    );
  }

  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static Future<void> generer({
    required Bail bail,
    required List<Echeance> echeances,
    required List<Depense> depenses,
    required String agence,
    required DateTime debut,
    required DateTime fin,
    required String periodeLabel,
    required bool excel,
  }) async {
    final enc = _encaissees(echeances, debut, fin);
    final dep = _depPeriode(depenses, debut, fin);
    final c = _calc(bail: bail, enc: enc, dep: dep);
    final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
    final base = 'releve-gerance-${_slug(bail.bienTitre.isEmpty ? bail.locataireNom : bail.bienTitre)}-$stamp';

    if (excel) {
      downloadBytes('$base.xlsx',
          _xlsx(bail, agence, periodeLabel, enc, dep, c), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    } else {
      downloadBytes('$base.pdf',
          await _pdf(bail, agence, periodeLabel, debut, fin, enc, dep, c),
          'application/pdf');
    }
  }

  /// Relevé consolidé de tous les baux d'un même propriétaire sur une période.
  /// `echeances` et `depenses` sont les listes complètes du partenaire ; le
  /// filtrage par bail se fait ici.
  static Future<void> parProprietaire({
    required String proprietaire,
    required List<Bail> baux,
    required List<Echeance> echeances,
    required List<Depense> depenses,
    required String agence,
    required DateTime debut,
    required DateTime fin,
    required String periodeLabel,
    required bool excel,
  }) async {
    final lignes = <({Bail bail, List<Echeance> enc, List<Depense> dep, ({double loyers, double commission, double depProprio, double depLocataire, double net, int nbLoyers}) c})>[];
    for (final b in baux) {
      final enc = _encaissees(
          echeances.where((e) => e.bailRefId == b.id).toList(), debut, fin);
      final dep = _depPeriode(
          depenses.where((d) => d.bailRefId == b.id).toList(), debut, fin);
      lignes.add((bail: b, enc: enc, dep: dep, c: _calc(bail: b, enc: enc, dep: dep)));
    }
    final totLoyers = lignes.fold<double>(0, (a, l) => a + l.c.loyers);
    final totComm = lignes.fold<double>(0, (a, l) => a + l.c.commission);
    final totDep = lignes.fold<double>(0, (a, l) => a + l.c.depProprio);
    final totNet = totLoyers - totComm - totDep;
    final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
    final base = 'releve-proprietaire-${_slug(proprietaire)}-$stamp';

    if (excel) {
      final ex = Excel.createExcel();
      const name = 'Relevé';
      final s = ex[name];
      ex.setDefaultSheet(name);
      for (final k in ex.sheets.keys.where((k) => k != name).toList()) {
        ex.delete(k);
      }
      s.appendRow([TextCellValue('Relevé de gérance — $agence')]);
      s.appendRow([TextCellValue('Propriétaire'), TextCellValue(proprietaire)]);
      s.appendRow([TextCellValue('Période'), TextCellValue(periodeLabel)]);
      s.appendRow([TextCellValue('')]);
      s.appendRow([
        TextCellValue('Bien'),
        TextCellValue('Locataire'),
        TextCellValue('Loyers encaissés'),
        TextCellValue('Commission'),
        TextCellValue('Dépenses'),
        TextCellValue('Net à reverser'),
      ]);
      for (final l in lignes) {
        s.appendRow([
          TextCellValue(l.bail.bienTitre),
          TextCellValue(l.bail.locataireNom),
          IntCellValue(l.c.loyers.round()),
          IntCellValue(-l.c.commission.round()),
          IntCellValue(-l.c.depProprio.round()),
          IntCellValue(l.c.net.round()),
        ]);
      }
      s.appendRow([TextCellValue('')]);
      s.appendRow([
        TextCellValue('TOTAL'),
        TextCellValue(''),
        IntCellValue(totLoyers.round()),
        IntCellValue(-totComm.round()),
        IntCellValue(-totDep.round()),
        IntCellValue(totNet.round()),
      ]);
      downloadBytes('$base.xlsx', ex.save() ?? <int>[],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      return;
    }

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(38),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(agence,
                  style: pw.TextStyle(
                      fontSize: 15, fontWeight: pw.FontWeight.bold)),
              pw.Text('Gérance locative',
                  style:
                      const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            ]),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey900,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text('RELEVÉ PROPRIÉTAIRE',
                  style: pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text('$proprietaire  ·  période : $periodeLabel',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Text('Édité le ${_dfLong.format(DateTime.now())} · via Zappart Pro',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Bien',
            'Locataire',
            'Loyers',
            'Commission',
            'Dépenses',
            'Net à reverser'
          ],
          data: [
            for (final l in lignes)
              [
                l.bail.bienTitre,
                l.bail.locataireNom,
                _fmt.format(l.c.loyers.round()),
                '− ${_fmt.format(l.c.commission.round())}',
                '− ${_fmt.format(l.c.depProprio.round())}',
                _fmt.format(l.c.net.round()),
              ],
          ],
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(children: [
            _totLine('Loyers encaissés', totLoyers),
            _totLine('Commission de gérance', -totComm),
            _totLine('Dépenses à la charge du propriétaire', -totDep),
            pw.Divider(),
            _totLine('NET À REVERSER', totNet, bold: true),
          ]),
        ),
      ],
    ));
    downloadBytes('$base.pdf', await doc.save(), 'application/pdf');
  }

  static pw.Widget _totLine(String l, double v, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(l,
                style: pw.TextStyle(
                    fontSize: bold ? 12 : 10.5,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text('${_fmt.format(v.round())} FCFA',
                style: pw.TextStyle(
                    fontSize: bold ? 12 : 10.5,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  // ── PDF ──────────────────────────────────────────────────────────────────
  static Future<List<int>> _pdf(
    Bail bail,
    String agence,
    String periodeLabel,
    DateTime debut,
    DateTime fin,
    List<Echeance> enc,
    List<Depense> dep,
    ({double loyers, double commission, double depProprio, double depLocataire, double net, int nbLoyers}) c,
  ) async {
    final doc = pw.Document();
    pw.Widget money(String label, double v, {bool bold = false, bool minus = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: bold ? 12 : 10.5,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.Text('${minus && v > 0 ? '− ' : ''}${_fmt.format(v.round())} FCFA',
                  style: pw.TextStyle(
                      fontSize: bold ? 12 : 10.5,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(agence,
                    style: pw.TextStyle(
                        fontSize: 15, fontWeight: pw.FontWeight.bold)),
                pw.Text('Gérance locative',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600)),
              ]),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey900,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text('RELEVÉ DE GÉRANCE',
                    style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
              'Période : $periodeLabel  ·  édité le ${_dfLong.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 20),
          pw.Text('Logement : ${bail.bienTitre}',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Locataire : ${bail.locataireNom}',
              style: const pw.TextStyle(fontSize: 11)),
          if (bail.proprietaireNom.isNotEmpty)
            pw.Text('Propriétaire : ${bail.proprietaireNom}',
                style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Commission de gérance : ${bail.commissionLabel}',
              style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 20),

          pw.Text('Loyers encaissés',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (enc.isEmpty)
            pw.Text('Aucun loyer encaissé sur la période.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Période', 'Encaissé le', 'Méthode', 'Montant'],
              data: [
                for (final e in enc)
                  [
                    e.periodeLabel,
                    e.datePaiement == null ? '—' : _df.format(e.datePaiement!),
                    e.methode.isEmpty ? '—' : e.methode,
                    '${_fmt.format(_montantEncaisse(e).round())} FCFA',
                  ],
              ],
              headerStyle:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: {3: pw.Alignment.centerRight},
            ),

          pw.SizedBox(height: 16),
          pw.Text('Dépenses imputées',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (dep.isEmpty)
            pw.Text('Aucune dépense sur la période.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Catégorie', 'Libellé', 'À la charge de', 'Montant'],
              data: [
                for (final d in dep)
                  [
                    d.date == null ? '—' : _df.format(d.date!),
                    d.categorie,
                    d.libelle,
                    depenseChargeCourt(d.charge),
                    '${_fmt.format(d.montant.round())} FCFA',
                  ],
              ],
              headerStyle:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: {4: pw.Alignment.centerRight},
              columnWidths: {2: const pw.FlexColumnWidth(3)},
            ),

          pw.SizedBox(height: 22),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(children: [
              money('Loyers encaissés (${c.nbLoyers})', c.loyers),
              money('Commission de gérance', c.commission, minus: true),
              money('Dépenses à la charge du propriétaire', c.depProprio,
                  minus: true),
              pw.Divider(),
              money('NET À REVERSER AU PROPRIÉTAIRE', c.net, bold: true),
            ]),
          ),
          if (c.depLocataire > 0) ...[
            pw.SizedBox(height: 10),
            pw.Text(
                'Pour information — à refacturer au locataire : '
                '${_fmt.format(c.depLocataire.round())} FCFA',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
          pw.SizedBox(height: 26),
          pw.Text('Document généré via Zappart Pro',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ],
      ),
    );
    return doc.save();
  }

  // ── Excel ────────────────────────────────────────────────────────────────
  static List<int> _xlsx(
    Bail bail,
    String agence,
    String periodeLabel,
    List<Echeance> enc,
    List<Depense> dep,
    ({double loyers, double commission, double depProprio, double depLocataire, double net, int nbLoyers}) c,
  ) {
    final ex = Excel.createExcel();
    const name = 'Relevé';
    final s = ex[name];
    ex.setDefaultSheet(name);
    for (final k in ex.sheets.keys.where((k) => k != name).toList()) {
      ex.delete(k);
    }

    s.appendRow([TextCellValue('Relevé de gérance — $agence')]);
    s.appendRow([TextCellValue('Logement'), TextCellValue(bail.bienTitre)]);
    s.appendRow([TextCellValue('Locataire'), TextCellValue(bail.locataireNom)]);
    s.appendRow(
        [TextCellValue('Propriétaire'), TextCellValue(bail.proprietaireNom)]);
    s.appendRow([TextCellValue('Période'), TextCellValue(periodeLabel)]);
    s.appendRow([TextCellValue('')]);

    s.appendRow([TextCellValue('LOYERS ENCAISSÉS')]);
    s.appendRow([
      TextCellValue('Période'),
      TextCellValue('Encaissé le'),
      TextCellValue('Méthode'),
      TextCellValue('Montant (FCFA)'),
    ]);
    for (final e in enc) {
      s.appendRow([
        TextCellValue(e.periodeLabel),
        TextCellValue(e.datePaiement == null ? '' : _df.format(e.datePaiement!)),
        TextCellValue(e.methode),
        IntCellValue(_montantEncaisse(e).round()),
      ]);
    }
    s.appendRow([TextCellValue('')]);

    s.appendRow([TextCellValue('DÉPENSES IMPUTÉES')]);
    s.appendRow([
      TextCellValue('Date'),
      TextCellValue('Catégorie'),
      TextCellValue('Libellé'),
      TextCellValue('À la charge de'),
      TextCellValue('Montant (FCFA)'),
    ]);
    for (final d in dep) {
      s.appendRow([
        TextCellValue(d.date == null ? '' : _df.format(d.date!)),
        TextCellValue(d.categorie),
        TextCellValue(d.libelle),
        TextCellValue(depenseChargeCourt(d.charge)),
        IntCellValue(d.montant.round()),
      ]);
    }
    s.appendRow([TextCellValue('')]);

    s.appendRow([TextCellValue('DÉCOMPTE')]);
    s.appendRow([
      TextCellValue('Loyers encaissés'),
      IntCellValue(c.loyers.round())
    ]);
    s.appendRow([
      TextCellValue('Commission de gérance'),
      IntCellValue(-c.commission.round())
    ]);
    s.appendRow([
      TextCellValue('Dépenses propriétaire'),
      IntCellValue(-c.depProprio.round())
    ]);
    s.appendRow(
        [TextCellValue('NET À REVERSER'), IntCellValue(c.net.round())]);
    return ex.save() ?? <int>[];
  }

  // ── Reçu de restitution de caution ───────────────────────────────────────
  static Future<void> recuCaution({
    required Bail bail,
    required String agence,
    required DateTime finDate,
    required double cautionTotale,
    required double restitue,
    required double retenue,
    required String note,
  }) async {
    final doc = pw.Document();
    pw.Widget ligne(String l, double v, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(l,
                  style: pw.TextStyle(
                      fontSize: bold ? 12 : 10.5,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.Text('${_fmt.format(v.round())} FCFA',
                  style: pw.TextStyle(
                      fontSize: bold ? 12 : 10.5,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ],
          ),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(agence,
                    style: pw.TextStyle(
                        fontSize: 15, fontWeight: pw.FontWeight.bold)),
                pw.Text('Gérance locative',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600)),
              ]),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey900,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text('SOLDE DE CAUTION',
                    style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text('Émis le ${_dfLong.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 26),
          pw.Text('Fin de bail : ${_dfLong.format(finDate)}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Logement : ${bail.bienTitre}',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Locataire : ${bail.locataireNom}',
              style: const pw.TextStyle(fontSize: 11)),
          if (bail.proprietaireNom.isNotEmpty)
            pw.Text('Propriétaire : ${bail.proprietaireNom}',
                style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 22),
          ligne('Dépôt de garantie versé', cautionTotale),
          ligne('Retenues', retenue),
          pw.Divider(),
          ligne('Montant restitué au locataire', restitue, bold: true),
          if (note.trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('Détail des retenues',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(note.trim(),
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 2)),
          ],
          pw.SizedBox(height: 30),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'Le présent document constate la fin du bail portant sur le logement '
              '« ${bail.bienTitre} » et le solde du dépôt de garantie. '
              'La somme de ${_fmt.format(restitue.round())} FCFA est restituée au '
              'locataire${retenue > 0 ? ', après retenue de ${_fmt.format(retenue.round())} FCFA' : ''}.',
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
            ),
          ),
          pw.SizedBox(height: 34),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(children: [
                pw.Text('Le locataire',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 30),
                pw.Container(width: 140, height: 1, color: PdfColors.grey400),
              ]),
              pw.Column(children: [
                pw.Text('Le gérant', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 30),
                pw.Container(width: 140, height: 1, color: PdfColors.grey400),
              ]),
            ],
          ),
          pw.Spacer(),
          pw.Text('Document généré via Zappart Pro',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ],
      ),
    ));

    downloadBytes(
        'solde-caution-${_slug(bail.locataireNom)}-${DateFormat('yyyyMMdd').format(finDate)}.pdf',
        await doc.save(),
        'application/pdf');
  }
}
