import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/download.dart';
import '../../data/bail.dart';

/// Quittance de loyer en PDF — générée à la volée (pas stockée), téléchargée
/// par le navigateur. Style sobre, charte Zappart.
class BailQuittance {
  static final _df = DateFormat('d MMMM yyyy', 'fr');
  static final _fmt = NumberFormat('#,###', 'fr_FR');

  static Future<void> generer({
    required Bail bail,
    required Echeance echeance,
    required String agence,
    String? refInterne,
  }) async {
    final doc = pw.Document();
    final loyer = echeance.montantLoyer;
    final charges = echeance.montantCharges;
    final total = echeance.montantPaye > 0 ? echeance.montantPaye : echeance.montantDu;
    final paiement = echeance.datePaiement ?? DateTime.now();

    doc.addPage(
      pw.Page(
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
                  child: pw.Text('QUITTANCE DE LOYER',
                      style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
                'N° ${refInterne ?? echeance.periode} · émise le ${_df.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 28),
            pw.Text('Période : ${echeance.periodeLabel}',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Logement : ${bail.bienTitre}',
                style: const pw.TextStyle(fontSize: 11)),
            pw.Text('Locataire : ${bail.locataireNom}',
                style: const pw.TextStyle(fontSize: 11)),
            if (bail.proprietaireNom.isNotEmpty)
              pw.Text('Propriétaire : ${bail.proprietaireNom}',
                  style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 22),
            _ligne('Loyer', loyer),
            if (charges > 0) _ligne('Charges (forfait)', charges),
            pw.Divider(),
            _ligne('Total réglé', total, bold: true),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'Je soussigné, gérant pour le compte du propriétaire, reconnais avoir '
                'reçu de ${bail.locataireNom} la somme de ${_fmt.format(total.round())} FCFA '
                'au titre du loyer${charges > 0 ? ' et des charges' : ''} du logement '
                '« ${bail.bienTitre} » pour la période de ${echeance.periodeLabel}, '
                'et lui en donne quittance sous réserve de tous mes droits.\n\n'
                'Paiement reçu le ${_df.format(paiement)}'
                '${echeance.methode.isNotEmpty ? ' par ${echeance.methode}' : ''}.',
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
              ),
            ),
            pw.SizedBox(height: 30),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Fait à Dakar, le ${_df.format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.Column(children: [
                  pw.Text('Le gérant',
                      style: const pw.TextStyle(fontSize: 10)),
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
      ),
    );

    final stamp = echeance.periode.replaceAll('-', '');
    downloadBytes('quittance-${_slug(bail.locataireNom)}-$stamp.pdf',
        await doc.save(), 'application/pdf');
  }

  static pw.Widget _ligne(String label, double montant, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: bold ? 12 : 11,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text('${_fmt.format(montant.round())} FCFA',
                style: pw.TextStyle(
                    fontSize: bold ? 12 : 11,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
