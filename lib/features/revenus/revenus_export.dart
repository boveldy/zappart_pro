import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/revenus_repository.dart';

/// Construit un relevé de revenus (CSV / Excel / PDF) à partir des lignes déjà
/// filtrées par période. Colonnes communes : Date · Sens · Libellé · Montant ·
/// Statut · Méthode · Référence.
class RevenusExport {
  RevenusExport({
    required this.ledger,
    required this.retraits,
    required this.periodeLabel,
    required this.partenaire,
  });

  final List<LedgerEntry> ledger;
  final List<RetraitEntry> retraits;
  final String periodeLabel;
  final String partenaire;

  static final _df = DateFormat('yyyy-MM-dd HH:mm');
  static final _dfHuman = DateFormat('d MMM yyyy', 'fr');
  static final _fmt = NumberFormat('#,###', 'fr_FR');

  static const _headers = [
    'Date',
    'Sens',
    'Libellé',
    'Montant (FCFA)',
    'Statut',
    'Méthode',
    'Référence',
  ];

  /// Lignes de données (montants signés : crédit +, retrait −).
  List<({DateTime? date, String sens, String libelle, int montant, String statut, String methode, String ref})>
      get _lignes {
    final out = [
      for (final l in ledger.where((l) => l.actif))
        (
          date: l.date,
          sens: 'Crédit',
          libelle: l.typeLabel,
          montant: l.montant.round(),
          statut: l.enAttente ? 'En attente' : 'Disponible',
          methode: l.methode,
          ref: l.reference,
        ),
      for (final r in retraits)
        (
          date: r.date,
          sens: 'Retrait',
          libelle: 'Retrait ${r.methodeLabel} ${r.numeroMasque}',
          montant: -r.montant,
          statut: r.badge.label,
          methode: r.methodeLabel,
          ref: r.preuve,
        ),
    ]..sort((a, b) =>
        (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    return out;
  }

  int get _totalCredit => ledger
      .where((l) => l.actif)
      .fold(0, (a, l) => a + l.montant.round());
  int get _totalRetraits =>
      retraits.where((r) => r.status == 'paye').fold(0, (a, r) => a + r.montant);

  String _stamp() => DateFormat('yyyyMMdd').format(DateTime.now());

  // ── CSV ──
  String csv() {
    final rows = <String>[_headers.join(';')];
    for (final l in _lignes) {
      rows.add([
        l.date == null ? '' : _df.format(l.date!),
        l.sens,
        l.libelle,
        l.montant,
        l.statut,
        l.methode,
        l.ref,
      ].join(';'));
    }
    return rows.join('\r\n');
  }

  String csvName() => 'zappart-revenus-${_stamp()}.csv';

  // ── Excel (.xlsx) ──
  List<int> xlsx() {
    final ex = Excel.createExcel();
    final name = 'Revenus';
    final sheet = ex[name];
    ex.setDefaultSheet(name);
    for (final s in ex.sheets.keys.where((k) => k != name).toList()) {
      ex.delete(s);
    }

    sheet.appendRow([
      TextCellValue('Relevé Zappart — $partenaire — $periodeLabel'),
    ]);
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([for (final h in _headers) TextCellValue(h)]);
    for (final l in _lignes) {
      sheet.appendRow([
        TextCellValue(l.date == null ? '' : _dfHuman.format(l.date!)),
        TextCellValue(l.sens),
        TextCellValue(l.libelle),
        IntCellValue(l.montant),
        TextCellValue(l.statut),
        TextCellValue(l.methode),
        TextCellValue(l.ref),
      ]);
    }
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([
      TextCellValue('Total encaissé'),
      TextCellValue(''),
      TextCellValue(''),
      IntCellValue(_totalCredit),
    ]);
    sheet.appendRow([
      TextCellValue('Total retraits payés'),
      TextCellValue(''),
      TextCellValue(''),
      IntCellValue(-_totalRetraits),
    ]);
    return ex.save() ?? <int>[];
  }

  String xlsxName() => 'zappart-revenus-${_stamp()}.xlsx';

  // ── PDF ──
  Future<List<int>> pdf() async {
    final doc = pw.Document();
    final data = _lignes
        .map((l) => [
              l.date == null ? '' : _dfHuman.format(l.date!),
              l.sens,
              l.libelle,
              '${l.montant >= 0 ? '+' : '−'} ${_fmt.format(l.montant.abs())}',
              l.statut,
              l.methode,
            ])
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text('Relevé de revenus',
              style:
                  pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('$partenaire · $periodeLabel',
              style: const pw.TextStyle(
                  fontSize: 11, color: PdfColors.grey700)),
          pw.Text(
              'Édité le ${_dfHuman.format(DateTime.now())} · via Zappart Pro',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey500)),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Sens',
              'Libellé',
              'Montant',
              'Statut',
              'Méthode'
            ],
            data: data,
            headerStyle: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {3: pw.Alignment.centerRight},
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(3),
            },
          ),
          pw.SizedBox(height: 18),
          pw.Divider(),
          _totalRow('Total encaissé', _totalCredit),
          _totalRow('Total retraits payés', -_totalRetraits),
        ],
      ),
    );
    return doc.save();
  }

  String pdfName() => 'zappart-revenus-${_stamp()}.pdf';

  pw.Widget _totalRow(String label, int montant) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
            pw.Text('${montant >= 0 ? '+' : '−'} ${_fmt.format(montant.abs())} FCFA',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
}
