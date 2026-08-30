import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand.dart';

/// Écran de connexion — carte flottante à deux volets : visuel + accroche à
/// gauche, formulaire à droite. Sous ~900 px, seul le formulaire reste.
///
/// Les partenaires se sont inscrits via Google / Apple sur mobile (aucun mot
/// de passe) → même projet Firebase = même compte = `partenaire_ref` déjà lié.
/// Le bloc e-mail / mot de passe reste pour les comptes internes.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  static const _heroImage =
      'https://images.unsplash.com/photo-1560518883-ce09059eeffa'
      '?auto=format&fit=crop&w=1400&q=80';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _message(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'Adresse e-mail invalide.';
        case 'user-disabled':
          return 'Ce compte est désactivé.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'E-mail ou mot de passe incorrect.';
        case 'too-many-requests':
          return 'Trop de tentatives. Réessayez dans quelques minutes.';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<AuthService>()
          .signInWithEmail(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _oauth(Future<void> Function() run) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await run();
    } catch (e) {
      final msg = _message(e);
      if (mounted && msg.isNotEmpty) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() =>
          _error = 'Entrez votre e-mail puis « Mot de passe oublié ».');
      return;
    }
    try {
      await context.read<AuthService>().sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('E-mail de réinitialisation envoyé.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B4C5A), Color(0xFF2E6C8E), Color(0xFF4C93C4)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: wide ? 980 : 460, minHeight: 0),
              child: Material(
                color: Colors.white,
                elevation: 18,
                shadowColor: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide)
                        Expanded(
                          flex: 5,
                          child: _HeroPanel(imageUrl: _heroImage),
                        ),
                      Expanded(
                        flex: 6,
                        child: _FormPanel(
                          formKey: _formKey,
                          email: _email,
                          password: _password,
                          obscure: _obscure,
                          busy: _busy,
                          error: _error,
                          onToggleObscure: () =>
                              setState(() => _obscure = !_obscure),
                          onSubmit: _submit,
                          onForgot: _forgotPassword,
                          onGoogle: () => _oauth(() =>
                              context.read<AuthService>().signInWithGoogle()),
                          onApple: () => _oauth(() =>
                              context.read<AuthService>().signInWithApple()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Volet gauche : photo plein cadre + dégradé sombre + accroche.
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2E6C8E), Color(0xFF24333D)],
              ),
            ),
          ),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const ColoredBox(color: Color(0xFF24333D)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x22000000), Color(0xCC0C1A22)],
              stops: [0.35, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilotez votre parc,\nun bien à la fois.',
                style: GoogleFonts.mavenPro(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Zappart Pro — votre espace de gestion locative : '
                'annonces, réservations, revenus.',
                style: GoogleFonts.mavenPro(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Volet droit : logo, titres, fournisseurs, formulaire e-mail.
class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.formKey,
    required this.email,
    required this.password,
    required this.obscure,
    required this.busy,
    required this.error,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onForgot,
    required this.onGoogle,
    required this.onApple,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool obscure;
  final bool busy;
  final String? error;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onForgot;
  final VoidCallback onGoogle;
  final VoidCallback onApple;

  InputDecoration _dec(String label, String hint, IconData icon,
      {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 19, color: AppTheme.inkSoft),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFFAFAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.ink, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
      child: Form(
        key: formKey,
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const ZappartWordmark(height: 24),
                  const SizedBox(width: 9),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.ink,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('PRO',
                        style: GoogleFonts.mavenPro(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 1)),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('Bon retour',
                  style: GoogleFonts.mavenPro(
                      fontSize: 23, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Connectez-vous pour accéder à votre tableau de bord.',
                style: GoogleFonts.mavenPro(
                    fontSize: 13, color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration:
                    _dec('E-mail', 'nom@exemple.com', Icons.mail_outline),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'E-mail requis' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: password,
                obscureText: obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => onSubmit(),
                decoration: _dec(
                  'Mot de passe',
                  '••••••••',
                  Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                      color: AppTheme.inkSoft,
                    ),
                    onPressed: onToggleObscure,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? '6 caractères minimum' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : onForgot,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Mot de passe oublié ?',
                      style: GoogleFonts.mavenPro(
                          fontSize: 12, color: AppTheme.inkSoft)),
                ),
              ),
              if (error != null && error!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 15, color: AppTheme.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(error!,
                          style: GoogleFonts.mavenPro(
                              fontSize: 12, color: AppTheme.danger)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: busy ? null : onSubmit,
                  child: busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Continuer'),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OU',
                      style: GoogleFonts.mavenPro(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.inkSoft)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ProviderButton(
                      onPressed: busy ? null : onGoogle,
                      label: 'Google',
                      leading: const _GoogleG(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProviderButton(
                      onPressed: busy ? null : onApple,
                      label: 'Apple',
                      leading: const Icon(Icons.apple,
                          size: 18, color: AppTheme.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Pas encore partenaire ? Rejoignez Zappart depuis '
                  'l\'application mobile.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.mavenPro(
                      fontSize: 11.5, color: AppTheme.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.onPressed,
    required this.label,
    required this.leading,
  });

  final VoidCallback? onPressed;
  final String label;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
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
                leading,
                const SizedBox(width: 9),
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

/// Petit « G » Google multicolore, dessiné (pas d'asset).
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.22;
    final r = (size.width - stroke) / 2;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    void arc(double startDeg, double sweepDeg, Color color) {
      p.color = color;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r),
          startDeg * 3.1415926 / 180, sweepDeg * 3.1415926 / 180, false, p);
    }

    arc(-20, -140, const Color(0xFF4285F4)); // bleu (haut-droit)
    arc(-160, -80, const Color(0xFFEA4335)); // rouge (haut-gauche)
    arc(120, 80, const Color(0xFFFBBC05)); // jaune (bas-gauche)
    arc(40, 80, const Color(0xFF34A853)); // vert (bas-droit)

    // Barre horizontale du G
    p
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - stroke / 2, r + stroke / 2, stroke),
      p,
    );
    canvas.clipRect(rect);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
