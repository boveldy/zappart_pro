import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui.dart';
import '../../data/bail.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'bail_quittance.dart';

class FicheBailPage extends StatelessWidget {
  const FicheBailPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null) return const _Shell(child: EmptyState('Session en cours…'));
    final repo = BailRepository(ref);

    return StreamBuilder<Bail?>(
      stream: repo.bail(id),
      builder: (context, bSnap) {
        if (bSnap.hasError) {
          return const _Shell(child: EmptyState('Impossible de charger ce bail.'));
        }
        if (!bSnap.hasData) return const _Shell(child: SkeletonBox(height: 380));
        final bail = bSnap.data;
        if (bail == null) {
          return const _Shell(child: EmptyState('Bail introuvable.'));
        }
        return _Shell(
          child: StreamBuilder<List<Echeance>>(
            stream: repo.echeancesDuBail(id),
            builder: (context, eSnap) => _Content(
              bail: bail,
              echeances: eSnap.data ?? const [],
              repo: repo,
              agence: auth.displayName,
            ),
          ),
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => context.go('/baux'),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Baux'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.inkSoft,
                padding: EdgeInsets.zero,
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}

class _Content extends StatelessWidget {
  const _Content({
    required this.bail,
    required this.echeances,
    required this.repo,
    required this.agence,
  });
  final Bail bail;
  final List<Echeance> echeances;
  final BailRepository repo;
  final String agence;

  static final _fmt = NumberFormat('#,###', 'fr_FR');
  static final _df = DateFormat('d MMM yyyy', 'fr');

  double get _encaisse => echeances
      .where((e) => e.statutBrut == 'paye' || e.statutBrut == 'partiel')
      .fold(0, (a, e) => a + (e.montantPaye > 0 ? e.montantPaye : e.montantDu));

  double get _commission => switch (bail.commissionMode) {
        'pourcentage' => _encaisse * bail.commissionValeur / 100,
        'fixe' => bail.commissionValeur *
            echeances.where((e) => e.statutBrut == 'paye').length,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final left = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 16),
          _conditions(),
          const SizedBox(height: 16),
          _echeancier(context),
        ],
      );
      final right = Column(
        children: [
          _actions(context),
          const SizedBox(height: 14),
          _reversement(),
          const SizedBox(height: 14),
          _locataire(),
        ],
      );
      return wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 20),
                SizedBox(width: 300, child: right),
              ],
            )
          : Column(children: [left, const SizedBox(height: 16), right]);
    });
  }

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(bail.locataireNom, style: AppTheme.h1),
                  const SizedBox(width: 10),
                  StatusChip(
                      bail.actif
                          ? 'Bail actif'
                          : bail.statut == 'resilie'
                              ? 'Résilié'
                              : 'Terminé',
                      tone: bail.actif ? 'ok' : 'muted'),
                ]),
                const SizedBox(height: 3),
                Text(
                  [
                    bail.bienTitre,
                    if (bail.proprietaireNom.isNotEmpty)
                      'Propriétaire : ${bail.proprietaireNom}',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: AppTheme.label,
                ),
                Text(bail.locataireTel,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppTheme.inkSoft)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('LOYER MENSUEL',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                      color: AppTheme.inkSoft)),
              Text('${_fmt.format(bail.loyer.round())} FCFA',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      );

  Widget _conditions() => AppCard(
        title: 'Conditions du bail',
        child: Column(
          children: [
            _kv('Loyer', '${_fmt.format(bail.loyer.round())} FCFA / mois'),
            _kv(
                'Charges',
                bail.chargesMode == ChargesMode.forfait
                    ? '${_fmt.format(bail.charges.round())} FCFA — forfait'
                    : chargesModeLabel(bail.chargesMode)),
            _kv('Caution',
                '${_fmt.format(bail.caution.round())} FCFA (${bail.cautionMois} mois)'),
            _kv('Date d\'entrée',
                bail.dateEntree == null ? '—' : _df.format(bail.dateEntree!)),
            _kv('Durée',
                '${bail.dureeMois} mois — échéance le ${bail.jourEcheance} du mois'),
            _kv('Commission de gérance', bail.commissionLabel, last: true),
          ],
        ),
      );

  Widget _echeancier(BuildContext context) {
    final paye = echeances.where((e) => e.statutBrut == 'paye').length;
    final retard = echeances
        .where((e) => e.statutAffiche() == EStatut.retard)
        .length;
    final du =
        echeances.where((e) => e.statutAffiche() == EStatut.du).length;
    return AppCard(
      title: 'Échéancier',
      trailing: Text(
          '$paye payés · $du dû · $retard retard',
          style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
      child: Column(
        children: [
          for (final e in echeances) _echRow(context, e),
        ],
      ),
    );
  }

  Widget _echRow(BuildContext context, Echeance e) {
    final s = e.statutAffiche();
    final (dotColor, _) = switch (s) {
      EStatut.paye => (const Color(0xFF2F6B45), 0),
      EStatut.partiel => (const Color(0xFF7A5C1F), 0),
      EStatut.du => (const Color(0xFF7A5C1F), 0),
      EStatut.retard => (const Color(0xFF8A4033), 0),
      EStatut.annule => (const Color(0xFFD7D7D7), 0),
      EStatut.aVenir => (const Color(0xFFD7D7D7), 0),
    };
    final r = e.joursDeRetard();
    final sub = switch (s) {
      EStatut.paye =>
        'Payé le ${e.datePaiement == null ? '' : _df.format(e.datePaiement!)}'
            '${e.methode.isNotEmpty ? ' · ${e.methode}' : ''}',
      EStatut.partiel =>
        'Partiel : ${_fmt.format(e.montantPaye.round())} / ${_fmt.format(e.montantDu.round())}',
      EStatut.retard =>
        'En retard — échéance ${e.dateEcheance == null ? '' : _df.format(e.dateEcheance!)}'
            '${r != null ? ' · +$r j' : ''}',
      EStatut.du =>
        'Loyer dû — échéance ${e.dateEcheance == null ? '' : _df.format(e.dateEcheance!)}',
      _ => 'À venir — ${e.dateEcheance == null ? '' : _df.format(e.dateEcheance!)}',
    };
    final bg = s == EStatut.retard
        ? const Color(0xFFFDF7F6)
        : s == EStatut.du
            ? const Color(0xFFFCF8F0)
            : null;

    return Container(
      margin: bg == null ? null : const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: const Border(top: BorderSide(color: Color(0xFFF1F1F1))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
      child: Row(
        children: [
          Container(
              width: 9,
              height: 9,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(e.periodeLabel,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(sub,
                style: TextStyle(
                    fontSize: 12,
                    color: s == EStatut.retard
                        ? const Color(0xFF8A4033)
                        : AppTheme.inkSoft)),
          ),
          Text(_fmt.format(e.montantDu.round()),
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: e.statutBrut == 'paye'
                  ? TextButton(
                      onPressed: () => BailQuittance.generer(
                          bail: bail, echeance: e, agence: agence),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.terracotta,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Quittance'),
                    )
                  : (s == EStatut.du || s == EStatut.retard || s == EStatut.partiel)
                      ? _miniPay(context, e)
                      : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniPay(BuildContext context, Echeance e) => InkWell(
        onTap: () => _openMarquerPaye(context, e),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: AppTheme.ink, borderRadius: BorderRadius.circular(8)),
          child: const Text('Marquer payé',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _actions(BuildContext context) {
    final prochaine = echeances
        .where((e) => e.statutBrut != 'paye' && e.statutBrut != 'annule')
        .toList()
      ..sort((a, b) => a.periode.compareTo(b.periode));
    return AppCard(
      title: 'Actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _actBtn(
            'Marquer un loyer payé',
            filled: true,
            onTap: prochaine.isEmpty
                ? null
                : () => _openMarquerPaye(context, prochaine.first),
          ),
          const SizedBox(height: 8),
          _actBtn('Relancer le locataire', onTap: () => _relance(context)),
          const SizedBox(height: 8),
          _actBtn('Résilier le bail',
              danger: true,
              onTap: bail.actif ? () => _resilier(context) : null),
        ],
      ),
    );
  }

  Widget _actBtn(String label,
      {bool filled = false, bool danger = false, VoidCallback? onTap}) {
    final c = danger ? const Color(0xFF8A4033) : (filled ? Colors.white : AppTheme.ink);
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: filled ? AppTheme.ink : Colors.white,
          foregroundColor: c,
          side: BorderSide(
              color: filled
                  ? AppTheme.ink
                  : danger
                      ? const Color(0xFFE7D3CF)
                      : AppTheme.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        child: Align(alignment: Alignment.centerLeft, child: Text(label)),
      ),
    );
  }

  Widget _reversement() => AppCard(
        title: 'Reversement propriétaire',
        child: Column(children: [
          _kv('Encaissé (bail)', '${_fmt.format(_encaisse.round())} FCFA'),
          _kv('Commission', '− ${_fmt.format(_commission.round())} FCFA'),
          _kv('Net à reverser',
              '${_fmt.format((_encaisse - _commission).round())} FCFA',
              last: true, strong: true),
        ]),
      );

  Widget _locataire() => AppCard(
        title: 'Locataire',
        child: Text(
          bail.locataireLie
              ? 'Compte Zappart lié — le locataire voit ses quittances et peut payer en ligne.'
              : 'Pas de compte Zappart. Envoyez-lui la quittance par WhatsApp / e-mail ; vous pourrez l\'inviter à créer un compte.',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
        ),
      );

  Widget _kv(String k, String v, {bool last = false, bool strong = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Color(0xFFF1F1F1))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppTheme.inkSoft))),
            Text(v,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );

  Future<void> _openMarquerPaye(BuildContext context, Echeance e) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _MarquerPayeDialog(bail: bail, echeance: e, repo: repo),
    );
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loyer enregistré. Quittance générée.')));
    }
  }

  Future<void> _relance(BuildContext context) async {
    final tel = bail.locataireTel.replaceAll(RegExp(r'[^0-9]'), '');
    final msg = Uri.encodeComponent(
        'Bonjour ${bail.locataireNom}, petit rappel concernant le loyer de votre logement '
        '« ${bail.bienTitre} ». Merci de régulariser dès que possible. — $agence');
    final uri = Uri.parse('https://wa.me/$tel?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _resilier(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Résilier ce bail ?', style: TextStyle(fontSize: 16)),
        content: const Text(
          'Le bail passe en « résilié ». L\'historique des loyers et des quittances '
          'est conservé. Les échéances futures ne sont plus suivies.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8A4033)),
            child: const Text('Résilier'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repo.resilier(bail.id);
      if (context.mounted) context.go('/baux');
    }
  }
}

// ── Dialogue « Marquer un loyer payé » ─────────────────────────────────────

class _MarquerPayeDialog extends StatefulWidget {
  const _MarquerPayeDialog({
    required this.bail,
    required this.echeance,
    required this.repo,
  });
  final Bail bail;
  final Echeance echeance;
  final BailRepository repo;

  @override
  State<_MarquerPayeDialog> createState() => _MarquerPayeDialogState();
}

class _MarquerPayeDialogState extends State<_MarquerPayeDialog> {
  static const _methodes = ['Espèces', 'Virement', 'Wave', 'Orange Money', 'Chèque'];
  String _methode = 'Espèces';
  late final _montant = TextEditingController(
      text: widget.echeance.montantDu.round().toString());
  DateTime _date = DateTime.now();
  bool _partiel = false;
  bool _busy = false;

  static final _fmt = NumberFormat('#,###', 'fr_FR');
  static final _df = DateFormat('d MMM yyyy', 'fr');

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final m = double.tryParse(_montant.text.trim().replaceAll(' ', '')) ?? 0;
    if (m <= 0) return;
    final agence = context.read<AuthService>().displayName;
    setState(() => _busy = true);
    try {
      await widget.repo.marquerPaye(
        echeanceId: widget.echeance.id,
        montant: m,
        partiel: _partiel && m < widget.echeance.montantDu,
        date: _date,
        methode: _methode,
      );
      if (mounted) {
        await BailQuittance.generer(
          bail: widget.bail,
          echeance: Echeance(
            id: widget.echeance.id,
            bailRefId: widget.echeance.bailRefId,
            houseRefId: widget.echeance.houseRefId,
            periode: widget.echeance.periode,
            dateEcheance: widget.echeance.dateEcheance,
            montantLoyer: widget.echeance.montantLoyer,
            montantCharges: widget.echeance.montantCharges,
            montantDu: widget.echeance.montantDu,
            statutBrut: 'paye',
            montantPaye: m,
            datePaiement: _date,
            methode: _methode,
          ),
          agence: agence,
        );
        if (mounted) Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Enregistrement impossible.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.echeance;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Marquer un loyer payé', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.bail.locataireNom} · ${widget.bail.bienTitre}',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
            const SizedBox(height: 14),
            _lbl('Échéance'),
            _box('${e.periodeLabel} — ${_fmt.format(e.montantDu.round())} FCFA'),
            const SizedBox(height: 12),
            _lbl('Moyen de paiement'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in _methodes)
                  GestureDetector(
                    onTap: () => setState(() => _methode = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _methode == m ? AppTheme.ink : Colors.white,
                        border: Border.all(
                            color: _methode == m ? AppTheme.ink : AppTheme.line),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(m,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _methode == m
                                  ? Colors.white
                                  : AppTheme.ink)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl('Date de paiement'),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now().add(const Duration(days: 3)),
                        );
                        if (d != null) setState(() => _date = d);
                      },
                      child: _box(_df.format(_date)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl('Montant reçu (FCFA)'),
                    TextField(
                      controller: _montant,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _partiel = !_partiel),
              child: Row(children: [
                Icon(
                    _partiel
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 18,
                    color: _partiel ? AppTheme.ink : AppTheme.inkSoft),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                      'Paiement partiel — le reste dû reste affiché',
                      style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                ),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Enregistrer & quittance'),
        ),
      ],
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Widget _box(String t) => Container(
        height: 40,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t, style: const TextStyle(fontSize: 13)),
      );
}
