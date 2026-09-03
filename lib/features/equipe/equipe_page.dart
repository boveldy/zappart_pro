import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/ui.dart';
import '../../data/membre_pro.dart';
import '../../data/permissions.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Gestion de l'équipe d'une agence : membres, rôles, permissions, invitations.
/// Réservée à `equipe.gerer` (le routeur garde déjà l'accès).
class EquipePage extends StatelessWidget {
  const EquipePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final ref = auth.agenceRef;
    if (ref == null || !auth.can(ProPerm.equipeGerer)) {
      return const PageScaffold(
        title: 'Équipe',
        child: EmptyState('Accès réservé à l\'administrateur de l\'agence.'),
      );
    }
    final abo = auth.abonnement;
    final repo = MembreRepository(
      ref,
      agenceNom: (auth.partenaireDoc?['nom'] as String?)?.trim().isNotEmpty == true
          ? auth.partenaireDoc!['nom'] as String
          : 'votre agence',
      parUid: auth.user?.uid ?? '',
      parNom: auth.displayName,
    );

    return StreamBuilder<List<MembrePro>>(
      stream: repo.membres(),
      builder: (context, mSnap) {
        return StreamBuilder<List<InvitationPro>>(
          stream: repo.invitationsOuvertes(),
          builder: (context, iSnap) {
            final membres = mSnap.data ?? const <MembrePro>[];
            final invites = iSnap.data ?? const <InvitationPro>[];
            final actifs = membres.where((m) => m.actif).length;
            final sieges = abo.plafondSieges;
            final occupe = actifs + invites.length;
            final resteDesSieges = occupe < sieges;
            final peutInviter = abo.multiUtilisateur && resteDesSieges;

            return PageScaffold(
              title: 'Équipe',
              subtitle: abo.multiUtilisateur
                  ? '$actifs membre${actifs > 1 ? 's' : ''} actif${actifs > 1 ? 's' : ''}'
                      ' · $occupe / $sieges sièges'
                  : 'Forfait ${abo.label} — mono-utilisateur',
              actions: [
                FilledButton.icon(
                  onPressed: peutInviter
                      ? () => _openInvite(context, repo)
                      : null,
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('Inviter'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.ink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: GoogleFonts.mavenPro(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!abo.multiUtilisateur)
                    _Notice(
                      'Votre forfait ${abo.label} ne permet qu\'un seul compte. '
                      'Passez à Agence + ou Réseau pour ajouter des collaborateurs.',
                    ),
                  if (abo.multiUtilisateur && !resteDesSieges)
                    _Notice(
                      'Tous les sièges de votre forfait sont occupés '
                      '($occupe / $sieges). Révoquez un membre ou passez au '
                      'forfait supérieur pour inviter quelqu\'un.',
                    ),
                  if (invites.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    AppCard(
                      title: 'Invitations en attente',
                      child: Column(
                        children: [
                          for (final i in invites)
                            _InviteRow(inv: i, repo: repo),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  AppCard(
                    title: 'Membres',
                    child: mSnap.connectionState == ConnectionState.waiting
                        ? const SkeletonBox(height: 120)
                        : Column(
                            children: [
                              for (final m in membres)
                                _MembreRow(
                                  membre: m,
                                  repo: repo,
                                  membres: membres,
                                  moiUid: auth.user?.uid ?? '',
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _openInvite(
      BuildContext context, MembreRepository repo) async {
    final emailCtrl = TextEditingController();
    var role = ProRole.agent;
    var busy = false;
    String? err;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 18, 20, MediaQuery.viewInsetsOf(c).bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Inviter un collaborateur', style: AppTheme.h2),
              const SizedBox(height: 4),
              Text(
                'Il recevra l\'accès à sa première connexion avec cette adresse '
                '(Google ou e-mail).',
                style: GoogleFonts.mavenPro(
                    fontSize: 12.5, color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Adresse e-mail',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Text('Rôle',
                  style: GoogleFonts.mavenPro(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r
                      in ProRole.values.where((r) => r != ProRole.admin))
                    ChoiceChip(
                      label: Text(r.label),
                      selected: role == r,
                      onSelected: (_) => setSheet(() => role = r),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_roleHint(role),
                  style: GoogleFonts.mavenPro(
                      fontSize: 11.5, color: AppTheme.inkSoft)),
              if (err != null) ...[
                const SizedBox(height: 10),
                Text(err!,
                    style: GoogleFonts.mavenPro(
                        fontSize: 12,
                        color: const Color(0xFF8A4033),
                        fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final email = emailCtrl.text.trim().toLowerCase();
                        if (!email.contains('@') || email.length < 5) {
                          setSheet(() => err = 'Adresse e-mail invalide.');
                          return;
                        }
                        setSheet(() {
                          busy = true;
                          err = null;
                        });
                        try {
                          await repo.inviter(email, role);
                          if (c.mounted) Navigator.pop(c);
                        } catch (_) {
                          setSheet(() {
                            busy = false;
                            err = 'Envoi impossible. Réessayez.';
                          });
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.ink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(busy ? 'Envoi…' : 'Envoyer l\'invitation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _roleHint(ProRole r) => switch (r) {
      ProRole.admin => '',
      ProRole.gerant =>
        'Toute la gestion locative et les annonces. Pas la facturation ni l\'équipe.',
      ProRole.comptable =>
        'Encaissements, dépenses, relevés et propriétaires. Ni annonces ni clôture de bail.',
      ProRole.agent =>
        'Saisie au quotidien : brouillons d\'annonces, consultation. Aucune action financière.',
    };

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2EDE1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: GoogleFonts.mavenPro(
                fontSize: 12.5,
                height: 1.35,
                color: const Color(0xFF7A5C1F),
                fontWeight: FontWeight.w600)),
      );
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.inv, required this.repo});
  final InvitationPro inv;
  final MembreRepository repo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inv.email,
                    style: GoogleFonts.mavenPro(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(children: [
                  StatusChip(inv.role.label),
                  const SizedBox(width: 6),
                  const StatusChip('En attente', tone: 'wait'),
                ]),
              ],
            ),
          ),
          TextButton(
            onPressed: () => repo.annulerInvitation(inv.id, email: inv.email),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8A4033)),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}

class _MembreRow extends StatelessWidget {
  const _MembreRow({
    required this.membre,
    required this.repo,
    required this.membres,
    required this.moiUid,
  });
  final MembrePro membre;
  final MembreRepository repo;
  final List<MembrePro> membres;
  final String moiUid;

  bool get _dernierAdmin =>
      membre.role == ProRole.admin &&
      membre.actif &&
      membres
              .where((m) => m.actif && m.role == ProRole.admin)
              .length ==
          1;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openDetail(context),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFF1F1F1))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    membre.nom.isEmpty ? membre.email : membre.nom,
                    style: GoogleFonts.mavenPro(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  if (membre.nom.isNotEmpty)
                    Text(membre.email,
                        style: GoogleFonts.mavenPro(
                            fontSize: 11.5, color: AppTheme.inkSoft)),
                  const SizedBox(height: 4),
                  Row(children: [
                    StatusChip(membre.role.label,
                        tone: membre.role == ProRole.admin ? 'ink' : 'muted'),
                    const SizedBox(width: 6),
                    if (!membre.actif)
                      const StatusChip('Révoqué', tone: 'danger')
                    else if (membre.uid == moiUid)
                      const StatusChip('Vous', tone: 'ok'),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.inkSoft),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => _MembreDetailSheet(
        membre: membre,
        repo: repo,
        dernierAdmin: _dernierAdmin,
      ),
    );
  }
}

class _MembreDetailSheet extends StatefulWidget {
  const _MembreDetailSheet({
    required this.membre,
    required this.repo,
    required this.dernierAdmin,
  });
  final MembrePro membre;
  final MembreRepository repo;
  final bool dernierAdmin;

  @override
  State<_MembreDetailSheet> createState() => _MembreDetailSheetState();
}

class _MembreDetailSheetState extends State<_MembreDetailSheet> {
  late ProRole _role = widget.membre.role;
  late Map<String, dynamic> _override =
      Map<String, dynamic>.from(widget.membre.override);
  bool _busy = false;

  Map<String, bool> get _effectif => resolvePermissions(_role, _override);

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Action impossible. Réessayez.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.membre;
    final surchargeables =
        ProPerm.all.where((k) => !ProPerm.nonDelegables.contains(k)).toList();
    final preset = presetFor(_role);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.nom.isEmpty ? m.email : m.nom, style: AppTheme.h2),
            if (m.nom.isNotEmpty)
              Text(m.email,
                  style: GoogleFonts.mavenPro(
                      fontSize: 12, color: AppTheme.inkSoft)),
            const SizedBox(height: 16),

            Text('Rôle',
                style: GoogleFonts.mavenPro(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in ProRole.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _role == r,
                    onSelected: (widget.dernierAdmin && r != ProRole.admin)
                        ? null
                        : (_) => setState(() {
                              _role = r;
                              _override = {}; // repart du préréglage
                            }),
                  ),
              ],
            ),
            if (widget.dernierAdmin)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'C\'est le dernier administrateur — son rôle ne peut pas être '
                  'changé. Promouvez d\'abord quelqu\'un d\'autre.',
                  style: GoogleFonts.mavenPro(
                      fontSize: 11, color: const Color(0xFF8A4033)),
                ),
              ),

            const SizedBox(height: 18),
            Text('Permissions',
                style: GoogleFonts.mavenPro(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              'Coché = autorisé. Les cases suivent le rôle ; ajuste au besoin.',
              style: GoogleFonts.mavenPro(
                  fontSize: 11, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 4),
            for (final k in surchargeables)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _effectif[k] ?? false,
                title: Text(ProPerm.labels[k] ?? k,
                    style: GoogleFonts.mavenPro(fontSize: 12.5)),
                subtitle: _override.containsKey(k)
                    ? Text('Modifié (préréglage : ${preset[k]! ? 'oui' : 'non'})',
                        style: GoogleFonts.mavenPro(
                            fontSize: 10.5, color: AppTheme.inkSoft))
                    : null,
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          if (v == preset[k]) {
                            _override.remove(k);
                          } else {
                            _override[k] = v;
                          }
                        }),
              ),

            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => widget.repo.enregistrer(m, _role, _override)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.ink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: Text(_busy ? 'Enregistrement…' : 'Enregistrer'),
            ),
            const SizedBox(height: 8),
            if (m.actif && !widget.dernierAdmin)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.repo.revoquer(m)),
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8A4033)),
                child: const Text('Révoquer l\'accès'),
              )
            else if (!m.actif)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.repo.reactiver(m)),
                child: const Text('Réactiver l\'accès'),
              ),
          ],
        ),
      ),
    );
  }
}
