# Fiche App Store — Rapporteur

Textes prêts à coller dans App Store Connect → votre application → *App Store*
→ version 1.0. Français (France) en langue principale ; anglais (U.S.) en
seconde localisation, à partir de la version anglaise du site (`/en`) —
glossaire : « meeting report », jamais « minutes » seul.

## Identité

- **Nom** (30 car. max) : `Rapporteur — Comptes rendus`
- **Sous-titre** (30 car. max) : `Vos réunions, rédigées pour vous`
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

`compte rendu,réunion,enregistreur,transcription,procès-verbal,dictaphone,notes,IA,minutes,meeting`

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

- Nom : `Rapporteur — Meeting Reports` · Sous-titre : `Your meetings, written for you`
- Promotionnel : `Three meeting reports free when you sign up. Set the iPhone down, run the meeting: the document arrives by email.`
- Description : **en place depuis le 11/09/2026** (1406 caractères) — elle était
  restée en FRANÇAIS dans la fiche anglaise jusque-là. Mêmes sections que le
  français : HOW IT WORKS, THREE WAYS TO RECORD, FAITHFUL TO THE FACTS, BUILT
  FOR THE FIELD, FREE TRIAL. Aucune autre plateforme nommée.
- Mots-clés : `meeting report,minutes,recorder,transcription,meeting notes,AI,dictaphone,summary`
