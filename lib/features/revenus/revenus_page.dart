import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/download.dart';
import '../../core/ui.dart';
import '../../data/revenus_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Revenus : solde disponible, demande de retrait, relevé filtrable par période,
/// export CSV. Données : `wallet_ledger` (encaissements en ligne) +
/// `retraits_partenaires`, part partenaire dénormalisée sur
/// `Partenaires.solde_disponible`.
class RevenusPage extends StatefulWidget {
  const RevenusPage({super.key});

  @override
  State<RevenusPage> createState() => _RevenusPageState();
}

enum _Periode { j7, j30, j90, tout }

extension on _Periode {
  String get label => switch (this) {
        _Periode.j7 => '7 jours',
        _Periode.j30 => '30 jours',
        _Periode.j90 => '90 jours',
        _Periode.tout => 'Tout',
      };
  DateTime? get depuis => switch (this) {
        _Periode.j7 => DateTime.now().subtract(const Duration(days: 7)),
        _Periode.j30 => DateTime.now().subtract(const Duration(days: 30)),
        _Periode.j90 => DateTime.now().subtract(const Duration(days: 90)),
        _Periode.tout => null,
      };
}

class _RevenusPageState extends State<RevenusPage> {
  _Periode _periode = _Periode.j30;

  static final _fmt = NumberFormat('#,###', 'fr_FR');
  static String _fcfa(num v) => '${_fmt.format(v.round())} FCFA';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.partenaireRef;
    if (ref == null) {
      return const PageScaffold(
        title: 'Revenus',
        child: EmptyState('Fiche partenaire en cours de liaison…'),
      );
    }
    final repo = RevenusRepository(ref);

    return StreamBuilder<int>(
      stream: repo.soldeDisponible(),
      builder: (context, soldeSnap) {
        return StreamBuilder<List<LedgerEntry>>(
          stream: repo.ledger(),
          builder: (context, ledgerSnap) {
            return StreamBuilder<List<RetraitEntry>>(
              stream: repo.retraits(),
              builder: (context, retraitSnap) {
                final ledger = ledgerSnap.data;
                final retraits = retraitSnap.data;
                final loading = ledger == null || retraits == null;
                final err = ledgerSnap.hasError || retraitSnap.hasError;

                final disponible = soldeSnap.data ?? 0;
                final depuis = _periode.depuis;
                bool inPeriod(DateTime? d) =>
                    depuis == null || (d != null && d.isAfter(depuis));

                final enAttente = (ledger ?? const [])
                    .where((l) => l.enAttente)
                    .fold<double>(0, (a, l) => a + l.montant);
                final revenuPeriode = (ledger ?? const [])
                    .where((l) => l.actif && inPeriod(l.date))
                    .fold<double>(0, (a, l) => a + l.montant);
                final retirePeriode = (retraits ?? const [])
                    .where((r) => r.status == 'paye' && inPeriod(r.date))
                    .fold<int>(0, (a, r) => a + r.montant);

                return PageScaffold(
                  title: 'Revenus',
                  subtitle: 'Encaissements en ligne et retraits',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: loading || err
                          ? null
                          : () => _exportCsv(ledger, retraits),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Exporter CSV'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.ink,
                        side: const BorderSide(color: AppTheme.line),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SoldeCard(
                        nom: auth.displayName,
                        idMasque: _mask(ref.id),
                        disponible: disponible,
                        enAttente: enAttente,
                        revenuPeriode: revenuPeriode,
                        periodeLabel: _periode.label,
                        onRetirer: disponible <= 0
                            ? null
                            : () => _retrait(repo, disponible),
                      ),
                      const SizedBox(height: 18),
                      _PeriodeBar(
                        value: _periode,
                        onChanged: (p) => setState(() => _periode = p),
                      ),
                      const SizedBox(height: 14),
                      if (err)
                        const AppCard(
                            child: EmptyState('Impossible de charger vos revenus.'))
                      else if (loading)
                        const AppCard(child: SkeletonBox(height: 220))
                      else ...[
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _Kpi('Encaissé · ${_periode.label}',
                                _fcfa(revenuPeriode)),
                            _Kpi('En attente', _fcfa(enAttente)),
                            _Kpi('Retiré · ${_periode.label}',
                                _fcfa(retirePeriode)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _Mouvements(
                          ledger: ledger
                              .where((l) => l.actif && inPeriod(l.date))
                              .toList(),
                          retraits: retraits
                              .where((r) => inPeriod(r.date))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static String _mask(String id) {
    final l = id.length >= 4 ? id.substring(id.length - 4) : id;
    return '•••• ${l.toUpperCase()}';
  }

  void _exportCsv(List<LedgerEntry> ledger, List<RetraitEntry> retraits) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final rows = <String>['Date;Sens;Libellé;Montant FCFA;Statut;Méthode;Référence'];
    for (final l in ledger.where((l) => l.actif)) {
      rows.add([
        l.date == null ? '' : df.format(l.date!),
        'Crédit',
        l.typeLabel,
        l.montant.round(),
        l.enAttente ? 'En attente' : 'Disponible',
        l.methode,
        l.reference,
      ].join(';'));
    }
    for (final r in retraits) {
      rows.add([
        r.date == null ? '' : df.format(r.date!),
        'Retrait',
        'Retrait ${r.methodeLabel} ${r.numeroMasque}',
        -r.montant,
        r.badge.label,
        r.methodeLabel,
        r.preuve,
      ].join(';'));
    }
    final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
    downloadText('zappart-revenus-$stamp.csv', rows.join('\r\n'));
  }

  Future<void> _retrait(RevenusRepository repo, int disponible) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RetraitDialog(repo: repo, disponible: disponible),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Demande de retrait envoyée. Elle apparaît dans votre historique.'),
      ));
    }
  }
}

// ── Carte solde ────────────────────────────────────────────────────────────

class _SoldeCard extends StatelessWidget {
  const _SoldeCard({
    required this.nom,
    required this.idMasque,
    required this.disponible,
    required this.enAttente,
    required this.revenuPeriode,
    required this.periodeLabel,
    required this.onRetirer,
  });

  final String nom, idMasque, periodeLabel;
  final int disponible;
  final double enAttente, revenuPeriode;
  final VoidCallback? onRetirer;

  static final _f = NumberFormat('#,###', 'fr_FR');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(nom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              Text(idMasque,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 20),
          Text('Solde disponible',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
          const SizedBox(height: 3),
          Text('${_f.format(disponible)} FCFA',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _sub('En attente', '${_f.format(enAttente.round())} FCFA')),
              Expanded(
                  child: _sub('Revenu généré · $periodeLabel',
                      '${_f.format(revenuPeriode.round())} FCFA')),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onRetirer,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.ink,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.25),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Retirer mon solde',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sub(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      );
}

// ── Période ────────────────────────────────────────────────────────────────

class _PeriodeBar extends StatelessWidget {
  const _PeriodeBar({required this.value, required this.onChanged});
  final _Periode value;
  final ValueChanged<_Periode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.line),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in _Periode.values)
            GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: value == p ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color:
                          value == p ? AppTheme.line : Colors.transparent),
                ),
                child: Text(p.label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            value == p ? FontWeight.w700 : FontWeight.w500,
                        color: value == p ? AppTheme.ink : AppTheme.inkSoft)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ── Liste des mouvements ───────────────────────────────────────────────────

class _Mvt {
  _Mvt(this.date, this.child);
  final DateTime? date;
  final Widget child;
}

class _Mouvements extends StatelessWidget {
  const _Mouvements({required this.ledger, required this.retraits});
  final List<LedgerEntry> ledger;
  final List<RetraitEntry> retraits;

  static final _fmt = NumberFormat('#,###', 'fr_FR');
  static final _df = DateFormat('d MMM · HH:mm', 'fr');

  @override
  Widget build(BuildContext context) {
    final items = <_Mvt>[
      for (final l in ledger) _Mvt(l.date, _LedgerRow(l)),
      for (final r in retraits) _Mvt(r.date, _RetraitRow(r)),
    ]..sort((a, b) => (b.date ?? DateTime(2000))
        .compareTo(a.date ?? DateTime(2000)));

    return AppCard(
      title: 'Mouvements',
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
      child: items.isEmpty
          ? const EmptyState('Aucun mouvement sur cette période.')
          : Column(
              children: [
                for (final it in items)
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                          top: BorderSide(color: Color(0xFFF0F0F0))),
                    ),
                    child: it.child,
                  ),
              ],
            ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow(this.l);
  final LedgerEntry l;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
                color: AppTheme.panel, shape: BoxShape.circle),
            child: const Icon(Icons.south_west_rounded,
                size: 16, color: AppTheme.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.typeLabel,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  l.date == null ? '' : _Mouvements._df.format(l.date!),
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('+ ${_Mouvements._fmt.format(l.montant.round())}',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              StatusChip(l.enAttente ? 'En attente' : 'Disponible',
                  tone: l.enAttente ? 'wait' : 'ok'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RetraitRow extends StatelessWidget {
  const _RetraitRow(this.r);
  final RetraitEntry r;

  @override
  Widget build(BuildContext context) {
    final b = r.badge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
                color: AppTheme.ink, shape: BoxShape.circle),
            child: const Icon(Icons.north_east_rounded,
                size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Retrait → ${r.methodeLabel} ${r.numeroMasque}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (r.date != null) _Mouvements._df.format(r.date!),
                    if (r.status == 'paye' && r.preuve.isNotEmpty)
                      'réf. ${r.preuve}',
                    if (r.status == 'rejete')
                      r.motif.isNotEmpty
                          ? '${r.motif} — solde recrédité'
                          : 'solde recrédité',
                  ].join('  ·  '),
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('− ${_Mouvements._fmt.format(r.montant)}',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: r.status == 'rejete'
                          ? AppTheme.inkSoft
                          : AppTheme.ink)),
              const SizedBox(height: 4),
              StatusChip(b.label, tone: b.tone),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Dialogue de retrait ────────────────────────────────────────────────────

class _RetraitDialog extends StatefulWidget {
  const _RetraitDialog({required this.repo, required this.disponible});
  final RevenusRepository repo;
  final int disponible;

  @override
  State<_RetraitDialog> createState() => _RetraitDialogState();
}

class _RetraitDialogState extends State<_RetraitDialog> {
  String _methode = 'wave';
  final _numero = TextEditingController();
  late final _montant =
      TextEditingController(text: widget.disponible.toString());
  bool _envoi = false;
  String? _err;

  @override
  void dispose() {
    _numero.dispose();
    _montant.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final montant = int.tryParse(_montant.text.trim());
    final numero = _numero.text.trim();
    if (montant == null || montant <= 0) {
      setState(() => _err = 'Montant invalide.');
      return;
    }
    if (montant > widget.disponible) {
      setState(() => _err = 'Montant supérieur au solde disponible.');
      return;
    }
    if (numero.length < 6) {
      setState(() => _err = 'Numéro requis.');
      return;
    }
    setState(() {
      _envoi = true;
      _err = null;
    });
    final r = await widget.repo.demanderRetrait(
        montant: montant, methode: _methode, numero: numero);
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _envoi = false;
        _err = r.message.isNotEmpty ? r.message : 'Échec. Réessayez.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat('#,###', 'fr_FR');
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Retirer mon solde', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solde disponible : ${f.format(widget.disponible)} FCFA',
                style:
                    const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final m in const [
                  ('wave', 'Wave'),
                  ('orange_money', 'Orange Money')
                ]) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _methode = m.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _methode == m.$1
                              ? AppTheme.ink
                              : AppTheme.panel,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(m.$2,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _methode == m.$1
                                    ? Colors.white
                                    : AppTheme.ink)),
                      ),
                    ),
                  ),
                  if (m.$1 == 'wave') const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numero,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                  labelText: 'Numéro', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _montant,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                  labelText: 'Montant (FCFA)', isDense: true),
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!,
                  style:
                      const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _envoi ? null : () => Navigator.pop(context, false),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _envoi ? null : _envoyer,
          child: _envoi
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Confirmer'),
        ),
      ],
    );
  }
}
