import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';

/// Entrée de navigation du shell.
class NavItem {
  const NavItem(this.route, this.label, this.icon);
  final String route;
  final String label;
  final IconData icon;
}

const kNavItems = <NavItem>[
  NavItem('/', 'Tableau de bord', Icons.grid_view_rounded),
  NavItem('/parc', 'Parc', Icons.home_work_outlined),
  NavItem('/baux', 'Baux', Icons.description_outlined),
  NavItem('/calendrier', 'Calendrier', Icons.calendar_month_outlined),
  NavItem('/reservations', 'Réservations', Icons.event_available_outlined),
  NavItem('/revenus', 'Revenus', Icons.account_balance_wallet_outlined),
  NavItem('/statistiques', 'Statistiques', Icons.insights_outlined),
  NavItem('/parametres', 'Paramètres', Icons.settings_outlined),
];

/// Coquille commune : barre latérale (pleine ou réduite selon la largeur) +
/// barre haute + zone de contenu centrée. Reçoit l'écran actif via
/// `ShellRoute`.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AppTheme.breakpointCompact;
    final location = GoRouterState.of(context).uri.path;
    final current = kNavItems.firstWhere(
      (n) => n.route == '/'
          ? location == '/'
          : location.startsWith(n.route),
      orElse: () => kNavItems.first,
    );

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Row(
        children: [
          _Sidebar(compact: compact, current: current),
          Expanded(
            child: Column(
              children: [
                _Topbar(title: current.label),
                const Divider(height: 1),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: AppTheme.contentMaxWidth),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.compact, required this.current});
  final bool compact;
  final NavItem current;

  @override
  Widget build(BuildContext context) {
    final w = compact ? AppTheme.sidebarRailWidth : AppTheme.sidebarWidth;
    return Container(
      width: w,
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        border: Border(right: BorderSide(color: AppTheme.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppTheme.topbarHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 20),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  ZappartWordmark(height: compact ? 15 : 24),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.ink,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('PRO',
                          style: GoogleFonts.mavenPro(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                              letterSpacing: 0.8)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          for (final item in kNavItems)
            _NavTile(
              item: item,
              compact: compact,
              selected: item.route == current.route,
              onTap: () => context.go(item.route),
            ),
          const Spacer(),
          const Divider(height: 1),
          _NavTile(
            item: const NavItem('__logout', 'Déconnexion', Icons.logout_rounded),
            compact: compact,
            selected: false,
            onTap: () => context.read<AuthService>().signOut(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.compact,
    required this.selected,
    required this.onTap,
  });
  final NavItem item;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.ink : AppTheme.inkSoft;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 2),
      child: Material(
        color: selected ? AppTheme.panel : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Tooltip(
            message: compact ? item.label : '',
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 0 : 14, vertical: 11),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(item.icon, size: 20, color: color),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Text(item.label,
                        style: GoogleFonts.mavenPro(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: color,
                        )),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Topbar extends StatelessWidget {
  const _Topbar({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return SizedBox(
      height: AppTheme.topbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Text(title, style: AppTheme.h2),
            const Spacer(),
            _AgencyChip(ref: auth.partenaireRef, fallback: auth.displayName),
          ],
        ),
      ),
    );
  }
}

class _AgencyChip extends StatelessWidget {
  const _AgencyChip({required this.ref, required this.fallback});
  final DocumentReference<Map<String, dynamic>>? ref;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref?.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = (data?['nom'] as String?)?.trim();
        final logo = (data?['logo'] as String?)?.trim() ?? '';
        final label = (name?.isNotEmpty ?? false) ? name! : fallback;
        return Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.ink,
                shape: BoxShape.circle,
                image: logo.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(logo), fit: BoxFit.cover)
                    : null,
              ),
              alignment: Alignment.center,
              child: logo.isEmpty
                  ? const Icon(Icons.storefront_rounded,
                      size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.mavenPro(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }
}
