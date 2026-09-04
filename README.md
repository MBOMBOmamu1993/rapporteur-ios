# Rapporteur pour iPhone

La coquille iPhone de [lerapporteur.com](https://lerapporteur.com) — le pendant
de l'application Android (`rapporteur-mobile`) et de l'application Windows,
avec la même philosophie : **aucune logique du service dans l'application**.
Elle charge le site et lui ajoute la seule chose qu'une page web ne sait pas
faire sur un iPhone : continuer d'enregistrer **écran éteint**.

Il n'y a pas de Mac ici. Le projet Xcode est **généré** (XcodeGen, `project.yml`)
et **compilé par GitHub Actions** sur une machine macOS : chaque poussée compile
pour le simulateur (`Construire`), et le workflow `Publier sur App Store Connect`
archive, signe et téléverse le build — sans TestFlight, directement attachable
à la version soumise à l'examen. Le mode d'emploi complet est dans
[GUIDE-APPLE.md](GUIDE-APPLE.md).

## Architecture

| Pièce | Rôle |
|---|---|
| `ControleurPrincipal` | Un WKWebView plein écran qui charge `lerapporteur.com/mobile`. Marque → accueil de l'application ; `/api/connexion` → fenêtre système d'authentification (ASWebAuthenticationSession) et retour par `rapporteur://connexion?billet=…` ; tarifs, caisses → jamais (version App Store) ; autres sites → Safari ; hors connexion → écran local. |
| `Pont` + `Ressources/pont.js` | Le seul pont page ↔ application. `pont.js` pose `window.rapporteurIOS` **et son alias `window.rapporteurAndroid`** : pour le site, ce nom veut dire « application mobile », ses branches Android valent, et il lit `rapporteurIOS` là où l'iPhone diffère. Appels asynchrones (`{id, action}` → `_repondre`), binaire par morceaux base64. |
| `Enregistreur` | **La capture native.** WebKit coupe le micro d'une page dès que l'écran s'éteint : l'application capte elle-même (AVAudioEngine, mode audio en arrière-plan), écrit un `.m4a` AAC 32 kbit/s mono, pousse le niveau du vu-mètre, garde les trois dernières minutes pour la sonde de parole, et rend le fichier à la page à l'arrêt — repris par la file d'attente du site comme n'importe quelle piste. |
| `Notifications` | Notification locale quand la salle alerte d'un silence (écran éteint, c'est le seul moyen). |

Côté site (`rapporteur-web`) : la salle `/enregistrer` reconnaît `DANS_IOS`
(démarrage, pause, niveau, extrait et fichier délégués à `rapporteurIOS.capture`),
les envois partent marqués `origine: "ios"`, la boutique `appstore` masque les
achats comme `play`, et `/api/connexion?application=ios` rend le même billet
que pour Android.

## Ce qui diffère d'Android, et pourquoi

- **Pas de réunion ouverte DANS l'application** (`ouvrirReunion` absent) :
  iOS donne le micro à une seule application à la fois. Une réunion Teams ou
  Zoom tenue sur le même iPhone garderait le micro ; la salle le dit et
  conseille le haut-parleur d'un autre appareil.
- **Pas d'achat** : règle 3.1.1 de l'App Store, comme la règle Paiements de
  Google Play. Le solde reste jugé par le serveur.
- **Fichier `.m4a`** (AAC) et non WebM/Opus : c'est ce qu'iOS encode ; le site
  le nomme `.mp4` et le serveur le transcrit comme les autres.

## Construire et publier

```
# à chaque poussée : GitHub Actions → « Construire » (simulateur, sans signature)
# publier : GitHub Actions → « Publier sur App Store Connect » → Run workflow → version
```

Secrets attendus par la publication : `APPLE_EQUIPE`, `ASC_CLE_ID`,
`ASC_EMETTEUR_ID`, `ASC_CLE_P8` — voir le guide. Identifiant du paquet :
`com.lerapporteur.mobile` (le même que sur Android : un identifiant par
plateforme, ils ne se croisent pas).

## Sécurité — ce qui est verrouillé

- Le pont n'écoute que les messages venant de `lerapporteur.com` ; une caisse
  de paiement embarquée n'obtient rien.
- `NSAppTransportSecurity` sans exception : HTTPS seulement.
- Le défi de connexion vit en mémoire : une application qui écouterait
  `rapporteur://` aurait le billet, jamais le défi.
- L'application ne lit aucun fichier de l'appareil ; le fichier de la séance
  est temporaire et supprimé dès que la page l'a repris.
