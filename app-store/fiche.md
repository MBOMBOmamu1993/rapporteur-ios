# Fiche App Store — Rapporteur

Textes prêts à coller dans App Store Connect → votre application → *App Store*
→ version 1.0. Français (France) en langue principale ; anglais (U.S.) en
seconde localisation, à partir de la version anglaise du site (`/en`) —
glossaire : « meeting report », jamais « minutes » seul.

## Identité

- **Nom** (30 car. max) : `Rapporteur — Comptes rendus`
- **Sous-titre** (30 car. max) : `Vos réunions, déjà rédigées` (posé le 14/09/2026 sur la version 1.1.6 ; l'ancien « Vos réunions, rédigées pour vous » faisait 32 caractères et n'avait jamais été enregistré : le champ était VIDE)
- **Bundle ID** : `com.lerapporteur.mobile` — **définitif** une fois le premier build téléversé
- **SKU** : `rapporteur-ios`
- **Catégorie principale** : Productivity — secondaire : Business
- **URL d'assistance** : https://lerapporteur.com/aide
- **URL de confidentialité** : https://lerapporteur.com/confidentialite
- **Copyright** : `© 2026 Rapporteur`
- **Prix** : Gratuit (les comptes rendus s'achètent sur le site, jamais dans l'application)

## Texte promotionnel (170 car. max, modifiable sans nouvel examen)

`Trois comptes rendus offerts à l'inscription. Posez l'iPhone, menez la réunion : le document arrive par courriel.`

## Description (4000 car. max)

```
Rapporteur transforme vos réunions en comptes rendus professionnels, sans que
vous ayez à prendre une seule note.

COMMENT ÇA MARCHE
• Touchez le bouton micro au début de la réunion.
• Rangez l'iPhone : l'enregistrement continue écran éteint.
• Touchez « Arrêter » : l'audio part automatiquement.
• Quelques minutes plus tard, recevez un compte rendu structuré : participants,
  points discutés, décisions, actions et responsables.

TROIS FAÇONS D'ENREGISTRER
• En salle : posez l'iPhone au centre de la table, son micro capte toute la
  salle et chaque intervenant est départagé.
• En ligne : mettez la réunion sur haut-parleur, l'iPhone capte vos
  correspondants et votre voix.
• Relecture : rejouez l'enregistrement d'une réunion passée, il est rédigé
  comme une séance en direct.

FIDÈLE AUX FAITS
Le compte rendu s'appuie uniquement sur ce qui a été dit. Pas d'invention,
pas d'approximation : les chiffres, les noms et les décisions sont restitués
tels quels.

PENSÉ POUR LE TERRAIN
• Fonctionne en français et en anglais.
• Le réseau coupé n'arrête rien : les réunions sont gardées sur l'iPhone et
  partent toutes seules quand la connexion revient.
• Réunions longues acceptées (plusieurs heures).
• Un avertisseur vous prévient si plus rien n'est capté.
• Vos enregistrements sont transmis en toute sécurité (HTTPS) et traités sur
  nos serveurs ; l'audio est supprimé après transcription.

ESSAI GRATUIT
Trois comptes rendus offerts à l'inscription, avec toutes les fonctionnalités.
```

> **NE JAMAIS remettre la ligne « Rapporteur existe aussi sur Android, Windows
> et directement au navigateur ».** Elle a coûté le refus du 11/09/2026,
> `2.3.10 Performance: Accurate Metadata` : « Revise the app's description to
> remove Android references ». La fiche App Store ne nomme aucune autre
> plateforme, et ne renvoie pas au site.

## Mots-clés (100 car. max, séparés par des virgules)

`compte rendu,réunion,enregistreur vocal,transcription,procès-verbal,dictaphone,prise de notes,IA,PV` (99 car., 14/09/2026 — règles du tech talk Apple 110358 : jamais le nom de l'app ni la catégorie, pas de pluriels, virgules sans espace)

## Nouveautés de cette version

`Première version : enregistrement écran éteint, trois modes (salle, en ligne, relecture), envoi automatique au retour du réseau.`

## Captures d'écran

| Taille | Obligatoire | Fichiers |
|---|---|---|
| iPhone 6,7" (1290 × 2796) | oui | `captures/6.7/01-accueil.png`, `02-compartiments.png`, `03-salle.png`, `04-compte-rendu.png` |
| iPhone 6,5" (1284 × 2778 ou 1242 × 2688) | non (reprend les 6,7") | — |

Produites par `outils/captures-appstore.mjs` (dépôt `rapporteur-web`) : le
site rendu à la taille d'un iPhone 15 Pro Max, avec le pont simulé, sans
bandeau d'annonce. Trois à six captures ; la première est celle qu'on voit.

## App Privacy (déclaration)

| Donnée | Usage | Liée à l'identité | Suivi |
|---|---|---|---|
| Adresse e-mail (Contact Info) | Fonctionnalité de l'app, gestion du compte | oui | non |
| Audio (User Content → Audio Data) | Fonctionnalité de l'app | non (supprimé après transcription) | non |

Rien d'autre : pas d'identifiant publicitaire, pas de localisation, pas de
contacts, pas d'analyse d'usage tierce.

## Notes pour l'examen (App Review Information → Notes)

```
Rapporteur records meetings and sends the audio to our servers, which write a
structured meeting report delivered by email.

WHY THE APP IS NOT JUST A WEBSITE
The web version cannot keep recording once the iPhone screen turns off:
WebKit suspends page media capture in the background. The app records natively
(AVAudioEngine, background audio mode), shows the level to the page, keeps the
recording on the device if the network drops, and posts a local notification
when nothing is being captured. This is the feature that requires an app.

BACKGROUND AUDIO
The "audio" background mode is used only while the user has started a
recording and until they tap Stop. The microphone indicator stays visible.

NO IN-APP PURCHASES
The app sells nothing and shows no prices, no payment pages and no link to
purchase. The free trial (3 reports) is granted to every new account by the
server. Any purchase happens on our website, outside the app, and the app never
points to it.

DEMO ACCOUNT
Sign in with "Continue with email" using demo@lerapporteur.com: a one-time code
is emailed to that address. If you need the code during review, contact
info@lerapporteur.com and we will forward it immediately, or tell us and we
will set a fixed code for the review period. Silent recordings do not consume
the balance.

HOW TO TEST
1. Open the app, tap the microphone, choose "En salle".
2. Tap Démarrer, allow the microphone, speak for a minute, lock the screen:
   recording continues (level meter resumes when unlocking).
3. Tap Arrêter: the audio uploads and the report arrives by email in a few
   minutes.
```

## Traduction anglaise (U.S.)

- Nom : `Rapporteur — Meeting Reports` · Sous-titre : `Your meetings, already written` (30 car., posés le 14/09/2026 sur la 1.1.6)
- Promotionnel : `Three meeting reports free when you sign up. Set the iPhone down, run the meeting: the document arrives by email.`
- Description : **en place depuis le 11/09/2026** (1406 caractères) — elle était
  restée en FRANÇAIS dans la fiche anglaise jusque-là. Mêmes sections que le
  français : HOW IT WORKS, THREE WAYS TO RECORD, FAITHFUL TO THE FACTS, BUILT
  FOR THE FIELD, FREE TRIAL. Aucune autre plateforme nommée.
- Mots-clés : `meeting report,minutes,voice recorder,transcription,meeting notes,AI,dictaphone,summary,secretary` (97 car., 14/09/2026 ; jusque-là la fiche anglaise portait les mots-clés FRANÇAIS)

## 14/09/2026 — approbation, version 1.1.6 en préparation, quatre langues

L'application 1.1.5 (5) est **approuvée et en ligne** (« Prête pour la
distribution », `apps.apple.com/app/id6809614915`). Ses visuels sont figés :
tout ce qui suit est posé sur la **version 1.1.6** créée le jour même dans
App Store Connect, et ne paraîtra qu'à sa publication.

Fait par l'API App Store Connect (`meetingrec-web/outils/demo/asc-api.mjs`,
clé Admin `J5KDJK52QC`, fichier `.p8` dans Downloads) — le gestionnaire des
visuels du navigateur refuse les vidéos envoyées par automate et mélange
l'ordre des captures :

- **Captures 6,9"** (1320 × 2868), cinq compositions par langue (titre, phrase,
  écran réel dans un cadre) : `captures/6.9/{fr,en,pt,es}/0N-*.png`, produites
  par `outils/demo/captures-appstore.mjs` (`--langues fr,en,pt,es`).
- **Aperçu vidéo** 886 × 1920, 28 s, H.264 30 i/s + piste stéréo muette :
  `apercu/{fr,en,pt,es}/apercu-iphone.mp4`, produit par
  `outils/demo/apercu-appstore.mjs`.
- **Localisations** : `fr-FR`, `en-US`, et nouvelles `pt-PT` (« Rapporteur —
  Atas de reunião » / « As suas reuniões, já escritas ») et `es-ES`
  (« Rapporteur — Actas de reunión » / « Sus reuniones, ya redactadas »),
  description, texte promotionnel, mots-clés et nouveautés traduits par
  `claude -p` (consigne : limites de caractères, glossaire ata/acta).
- **Nouveautés 1.1.6** (à relire avant soumission) : comptes rendus
  multilingues, affichage pt/es, zone sûre iPhone/iPad.
- **Candidature « En vedette »** envoyée le 14/09/2026 à 09 h 37 (brouillon du
  8/09 complété, type Lancement de l'app).

**1.1.6 soumise à l'examen le 14/09/2026 à 10 h 13** (ordre de Felly) : build 6
par le workflow Publier (`gh workflow run publier.yml -f version=1.1.6`, numéro
de build = numéro de run), rattaché et envoyé par `asc-api.mjs build 6` puis
`asc-api.mjs soumettre` ; publication automatique après approbation. Le natif
1.1.6 = 1.1.5 + le durcissement du pont (5e8fd5a) — toujours pas de bouton
d'achat, faute d'entitlement. Une localisation sans `supportUrl`/`marketingUrl`
et `privacyPolicyUrl` bloque la soumission (409 sans détail) : pt/es corrigées.
Le code d'examen (`EXAMEN_CODE`) a été REMIS sur Vercel pour la durée de
l'examen ; le retirer à l'approbation.

## 01/10/2026 — micro perdu en séance : correctif pour la 1.1.7

Une réunion de 26 minutes est arrivée en 39 secondes d'audio : le système avait
donné le micro à une autre application (appel ou réunion tenue sur le même
iPhone), le moteur s'était arrêté et la fin d'interruption n'a jamais été suivie
d'effet. Branche `capture/interruption-micro` : l'enregistreur marque
l'interruption dès son début (`interrompuSec`, poussé dans la page avec le
niveau), la relance est tentée à la fin de l'interruption, au retour au premier
plan et par un chien de garde toutes les deux secondes ; la salle du site affiche
aussitôt « Une autre application a pris le microphone » (jumelles fr/en/pt/es).
À publier : `gh workflow run publier.yml -f version=1.1.7` après fusion, puis
nouveautés « L'application prévient dès qu'une autre application prend le micro
et reprend d'elle-même l'enregistrement ».

**1.1.7 soumise à l'examen le 01/10/2026 à 14 h 15 UTC** (ordre de Felly) : PR #3 fusionnée
(aca7724), build 7 par le workflow Publier (run 36873165580), version créée et textes
(nouveautés + promotionnel, fr/en/pt/es) posés par `asc-api.mjs creer-version 1.1.7` et
`texte`, rattaché par `asc-api.mjs build 7`, envoyé par `asc-api.mjs soumettre`
(dossier 7b72de5b…, WAITING_FOR_REVIEW). App Store Connect ne recopie ni le texte
promotionnel ni les nouveautés d'une version à l'autre : les reposer à chaque version.
`EXAMEN_CODE` était déjà en place sur Vercel.
