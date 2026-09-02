# Abonnement agences — Zappart Pro

> Note de travail — créée le 2026-09-01
> Statut : **discuté, rien codé.** Décisions à confirmer avant implémentation.
> Voir aussi : `zappart_officiel/CLAUDE.md` § « Baux & loyers » et la mémoire
> projet `baux-loyers-module.md`.

---

## 1. Ce qui est DÉJÀ construit (module Baux & loyers)

Le module de gérance locative mensuelle est en place côté `zappart_pro` (web).
Modèle éco retenu : **abonnement agence, 0 % de commission Zappart sur les loyers**.

### Collections Firestore
| Collection | Rôle | Écriture |
|---|---|---|
| `baux` | 1 doc = 1 contrat de location | direct-write agence hôte |
| `echeances` | 1 doc = 1 loyer dû/mois (générées d'avance, batch, cap 36) | direct-write agence |
| `depenses` | frais imputés (propriétaire / agence / locataire) | direct-write agence |
| `paiements_loyers` | signalements « j'ai payé » + encaissements en ligne | backend-only (callable `loyer`) |

- Statut retard / dû / à venir **dérivé de la date** côté client (pas de cron).
- Bien de gérance non publié = `house` avec `sur_marketplace:false` +
  `statut_validation:'prive'` + `active:false` (badge « Loué · privé »).
- Liaison locataire = **numéro de téléphone vérifié OTP** (`users.phone_number`,
  forme `221XXXXXXXXX` **sans `+`**). Dénormalisé sur `baux`, `echeances`,
  `paiements_loyers` en `locataire_tel_canonique`.

### Fonctionnalités livrées
- **Couche 2.1** : liste Baux, fiche bail (échéancier + actions), Nouveau bail,
  marquer payé + quittance PDF, bande « Loyers » sur le dashboard.
- **Couche 2.2** : relevé de gérance PDF/Excel (par bail + consolidé par
  propriétaire), dépenses imputées, clôture de bail + solde de caution (reçu PDF,
  annulation des échéances futures).
- **Couche 2.3** : reçu de loyer PDF dans « Ma location » (app mobile), prolonger
  un bail (tacite reconduction, loyer révisable) + bannière fin de bail, bien
  loué retiré / remis sur le marketplace, sous-quartiers (zones) alignés sur
  l'app, « Compléter et publier » un bien privé.
- **Point C** : espace locataire mobile (`zappart_officiel/lib/features/location/`,
  écran « Ma location »), callable `loyer` (`signaler` / `demander_quittance` /
  `initier`), 2 modes d'encaissement par bail (`encaissement_mode`).

### Les 2 modes d'encaissement (champ `encaissement_mode` sur le bail)
- **`direct`** (défaut) : le locataire paie l'agence hors app, touche « J'ai
  payé » → signalement → l'agence confirme → échéance `payé`. **Rien chez Zappart.**
- **`zappart`** : le locataire paie en ligne (GeniusPay), Zappart encaisse,
  échéance `payé` auto via webhook, **reversement à l'agence manuel** (payouts
  GeniusPay non dispo). Masqué tant que `app_settings.paiement_en_ligne_actif`
  est à `false`.

### État déploiement (au 2026-09-01)
- Règles Firestore (`depenses`, `paiements_loyers`, lecture locataire) :
  **DÉPLOYÉES** le 2026-08-31.
- Backend `services/loyer.py` + callable `loyer` + branche webhook `type=='loyer'` :
  **code prêt, NON déployé** (mêlé au WIP dans `main.py` / `paiement.py`).
- Ajout `'prive'` aux statuts `house` éditables (« Compléter et publier ») :
  **NON déployé**.
- zappart_pro : poussé (CI GitHub Pages). zappart_officiel : commits locaux sur
  `feature/wallet-partenaire`, non poussés.

### Reste (hors abo)
- **Paquet B** (reporté à la fin) : cron rappels retard automatiques + cron
  génération continue des échéances (tacite reconduction auto).
- Placeholders support dans `parametres_page` (vrais n° WhatsApp + e-mail).
- **Couche 3** : espace propriétaire, gestion journalier avancée, vente
  immobilière.

---

## 2. L'ABONNEMENT — ce qu'on a décidé (discussion 2026-08-31 → 09-01)

### 2.1 Principe
- L'**agence** paie un forfait mensuel prévisible. **0 % de commission Zappart
  sur les loyers.**
- Unité de compte = **le bail actif** (pas le bien : un bien vide ne coûte rien
  à gérer ; c'est le bail qui génère échéances, quittances, relances, relevés).
- Règle d'or du prix : rester **sous ~5–8 % du revenu de gérance mensuel** de
  l'agence.
- Zappart ne s'insère JAMAIS dans la relation agence ↔ propriétaire. Le
  propriétaire touche son argent de son agence. Zappart fournit le relevé
  (calcul d'affichage), pas un mouvement de compte. Pas de « solde propriétaire ».

### 2.2 Grille de prix proposée (à confirmer par l'utilisateur)
> FCFA/mois. Le « prix normal » sert d'ancrage (prix barré). Au lancement
> personne ne le paie.

> ⚠️ Grille indicative — la **source de vérité** est `lib/services/abonnement.dart`
> (`_quota` / `_prixLancement`) et `zappart-pro.html`.

| Plan | Baux actifs | Prix mensuel | Cible |
|---|---|---|---|
| **Découverte** | jusqu'à 3–5 | Gratuit | gérant indépendant, agence qui teste |
| **Gérant** | jusqu'à 15 | 9 000 | petit portefeuille |
| **Agence** | jusqu'à 40 | 25 000 | agence établie |
| **Agence +** | jusqu'à 100 | 55 000 | agence multi-utilisateurs |
| **Réseau** | 100+ | sur devis (dès 120 000) | multi-agences, franchise |

**Option annuelle** : 2 mois offerts (payer 10, avoir 12).
- Essentiel annuel : 150 000/an (= 12 500/mois)
- Agence annuel : 350 000/an (= ~29 000/mois)

**Au lancement, AUCUNE fonctionnalité bloquée par plan** — seul le nombre de
baux compte. Quittances, relevés, dépenses, espace locataire : partout. Le plan
Découverte gratuit est le **canal d'acquisition grand public** (chaque agence
gratuite met ses locataires sur l'app Zappart).

### 2.3 Comment ça se passe — cycle de vie
1. Inscription agence → validée par l'admin → démarre **auto en Découverte**.
2. Compteur permanent « 4 / 5 baux ».
3. Création du bail au-delà du quota → écran bloquant *« limite atteinte,
   passez à Essentiel »*. **Les baux existants continuent** (échéances,
   quittances, encaissement) — on ne bloque jamais les locataires.
4. Passage payant → paiement (voir 2.4) → `abonnement_actif_jusqu = +1 mois`.
5. Rappel J-7 (bandeau + notif).
6. À l'échéance non payée : **+7 j de grâce** (tout marche) → **blocage
   création** de nouveau bail → **lecture seule complète à J+30**.
7. Downgrade possible à la prochaine échéance si l'agence repasse sous un quota
   inférieur.

### 2.4 Paiement de l'abo — DÉCISION : en ligne dès le lancement (GeniusPay)
Vérifié le 2026-09-01 : **GeniusPay encaisse pour de vrai**
(`services/paiement.py::_appeler_prestataire` appelle
`https://geniuspay.ci/api/v1/merchant/payments`, Wave / OM / carte, XOF ;
webhook `geniuspay_webhook` confirme). Déjà déployé. Seuls les **payouts**
(argent sortant) n'existent pas — l'encaissement marche.

→ **Pas de « V1 manuelle ».** L'abo se paie en ligne, self-service dans
zappart_pro. Même plomberie que loyers/boost : ajouter une branche
`type == 'abonnement'` dans le webhook. C'est le cas le plus PROPRE :
**100 % revenu Zappart**, l'argent reste chez Zappart → aucun reversement,
aucun payout, aucun wallet.

**3 nuances qui restent :**
1. Le flag `paiement_en_ligne_actif` est encore `false`. Soit on l'active (actif
   pour tout : loyers + boost + abo), soit on ajoute un flag dédié
   `abonnement_en_ligne_actif` pour lancer l'abo seul.
2. **Pas de prélèvement automatique** (GeniusPay ne tokenise pas le mobile money
   sénégalais). « Abo en ligne » = l'agence clique **« Renouveler »** et paie
   chaque mois. Rachat mensuel self-service, pas un abonnement façon Netflix.
3. **Garder un chemin manuel en complément** (pas à la place) : virement
   bancaire, et surtout l'admin doit pouvoir prolonger / offrir un mois /
   corriger un paiement non synchronisé → page admin d'exception.

### 2.5 Où c'est géré (implémentation prévue, léger)
- **Collection `abonnements/{partenaireRef}`** : `formule`, `statut`
  (`actif` / `grace` / `suspendu`), `actif_jusqu`, `quota_baux`, `prix_mensuel`,
  `fondateur` (bool), `historique_paiements[]`.
- **Compteur de baux** = `count(baux where partenaire_ref == X and statut == 'actif')`.
- **`AuthService` (Pro)** lit `abonnements/{ref}` → expose `abonnement` (plan,
  quota, statut, jours restants) à toutes les pages + gating progressif.
- **Page Pro « Mon abonnement »** : plan actuel, jauge « 14 / 20 baux », bouton
  *Renouveler* / *Passer à Agence*, historique.
- **Page admin « Abonnements »** : liste agences (plan, échéance, statut),
  *Marquer payé* (+ référence, comme les retraits partenaires), file des
  demandes, relances, gestes commerciaux.
- **V2** : bouton *Renouveler* → GeniusPay one-shot → webhook `type=='abonnement'`
  → prolonge `actif_jusqu`.

### 2.6 App ou site ? — DÉCISION : site uniquement (zappart_pro)
- L'abo est une affaire d'agence → **zappart_pro (web) seulement**.
- L'app mobile `zappart_officiel` sert locataires / clients / hôtes marketplace,
  aucun ne paie un abo de gérance. Le locataire paie son **loyer** dans
  « Ma location », jamais l'abo — il ne voit rien de l'abonnement.
- Patron d'agence en mobilité : zappart_pro est Flutter Web, tourne dans un
  navigateur mobile → possibilité de le rendre **installable (PWA)** pour
  l'effet « app » sans 2ᵉ app native.
- Aucune section gérance prévue dans l'app native (métier de bureau).

### 2.7 Stratégie de lancement
1. **Découverte généreux** : quota large au lancement (5 baux gratuits), à
   resserrer plus tard.
2. **Annuel** : 2 mois offerts (payer 10, avoir 12) → cash-flow + fidélisation.
   Seule remise en place.

> **Décision 2026-09-02** : on retire le tarif Fondateur (−40 % à vie), les
> promos temps limité, le grandfathering verrouillé et le parrainage
> inter-agences. Grille de prix unique, plus le rabais annuel. Champ
> `abo_fondateur` supprimé du code (Pro + backend `paiement.py`) et de la page
> marketing.

### 2.8 Frais de transaction (mode `zappart` uniquement — loyers, pas l'abo)
Aujourd'hui non tracés → Zappart les absorbe (absurde à 0 % de commission).
Décision à prendre : **à la charge du locataire par défaut** (le locataire paie
`loyer + frais`), l'agence peut choisir de les absorber bail par bail. Ajouter
un champ `frais_transaction` sur `paiements_loyers`. **Ne concerne PAS l'abo**
(l'abo est 100 % Zappart, les frais GeniusPay sont juste un coût interne couvert
par le prix de l'abo).

---

## 3. Ordre de construction proposé (V1)
1. Collection `abonnements` + démarrage auto en Découverte à la validation de
   l'agence.
2. Compteur de baux actifs + écran bloquant au dépassement de quota.
3. Gating progressif dans `AuthService` (grâce 7j → blocage création → lecture
   seule 30j).
4. Page Pro « Mon abonnement » (plan, jauge, historique, bouton payer).
5. Paiement en ligne : branche `type=='abonnement'` dans le webhook GeniusPay +
   flag `abonnement_en_ligne_actif`.
6. Page admin « Abonnements » (demandes, marquer payé, virements, gestes
   commerciaux).
7. Offre Fondateur (badge + prix verrouillé) et promos.
