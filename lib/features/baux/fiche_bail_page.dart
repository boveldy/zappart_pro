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
import 'bail_releve.dart';

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
            builder: (context, eSnap) => StreamBuilder<List<Depense>>(
              stream: repo.depensesDuBail(id),
              builder: (context, dSnap) => StreamBuilder<List<SignalementLoyer>>(
                stream: repo.signalementsDuBail(id),
                builder: (context, sSnap) => _Content(
                  bail: bail,
                  echeances: eSnap.data ?? const [],
                  echeancesErreur:
                      eSnap.hasError ? eSnap.error.toString() : null,
                  depenses: dSnap.data ?? const [],
                  signalements: sSnap.data ?? const [],
                  repo: repo,
                  agence: auth.displayName,
                ),
              ),
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
    this.echeancesErreur,
    required this.depenses,
    required this.signalements,
    required this.repo,
    required this.agence,
  });
  final Bail bail;
  final List<Echeance> echeances;
  final String? echeancesErreur;
  final List<Depense> depenses;
  final List<SignalementLoyer> signalements;
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

  double get _depProprio => depenses
      .where((d) => d.charge == DepenseCharge.proprietaire)
      .fold(0, (a, d) => a + d.montant);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final pending = signalements.where((s) => s.enAttente).toList();
      final left = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 16),
          if (pending.isNotEmpty) ...[
            _signalementsCard(context, pending),
            const SizedBox(height: 16),
          ],
          _conditions(),
          const SizedBox(height: 16),
          _echeancier(context),
          const SizedBox(height: 16),
          _depensesCard(context),
        ],
      );
      final right = Column(
        children: [
          if (bail.termine) ...[
            _clotureCard(),
            const SizedBox(height: 14),
          ],
          _actions(context),
          const SizedBox(height: 14),
          _encaissementCard(context),
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
              const Text('LOYER MENSUEL',
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
    final retard =
        echeances.where((e) => e.statutAffiche() == EStatut.retard).length;
    final du = echeances.where((e) => e.statutAffiche() == EStatut.du).length;
    return AppCard(
      title: 'Échéancier',
      trailing: Text('$paye payés · $du dû · $retard retard',
          style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (echeancesErreur != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF2F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Impossible de charger l\'échéancier.\n$echeancesErreur\n\n'
                'Si l\'erreur parle de « permission », les règles Firestore '
                'ne sont pas à jour : redéployez-les.',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A4033)),
              ),
            )
          else if (echeances.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Aucune échéance. Elles sont générées à la création du bail — '
                'si ce bail a été créé avant une mise à jour, recréez-le.',
                style: TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
              ),
            )
          else
            for (final e in echeances) _echRow(context, e),
        ],
      ),
    );
  }

  Widget _echRow(BuildContext context, Echeance e) {
    final s = e.statutAffiche();
    final dotColor = switch (s) {
      EStatut.paye => const Color(0xFF2F6B45),
      EStatut.partiel => const Color(0xFF7A5C1F),
      EStatut.du => const Color(0xFF7A5C1F),
      EStatut.retard => const Color(0xFF8A4033),
      EStatut.annule => const Color(0xFFD7D7D7),
      EStatut.aVenir => const Color(0xFFD7D7D7),
    };
    final r = e.joursDeRetard();
    final sub = switch (s) {
      EStatut.paye =>
        'Payé le ${e.datePaiement == null ? '' : _df.format(e.datePaiement!)}'
            '${e.methode.isNotEmpty ? ' · ${e.methode}' : ''}',
      EStatut.partiel =>
        'Partiel : ${_fmt.format(e.montantPaye.round())} / ${_fmt.format(e.montantDu.round())}',
      EStatut.annule => 'Annulée (clôture du bail)',
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
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: s == EStatut.annule
                        ? TextDecoration.lineThrough
                        : null)),
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
                  : (s == EStatut.du ||
                          s == EStatut.retard ||
                          s == EStatut.partiel)
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

  // ── Dépenses ──────────────────────────────────────────────────────────────
  Widget _depensesCard(BuildContext context) {
    final total = depenses.fold<double>(0, (a, d) => a + d.montant);
    return AppCard(
      title: 'Dépenses & réparations',
      trailing: depenses.isEmpty
          ? null
          : Text('${_fmt.format(total.round())} FCFA',
              style: const TextStyle(
                  fontSize: 11.5, color: AppTheme.inkSoft)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (depenses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                  'Aucune dépense enregistrée. Ajoutez les réparations et frais '
                  'pour qu\'ils apparaissent sur le relevé de gérance.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
            )
          else
            for (final d in depenses) _depRow(context, d),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _openDepense(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Ajouter une dépense'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.ink,
                side: const BorderSide(color: AppTheme.line),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle:
                    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _depRow(BuildContext context, Depense d) => Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 78,
              child: Text(d.date == null ? '—' : _df.format(d.date!),
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.inkSoft)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.libelle.isEmpty ? d.categorie : d.libelle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text('${d.categorie} · ${depenseChargeCourt(d.charge)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.inkSoft)),
                ],
              ),
            ),
            Text('${_fmt.format(d.montant.round())} FCFA',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            IconButton(
              onPressed: () => _supprDepense(context, d),
              icon: const Icon(Icons.close_rounded, size: 15),
              color: AppTheme.inkSoft,
              visualDensity: VisualDensity.compact,
              tooltip: 'Supprimer',
            ),
          ],
        ),
      );

  // ── Signalements de paiement (locataire) ─────────────────────────────────
  Widget _signalementsCard(BuildContext context, List<SignalementLoyer> pending) {
    return AppCard(
      title: 'Paiements déclarés par le locataire',
      trailing: StatusChip('${pending.length}', tone: 'wait'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in pending) _signalRow(context, s),
        ],
      ),
    );
  }

  Widget _signalRow(BuildContext context, SignalementLoyer s) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${s.periodeLabel} · ${_fmt.format(s.montant.round())} FCFA',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            Text(s.date == null ? '' : _df.format(s.date!),
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
          ]),
          const SizedBox(height: 2),
          Text(
              '${s.canal == 'en_ligne' ? 'Payé en ligne' : 'Déclaré payé'}'
              '${s.methode.isNotEmpty ? ' · ${s.methode}' : ''}',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
          const SizedBox(height: 8),
          Row(children: [
            InkWell(
              onTap: () => _validerSignal(context, s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: AppTheme.ink,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('Confirmer la réception',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => repo.rejeterSignalement(s.id),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8A4033),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                textStyle:
                    const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
              child: const Text('Rien reçu'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _validerSignal(BuildContext context, SignalementLoyer s) async {
    Echeance? cible;
    for (final e in echeances) {
      if (e.id == s.echeanceRefId || e.periode == s.periode) {
        cible = e;
        break;
      }
    }
    if (cible == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Échéance introuvable pour cette période.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Confirmer la réception du loyer',
            style: TextStyle(fontSize: 16)),
        content: Text(
          '${cible!.periodeLabel} — ${_fmt.format((s.montant > 0 ? s.montant : cible.montantDu).round())} FCFA'
          '${s.methode.isNotEmpty ? '\nMoyen déclaré : ${s.methode}' : ''}'
          '\n\nL\'échéance sera marquée « payée » et la quittance sera disponible.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok == true) {
      await repo.validerSignalement(
        signalementId: s.id,
        echeanceId: cible.id,
        montant: s.montant > 0 ? s.montant : cible.montantDu,
        date: s.date ?? DateTime.now(),
        methode: s.methode.isEmpty
            ? (s.canal == 'en_ligne' ? 'En ligne' : 'Mobile money')
            : s.methode,
      );
    }
  }

  Widget _encaissementCard(BuildContext context) {
    final m = bail.encaissementMode;
    return AppCard(
      title: 'Encaissement du loyer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(encaissementModeLabel(m),
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            m == EncaissementMode.direct
                ? 'Le locataire vous paie directement et déclare le paiement dans l\'app.'
                : 'Le locataire paie en ligne ; Zappart vous reverse.',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
          ),
          if (bail.actif) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => repo.setEncaissementMode(
                bail.id,
                m == EncaissementMode.direct
                    ? EncaissementMode.zappart
                    : EncaissementMode.direct,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.ink,
                side: const BorderSide(color: AppTheme.line),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              child: Text(m == EncaissementMode.direct
                  ? 'Passer au paiement en ligne'
                  : 'Repasser en encaissement direct'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────
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
            onTap: (bail.actif && prochaine.isNotEmpty)
                ? () => _openMarquerPaye(context, prochaine.first)
                : null,
          ),
          const SizedBox(height: 8),
          _actBtn('Relevé de gérance', onTap: () => _openReleve(context)),
          const SizedBox(height: 8),
          _actBtn('Relancer le locataire', onTap: () => _relance(context)),
          const SizedBox(height: 8),
          _actBtn('Clôturer le bail',
              danger: true,
              onTap: bail.actif ? () => _openCloture(context) : null),
        ],
      ),
    );
  }

  Widget _actBtn(String label,
      {bool filled = false, bool danger = false, VoidCallback? onTap}) {
    final c =
        danger ? const Color(0xFF8A4033) : (filled ? Colors.white : AppTheme.ink);
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

  Widget _clotureCard() => AppCard(
        title: 'Bail clôturé',
        child: Column(
          children: [
            _kv('Fin de bail',
                bail.finDate == null ? '—' : _df.format(bail.finDate!)),
            _kv('Motif', bail.finMotifLabel),
            _kv('Caution', bail.cautionStatutLabel),
            if (bail.cautionRestitue > 0)
              _kv('Restitué',
                  '${_fmt.format(bail.cautionRestitue.round())} FCFA'),
            if (bail.cautionRetenue > 0)
              _kv('Retenu', '${_fmt.format(bail.cautionRetenue.round())} FCFA',
                  last: true),
          ],
        ),
      );

  Widget _reversement() => AppCard(
        title: 'Reversement propriétaire',
        child: Column(children: [
          _kv('Encaissé (bail)', '${_fmt.format(_encaisse.round())} FCFA'),
          _kv('Commission', '− ${_fmt.format(_commission.round())} FCFA'),
          if (_depProprio > 0)
            _kv('Dépenses propriétaire',
                '− ${_fmt.format(_depProprio.round())} FCFA'),
          _kv(
              'Net à reverser',
              '${_fmt.format((_encaisse - _commission - _depProprio).round())} FCFA',
              last: true,
              strong: true),
        ]),
      );

  Widget _locataire() => AppCard(
        title: 'Locataire',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(bail.locataireNom,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text(bail.locataireTel,
                style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
            const SizedBox(height: 8),
            Text(
              bail.locataireTelCanonique.isEmpty
                  ? 'Numéro non renseigné — le locataire ne pourra pas suivre son bail dans l\'app.'
                  : 'Le locataire retrouve ce bail dans l\'app Zappart s\'il utilise le numéro '
                      '${bail.locataireTel} (vérifié par SMS). Il y voit son échéancier et '
                      'peut déclarer ses paiements${bail.encaissementMode == EncaissementMode.zappart ? ' ou payer en ligne' : ''}.',
              style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
            ),
          ],
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

  // ── ouvertures de dialogues ──────────────────────────────────────────────
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

  Future<void> _openDepense(BuildContext context) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _DepenseDialog(bail: bail, repo: repo),
    );
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dépense ajoutée.')));
    }
  }

  Future<void> _supprDepense(BuildContext context, Depense d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Supprimer cette dépense ?',
            style: TextStyle(fontSize: 16)),
        content: Text('${d.libelle.isEmpty ? d.categorie : d.libelle} — '
            '${_fmt.format(d.montant.round())} FCFA'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8A4033)),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) await repo.supprimerDepense(d.id);
  }

  Future<void> _openReleve(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RelevePeriodeDialog(
        bail: bail,
        echeances: echeances,
        depenses: depenses,
        agence: agence,
      ),
    );
  }

  Future<void> _openCloture(BuildContext context) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ClotureDialog(
        bail: bail,
        echeances: echeances,
        repo: repo,
        agence: agence,
      ),
    );
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bail clôturé.')));
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                  child: Text('Paiement partiel — le reste dû reste affiché',
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

// ── Dialogue « Ajouter une dépense » ───────────────────────────────────────

class _DepenseDialog extends StatefulWidget {
  const _DepenseDialog({required this.bail, required this.repo});
  final Bail bail;
  final BailRepository repo;

  @override
  State<_DepenseDialog> createState() => _DepenseDialogState();
}

class _DepenseDialogState extends State<_DepenseDialog> {
  final _montant = TextEditingController();
  final _libelle = TextEditingController();
  String _categorie = kDepenseCategories.first;
  DepenseCharge _charge = DepenseCharge.proprietaire;
  DateTime _date = DateTime.now();
  bool _busy = false;

  static final _df = DateFormat('d MMM yyyy', 'fr');

  @override
  void dispose() {
    _montant.dispose();
    _libelle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final m = double.tryParse(_montant.text.trim().replaceAll(' ', '')) ?? 0;
    if (m <= 0) return;
    setState(() => _busy = true);
    try {
      await widget.repo.ajouterDepense(
        bailId: widget.bail.id,
        montant: m,
        categorie: _categorie,
        libelle: _libelle.text,
        charge: _charge,
        date: _date,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ajout impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Ajouter une dépense', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _lbl('Libellé'),
            TextField(
              controller: _libelle,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                  isDense: true, hintText: 'Ex. Remplacement chauffe-eau'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl('Catégorie'),
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.line),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _categorie,
                          isExpanded: true,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.ink),
                          items: [
                            for (final c in kDepenseCategories)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) =>
                              setState(() => _categorie = v ?? _categorie),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _lbl('Montant (FCFA)'),
                    TextField(
                      controller: _montant,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            _lbl('Date'),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 3)),
                );
                if (d != null) setState(() => _date = d);
              },
              child: Container(
                height: 40,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_df.format(_date),
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(height: 12),
            _lbl('Imputation'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in DepenseCharge.values)
                  GestureDetector(
                    onTap: () => setState(() => _charge = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _charge == c ? AppTheme.ink : Colors.white,
                        border: Border.all(
                            color: _charge == c ? AppTheme.ink : AppTheme.line),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(depenseChargeCourt(c),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _charge == c
                                  ? Colors.white
                                  : AppTheme.ink)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _charge == DepenseCharge.proprietaire
                  ? 'Déduite du net à reverser au propriétaire.'
                  : _charge == DepenseCharge.locataire
                      ? 'Signalée sur le relevé, à refacturer au locataire.'
                      : 'Supportée par l\'agence — n\'affecte pas le reversement.',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
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
              : const Text('Ajouter'),
        ),
      ],
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

// ── Dialogue « Relevé de gérance » ─────────────────────────────────────────

enum _Periode { moisEnCours, moisDernier, trimestre, annee, tout }

class _RelevePeriodeDialog extends StatefulWidget {
  const _RelevePeriodeDialog({
    required this.bail,
    required this.echeances,
    required this.depenses,
    required this.agence,
  });
  final Bail bail;
  final List<Echeance> echeances;
  final List<Depense> depenses;
  final String agence;

  @override
  State<_RelevePeriodeDialog> createState() => _RelevePeriodeDialogState();
}

class _RelevePeriodeDialogState extends State<_RelevePeriodeDialog> {
  _Periode _p = _Periode.moisEnCours;
  bool _excel = false;
  bool _busy = false;

  ({DateTime debut, DateTime fin, String label}) _bornes() {
    final now = DateTime.now();
    switch (_p) {
      case _Periode.moisEnCours:
        return (
          debut: DateTime(now.year, now.month, 1),
          fin: DateTime(now.year, now.month + 1, 0),
          label: DateFormat('MMMM yyyy', 'fr').format(now),
        );
      case _Periode.moisDernier:
        final m = DateTime(now.year, now.month - 1, 1);
        return (
          debut: m,
          fin: DateTime(m.year, m.month + 1, 0),
          label: DateFormat('MMMM yyyy', 'fr').format(m),
        );
      case _Periode.trimestre:
        final d = DateTime(now.year, now.month - 2, 1);
        return (
          debut: d,
          fin: DateTime(now.year, now.month + 1, 0),
          label: '3 derniers mois',
        );
      case _Periode.annee:
        return (
          debut: DateTime(now.year, 1, 1),
          fin: DateTime(now.year, 12, 31),
          label: 'Année ${now.year}',
        );
      case _Periode.tout:
        return (
          debut: DateTime(2020),
          fin: DateTime(now.year + 1),
          label: 'Depuis le début',
        );
    }
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final b = _bornes();
    try {
      await BailReleve.generer(
        bail: widget.bail,
        echeances: widget.echeances,
        depenses: widget.depenses,
        agence: widget.agence,
        debut: b.debut,
        fin: b.fin,
        periodeLabel: b.label,
        excel: _excel,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Génération impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = {
      _Periode.moisEnCours: 'Mois en cours',
      _Periode.moisDernier: 'Mois dernier',
      _Periode.trimestre: '3 derniers mois',
      _Periode.annee: 'Année civile',
      _Periode.tout: 'Depuis le début',
    };
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Relevé de gérance', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.bail.bienTitre} · ${widget.bail.locataireNom}',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
            const SizedBox(height: 14),
            _lbl('Période'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in labels.entries)
                  GestureDetector(
                    onTap: () => setState(() => _p = e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _p == e.key ? AppTheme.ink : Colors.white,
                        border: Border.all(
                            color:
                                _p == e.key ? AppTheme.ink : AppTheme.line),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(e.value,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _p == e.key
                                  ? Colors.white
                                  : AppTheme.ink)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _lbl('Format'),
            Row(children: [
              _fmtPill('PDF', !_excel, () => setState(() => _excel = false)),
              const SizedBox(width: 8),
              _fmtPill('Excel', _excel, () => setState(() => _excel = true)),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _busy ? null : _go,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Télécharger'),
        ),
      ],
    );
  }

  Widget _fmtPill(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: on ? AppTheme.ink : Colors.white,
            border: Border.all(color: on ? AppTheme.ink : AppTheme.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : AppTheme.ink)),
        ),
      );

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

// ── Dialogue « Clôturer le bail » ──────────────────────────────────────────

class _ClotureDialog extends StatefulWidget {
  const _ClotureDialog({
    required this.bail,
    required this.echeances,
    required this.repo,
    required this.agence,
  });
  final Bail bail;
  final List<Echeance> echeances;
  final BailRepository repo;
  final String agence;

  @override
  State<_ClotureDialog> createState() => _ClotureDialogState();
}

class _ClotureDialogState extends State<_ClotureDialog> {
  static const _motifs = [
    'Fin de bail',
    'Résiliation',
    'Départ anticipé',
    'Autre',
  ];
  String _motif = 'Fin de bail';
  DateTime _fin = DateTime.now();
  late final _restitue =
      TextEditingController(text: widget.bail.caution.round().toString());
  final _retenue = TextEditingController(text: '0');
  final _note = TextEditingController();
  bool _annulerFutures = true;
  bool _recu = true;
  bool _busy = false;

  static final _fmt = NumberFormat('#,###', 'fr_FR');
  static final _df = DateFormat('d MMM yyyy', 'fr');

  @override
  void dispose() {
    _restitue.dispose();
    _retenue.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _restV =>
      double.tryParse(_restitue.text.trim().replaceAll(' ', '')) ?? 0;
  double get _retV =>
      double.tryParse(_retenue.text.trim().replaceAll(' ', '')) ?? 0;

  List<String> get _aAnnuler {
    if (!_annulerFutures) return const [];
    final f = DateTime(_fin.year, _fin.month, _fin.day, 23, 59, 59);
    return widget.echeances
        .where((e) =>
            e.statutBrut == 'ouvert' &&
            e.dateEcheance != null &&
            e.dateEcheance!.isAfter(f))
        .map((e) => e.id)
        .toList();
  }

  bool get _valide => _restV + _retV <= widget.bail.caution + 0.5;

  Future<void> _save() async {
    if (!_valide) return;
    setState(() => _busy = true);
    try {
      await widget.repo.cloturerBail(
        bailId: widget.bail.id,
        finDate: _fin,
        motif: _motif,
        cautionRestitue: _restV,
        cautionRetenue: _retV,
        cautionNote: _note.text,
        echeancesAAnnuler: _aAnnuler,
      );
      if (_recu && mounted) {
        await BailReleve.recuCaution(
          bail: widget.bail,
          agence: widget.agence,
          finDate: _fin,
          cautionTotale: widget.bail.caution,
          restitue: _restV,
          retenue: _retV,
          note: _note.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clôture impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nbFutures = _aAnnuler.length;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Clôturer le bail', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.bail.locataireNom} · ${widget.bail.bienTitre}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.inkSoft)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _lbl('Motif'),
                      Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.line),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _motif,
                            isExpanded: true,
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.ink),
                            items: [
                              for (final m in _motifs)
                                DropdownMenuItem(value: m, child: Text(m)),
                            ],
                            onChanged: (v) =>
                                setState(() => _motif = v ?? _motif),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _lbl('Date de fin'),
                      InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _fin,
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null) setState(() => _fin = d);
                        },
                        child: Container(
                          height: 42,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.line),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(_df.format(_fin),
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.panel,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Dépôt de garantie : ${_fmt.format(widget.bail.caution.round())} FCFA',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _lbl('Restitué au locataire'),
                            TextField(
                              controller: _restitue,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(isDense: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _lbl('Retenues'),
                            TextField(
                              controller: _retenue,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(isDense: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ]),
                    if (!_valide) ...[
                      const SizedBox(height: 6),
                      const Text(
                          'Restitué + retenues dépasse le dépôt de garantie.',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF8A4033))),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _lbl('Détail des retenues (optionnel)'),
              TextField(
                controller: _note,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Ex. peinture chambre, facture eau impayée…'),
              ),
              const SizedBox(height: 10),
              _check(
                _annulerFutures,
                nbFutures > 0
                    ? 'Annuler les $nbFutures échéance${nbFutures > 1 ? 's' : ''} postérieure${nbFutures > 1 ? 's' : ''} à la date de fin'
                    : 'Annuler les échéances postérieures à la date de fin',
                () => setState(() => _annulerFutures = !_annulerFutures),
              ),
              _check(
                _recu,
                'Générer le reçu de solde de caution (PDF)',
                () => setState(() => _recu = !_recu),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _busy || !_valide ? null : _save,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A4033)),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Clôturer le bail'),
        ),
      ],
    );
  }

  Widget _check(bool on, String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: GestureDetector(
          onTap: onTap,
          child: Row(children: [
            Icon(
                on
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 18,
                color: on ? AppTheme.ink : AppTheme.inkSoft),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.inkSoft)),
            ),
          ]),
        ),
      );

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}
