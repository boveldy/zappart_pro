import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/abonnement/abonnement_page.dart';
import '../features/auth/devenir_partenaire_page.dart';
import '../features/auth/login_page.dart';
import '../features/baux/baux_page.dart';
import '../features/baux/fiche_bail_page.dart';
import '../features/baux/nouveau_bail_page.dart';
import '../features/calendrier/calendrier_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/not_partner_page.dart';
import '../features/parametres/parametres_page.dart';
import '../features/parc/fiche_bien_page.dart';
import '../features/parc/nouvelle_annonce_page.dart';
import '../features/parc/parc_page.dart';
import '../features/reservations/reservations_page.dart';
import '../features/revenus/revenus_page.dart';
import '../features/statistiques/statistiques_page.dart';
import '../services/auth_service.dart';
import '../shell/app_shell.dart';
import '../theme/app_theme.dart';

/// Routeur applicatif. `refreshListenable` = [AuthService] → toute bascule de
/// session (connexion, déconnexion, chargement du doc `users/{uid}`) relance
/// la logique de redirection.
GoRouter buildRouter(AuthService auth) {
  return GoRouter(
    refreshListenable: auth,
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.uri.path;
      switch (auth.access) {
        case ProAccess.loading:
          return loc == '/loading' ? null : '/loading';
        case ProAccess.loggedOut:
          // La page d'inscription gère elle-même le cas « pas connecté »
          // (boutons Google / Apple) → on l'autorise.
          return (loc == '/login' || loc == '/inscription') ? null : '/login';
        case ProAccess.notPartner:
        case ProAccess.pending:
          return loc == '/inscription' ? null : '/inscription';
        case ProAccess.partner:
          if (loc == '/login' || loc == '/loading' || loc == '/inscription') {
            return '/';
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/loading', builder: (_, __) => const _Splash()),
      GoRoute(
        path: '/inscription',
        builder: (_, __) => const DevenirPartenairePage(),
      ),
      GoRoute(path: '/no-access', builder: (_, __) => const NotPartnerPage()),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
          GoRoute(
            path: '/parc',
            builder: (_, __) => const ParcPage(),
            routes: [
              GoRoute(
                path: 'nouveau',
                builder: (_, __) => const NouvelleAnnoncePage(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) =>
                    FicheBienPage(id: s.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'publier',
                    builder: (_, s) => NouvelleAnnoncePage(
                        completerId: s.pathParameters['id']),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/baux',
            builder: (_, __) => const BauxPage(),
            routes: [
              GoRoute(
                path: 'nouveau',
                builder: (_, __) => const NouveauBailPage(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => FicheBailPage(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/calendrier',
            builder: (_, __) => const CalendrierPage(),
          ),
          GoRoute(
            path: '/reservations',
            builder: (_, __) => const ReservationsPage(),
          ),
          GoRoute(
            path: '/revenus',
            builder: (_, __) => const RevenusPage(),
          ),
          GoRoute(
            path: '/statistiques',
            builder: (_, __) => const StatistiquesPage(),
          ),
          GoRoute(
            path: '/abonnement',
            builder: (_, __) => const AbonnementPage(),
          ),
          GoRoute(
            path: '/parametres',
            builder: (_, __) => const ParametresPage(),
          ),
        ],
      ),
    ],
  );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink),
      ),
    );
  }
}
