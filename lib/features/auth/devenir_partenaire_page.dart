import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand.dart';

/// Inscription self-service à Zappart Pro.
///
/// Trois états, pilotés par [AuthService.access] :
///  - `loggedOut`  → « Continuer avec Google / Apple » (mêmes fournisseurs que
///    l'app mobile → même compte).
///  - `notPartner` → formulaire de demande partenaire (écrit une fiche
///    `Partenaires` `en_attente`).
///  - `pending`    → « Demande en cours de validation ».
class DevenirPartenairePage extends StatefulWidget {
  const DevenirPartenairePage({super.key});

  @override
  State<DevenirPartenairePage> createState() => _DevenirPartenairePageState();
}

class _DevenirPartenairePageState extends State<DevenirPartenairePage> {
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _nomAgence = TextEditingController();
  final _tel = TextEditingController();
  final _ville = TextEditingController();
  final _desc = TextEditingController();

  bool _service = false; // false = loue des logements, true = prestataire
  String _sousType = ''; // 'Agence'|'Gérant'|... ou code métier service
  int _nombreBiens = 1;
  int _nombreAgent = 1;

  bool _busy = false;
  bool _sent = false;
  String? _error;

  static const _typesHote = <String, String>{
    'Agence': 'Agence',
    'Gérant': 'Gérant',
    'Propriétaire': 'Propriétaire',
    'Courtier': 'Courtier',
    'Hôtel': 'Hotel',
  };
  // libellé → code métier (identiques au hub admin `kServicePartners`)
  static const _typesService = <String, String>{
    'Déménagement': 'Demenageur',
    'Nettoyage': 'Nettoyeur',
    'Plomberie': 'Plombier',
    'Électricité': 'Electricien',
    'Peinture': 'Peintre',
    'Autre': 'Installeur',
  };

  bool get _needsRaisonSociale => _sousType == 'Agence' || _sousType == 'Hotel';

  @override
  void dispose() {
    for (final c in [_nom, _prenom, _nomAgence, _tel, _ville, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  String _authMessage(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return '';
        case 'popup-blocked':
          return 'La fenêtre de connexion a été bloquée par le navigateur.';
        case 'account-exists-with-different-credential':
          return 'Ce compte existe déjà avec un autre mode de connexion.';
        case 'operation-not-allowed':
          return 'Ce mode de connexion n\'est pas encore activé.';
        case 'unauthorized-domain':
          return 'Domaine non autorisé dans Firebase Auth.';
        default:
          return 'Connexion impossible (${e.code}).';
      }
    }
    return 'Connexion impossible. Vérifiez votre connexion.';
  }

  Future<void> _oauth(Future<void> Function() run) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await run();
    } catch (e) {
      final m = _authMessage(e);
      if (mounted && m.isNotEmpty) setState(() => _error = m);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_sousType.isEmpty) {
      setState(() => _error = 'Choisissez votre activité.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AuthService>().submitPartenaireRequest(
          service: _service,
          typePartenaire: _service ? 'Prestataire' : _sousType,
          typeService: _service ? _sousType : null,
          nom: _nom.text,
          prenom: _prenom.text,
          nomAgence: _nomAgence.text,
          telephone: _tel.text,
          ville: _ville.text,
          nombreBiens: _nombreBiens,
          nombreAgent: _nombreAgent,
          descriptionCourte: _desc.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      _sent = err == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final wide = MediaQuery.sizeOf(context).width >= 900;

    Widget body;
    if (_sent || auth.access == ProAccess.pending) {
      body = _PendingView(email: auth.email, onSignOut: auth.signOut);
    } else if (auth.access == ProAccess.loggedOut) {
      body = _SignInView(
        busy: _busy,
        error: _error,
        onGoogle: () => _oauth(auth.signInWithGoogle),
        onApple: () => _oauth(auth.signInWithApple),
        onLogin: () => context.go('/login'),
      );
    } else {
      body = _buildForm(auth);
    }

    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: body,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(flex: 5, child: _HeroPanel()),
                Expanded(flex: 6, child: Center(child: card)),
              ],
            )
          : Center(child: card),
    );
  }

  Widget _buildForm(AuthService auth) {
    final options = _service ? _typesService : _typesHote;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(subtitle: 'Créez votre espace de gestion.'),
          const SizedBox(height: 26),
          Text('Votre activité',
              style: GoogleFonts.mavenPro(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _Segmented(
            left: 'Je loue des logements',
            right: 'Je propose un service',
            value: _service,
            onChanged: (v) => setState(() {
              _service = v;
              _sousType = '';
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _sousType.isEmpty ? null : _sousType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type'),
            hint: Text(_service ? 'Métier' : 'Vous êtes…'),
            items: [
              for (final e in options.entries)
                DropdownMenuItem(value: e.value, child: Text(e.key)),
            ],
            onChanged: (v) => setState(() => _sousType = v ?? ''),
          ),
          const SizedBox(height: 14),
          if (_needsRaisonSociale) ...[
            TextFormField(
              controller: _nomAgence,
              decoration:
                  const InputDecoration(labelText: 'Raison sociale / nom de l\'agence'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 14),
          ],
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _prenom,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _nom,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          TextFormField(
            controller: _tel,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Téléphone', hintText: '77 000 00 00'),
            validator: (v) {
              final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
              return d.length < 9 ? 'Numéro invalide' : null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _ville,
            decoration: const InputDecoration(
                labelText: 'Ville / zone', hintText: 'Dakar — Almadies'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requis' : null,
          ),
          const SizedBox(height: 14),
          if (!_service)
            _Stepper(
              label: 'Nombre de biens gérés',
              value: _nombreBiens,
              min: 1,
              onChanged: (v) => setState(() => _nombreBiens = v),
            )
          else ...[
            _Stepper(
              label: 'Nombre d\'intervenants',
              value: _nombreAgent,
              min: 1,
              onChanged: (v) => setState(() => _nombreAgent = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Décrivez votre activité en une phrase'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
          ],
          if (_error != null && _error!.isNotEmpty) ...[
            const SizedBox(height: 14),
            _ErrorRow(_error!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Envoyer ma demande'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Compte : ${auth.email} · Votre demande est vérifiée par '
            'l\'équipe Zappart avant l\'ouverture de l\'accès. Les pièces '
            'justificatives (CNI, RCCM) vous seront demandées ensuite.',
            style: GoogleFonts.mavenPro(fontSize: 11.5, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: auth.signOut,
              child: Text('Se déconnecter',
                  style: GoogleFonts.mavenPro(
                      fontSize: 12, color: AppTheme.inkSoft)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sous-vues ──────────────────────────────────────────────────────────────

class _SignInView extends StatelessWidget {
  const _SignInView({
    required this.busy,
    required this.error,
    required this.onGoogle,
    required this.onApple,
    required this.onLogin,
  });
  final bool busy;
  final String? error;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(
            subtitle:
                'Commencez avec votre compte Google ou Apple — le même que sur '
                'l\'application Zappart si vous en avez déjà un.'),
        const SizedBox(height: 26),
        _ProviderButton(
          onPressed: busy ? null : onGoogle,
          label: 'Continuer avec Google',
          icon: const _GoogleG(),
        ),
        const SizedBox(height: 12),
        _ProviderButton(
          onPressed: busy ? null : onApple,
          label: 'Continuer avec Apple',
          icon: const Icon(Icons.apple, size: 19, color: AppTheme.ink),
        ),
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 14),
          _ErrorRow(error!),
        ],
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: onLogin,
            child: Text('J\'ai déjà un accès Pro → me connecter',
                style: GoogleFonts.mavenPro(
                    fontSize: 12.5, color: AppTheme.inkSoft)),
          ),
        ),
      ],
    );
  }
}

class _PendingView extends StatelessWidget {
  const _PendingView({required this.email, required this.onSignOut});
  final String email;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(subtitle: ''),
        const SizedBox(height: 30),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.mark_email_read_outlined,
                  size: 34, color: AppTheme.success),
              const SizedBox(height: 12),
              Text('Demande envoyée',
                  style: GoogleFonts.mavenPro(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Votre demande pour le compte $email est en cours de '
                'validation par l\'équipe Zappart. Vous recevrez un message dès '
                'que votre espace est ouvert.',
                textAlign: TextAlign.center,
                style: GoogleFonts.mavenPro(
                    fontSize: 13, height: 1.5, color: AppTheme.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: () async {
            await FirebaseAuth.instance.currentUser?.reload();
          },
          child: const Text('Actualiser'),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: onSignOut,
            child: Text('Se déconnecter',
                style: GoogleFonts.mavenPro(
                    fontSize: 12, color: AppTheme.inkSoft)),
          ),
        ),
      ],
    );
  }
}

// ── Briques ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const ZappartWordmark(height: 32),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.ink,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('PRO',
                  style: GoogleFonts.mavenPro(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Devenir partenaire',
            style: GoogleFonts.mavenPro(
                fontSize: 23, fontWeight: FontWeight.w700)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(subtitle,
              style:
                  GoogleFonts.mavenPro(fontSize: 13, color: AppTheme.inkSoft)),
        ],
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.left,
    required this.right,
    required this.value,
    required this.onChanged,
  });
  final String left;
  final String right;
  final bool value; // false = left, true = right
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String t, bool selected, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected ? AppTheme.ink : Colors.transparent),
              ),
              child: Text(t,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.mavenPro(
                      fontSize: 12.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppTheme.ink : AppTheme.inkSoft)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        seg(left, !value, () => onChanged(false)),
        const SizedBox(width: 4),
        seg(right, value, () => onChanged(true)),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
  });
  final String label;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, VoidCallback? onTap) => IconButton(
          onPressed: onTap,
          icon: Icon(i, size: 18),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.panel,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.mavenPro(
                  fontSize: 13, color: AppTheme.ink)),
        ),
        btn(Icons.remove, value > min ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 34,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.mavenPro(
                  fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        btn(Icons.add, () => onChanged(value + 1)),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, size: 15, color: AppTheme.danger),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: GoogleFonts.mavenPro(
                  fontSize: 12, color: AppTheme.danger)),
        ),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.onPressed,
    required this.label,
    required this.icon,
  });
  final VoidCallback? onPressed;
  final String label;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.line),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(width: 10),
                Text(label,
                    style: GoogleFonts.mavenPro(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F6E56), Color(0xFF10231C)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vos loyers, vos baux,\nvos quittances —\nau même endroit.',
                  style: GoogleFonts.mavenPro(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      height: 1.25)),
              const SizedBox(height: 12),
              Text(
                'Gratuit jusqu\'à 3 baux. Aucune commission Zappart sur '
                'vos loyers.',
                style: GoogleFonts.mavenPro(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                    height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Petit « G » Google multicolore, dessiné (pas d'asset).
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 18, height: 18, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final r = (size.width - stroke) / 2;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    void arc(double s, double sw, Color col) {
      p.color = col;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r),
          s * 3.1415926 / 180, sw * 3.1415926 / 180, false, p);
    }

    arc(-20, -140, const Color(0xFF4285F4));
    arc(-160, -80, const Color(0xFFEA4335));
    arc(120, 80, const Color(0xFFFBBC05));
    arc(40, 80, const Color(0xFF34A853));
    p
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF4285F4);
    canvas.drawRect(
        Rect.fromLTWH(c.dx, c.dy - stroke / 2, r + stroke / 2, stroke), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
