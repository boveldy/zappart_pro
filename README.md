# Zappart Pro (web)

Interface **web de gestion** pour les partenaires Zappart (agences, gérants,
propriétaires multi-biens). Tape le **même backend Firebase** que l'app
officielle (projet `zappartofficiel-wqtyxj`) — mêmes collections Firestore,
même Auth, mêmes Cloud Functions.

> Mobile = companion (actions urgentes). Web = travail de fond (parc,
> calendrier, réservations, revenus, relevés). Le rôle `admin` (reprise de
> `zappart_admin`) viendra dans une phase ultérieure.

## Lancer en local

```bash
flutter pub get
flutter run -d chrome        # ou: flutter run -d web-server --web-port 5000
```

## Build

```bash
flutter build web --no-tree-shake-icons
# sortie: build/web/  (fichiers statiques)
```

## Hébergement (plus tard)

Rien à décider maintenant. Deux options simples le moment venu :

- **GitHub Pages** — pousser `build/web/` sur une branche `gh-pages`
  (`flutter build web --base-href /zappart_pro/`).
- **Firebase Hosting** — même projet Firebase, `firebase deploy --only hosting`,
  domaine `pro.zappart.xx`.

## Structure

```
lib/
├── main.dart                → init Firebase + MaterialApp.router
├── firebase_options.dart    → config web (identique à l'app officielle)
├── theme/app_theme.dart     → charte Zappart (Maven Pro, noir, fond blanc)
├── services/auth_service.dart → session + résolution partenaire_ref
├── router/app_router.dart   → go_router + garde d'accès
├── shell/app_shell.dart     → sidebar + topbar + zone de contenu
└── features/
    ├── auth/login_page.dart
    ├── not_partner_page.dart
    └── placeholder_page.dart → sections à construire (J2→J5)
```

## Accès

Un compte peut ouvrir Zappart Pro si son doc `users/{uid}` porte un
`partenaire_ref` (posé par le trigger backend `link_partenaire_from_user`).
Sinon → écran « Accès réservé aux partenaires ».

Les comptes sont créés par l'équipe Zappart (pas d'auto-inscription web pour
l'instant). Connexion e-mail + mot de passe — activer la méthode
**E-mail/Mot de passe** dans la console Firebase Auth.

## État (J1 — fait)

- [x] Projet Flutter Web + dépendances Firebase
- [x] Init Firebase web (même projet)
- [x] Thème Zappart
- [x] Auth e-mail/mot de passe + « mot de passe oublié »
- [x] Garde d'accès (`partenaire_ref` requis)
- [x] Shell responsive (sidebar pleine / réduite) + 6 sections routées
- [ ] J2 — Tableau de bord + Parc
- [ ] J3 — Réservations
- [ ] J4 — Calendrier centralisé
- [ ] J5 — Revenus + Paramètres
