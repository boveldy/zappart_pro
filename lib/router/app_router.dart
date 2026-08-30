import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/not_partner_page.dart';
import '../features/placeholder_page.dart';
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
          return loc == '/login' ? null : '/login';
        case ProAccess.notPartner:
          return loc == '/no-access' ? null : '/no-access';
        case ProAccess.partner:
          if (loc == '/login' || loc == '/loading' || loc == '/no-access') {
            return '/';
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/loading', builder: (_, __) => const _Splash()),
      GoRoute(path: '/no-access', builder: (_, __) => const NotPartnerPage()),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
          GoRoute(
            path: '/parc',
            builder: (_, __) => const PlaceholderPage(
              title: 'Parc',
              subtitle: 'Tous vos logements',
              plannedFor: 'J2',
            ),
          ),
          GoRoute(
            path: '/calendrier',
            builder: (_, __) => const PlaceholderPage(
              title: 'Calendrier',
              subtitle: 'Disponibilités de tout le parc',
              plannedFor: 'J4',
            ),
          ),
          GoRoute(
            path: '/reservations',
            builder: (_, __) => const PlaceholderPage(
              title: 'Réservations',
              subtitle: 'Demandes et séjours',
              plannedFor: 'J3',
            ),
          ),
          GoRoute(
            path: '/revenus',
            builder: (_, __) => const PlaceholderPage(
              title: 'Revenus',
              subtitle: 'Solde, retraits et relevés',
              plannedFor: 'J5',
            ),
          ),
          GoRoute(
            path: '/parametres',
            builder: (_, __) => const PlaceholderPage(
              title: 'Paramètres',
              subtitle: 'Fiche agence et coordonnées de versement',
              plannedFor: 'J5',
            ),
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
