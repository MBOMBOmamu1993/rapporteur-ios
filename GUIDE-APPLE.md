# Publier Rapporteur sur l'App Store — le guide, pas à pas

Ce guide mène du compte développeur Apple à l'application en ligne, **sans
Mac** : tout ce qui exige macOS tourne sur GitHub Actions. Il sert aussi pour la
version **Mac** de l'application de bureau (même compte, même signature).

Apple n'impose **aucune période de test** : une fois le build téléversé, on
l'attache à la version et on l'envoie à l'examen. TestFlight est facultatif et
n'est pas utilisé ici.

---

## 1. Le compte développeur Apple (99 $ par an)

Ce que vous faites vous-même — je ne peux ni créer le compte ni payer.

1. **Un identifiant Apple avec l'authentification à deux facteurs**, à votre
   nom, avec une adresse que vous lisez (fellybokota@gmail.com convient : c'est
   celle de vos autres comptes). Créez-le sur https://appleid.apple.com si
   besoin, et activez la validation en deux étapes — l'inscription la refuse
   sinon.
2. **L'inscription au programme** : https://developer.apple.com/programs/enroll/
   → *Start Your Enrollment*. Deux voies :
   - **Sur un iPhone ou un iPad**, avec l'application *Apple Developer*
     (App Store) : c'est la voie la plus simple pour une **personne
     physique** — elle photographie votre pièce d'identité et prend le
     paiement par la carte du compte Apple.
   - **Sur le web**, pour une entité (entreprise) : Apple demande alors un
     numéro **D-U-N-S** (gratuit, une à deux semaines à obtenir) et une
     personne habilitée à signer. Pour aller vite, inscrivez-vous en
     **personne physique** : le nom du vendeur affiché sur l'App Store sera le
     vôtre, et il pourra être converti en entité plus tard.
3. **Le paiement** : 99 $ US par an, par carte bancaire. Apple vérifie
   l'identité (quelques heures à deux jours) puis envoie « Welcome to the
   Apple Developer Program ».
4. Notez votre **Team ID** (10 caractères) : https://developer.apple.com/account
   → *Membership details*. C'est le secret `APPLE_EQUIPE`.

> Disponibilité : le programme accepte les personnes physiques de la
> République démocratique du Congo. Si l'inscription refusait le pays de la
> carte, une carte d'un autre pays au même nom passe.

## 2. La clé d'API App Store Connect (pour que GitHub signe et téléverse)

1. https://appstoreconnect.apple.com → *Users and Access* → onglet
   **Integrations** → *App Store Connect API* → *Team Keys* → **+**.
2. Nom : `GitHub Actions`, accès : **Admin**. *App Manager ne suffit pas* :
   la signature dans le nuage crée un certificat de distribution, et seule une
   clé Admin en a le droit — sinon l'export échoue sur « Cloud signing
   permission error ». (Constaté le 08/09/2026 : la première clé, App Manager,
   a dû être remplacée.)
3. Téléchargez le fichier **`AuthKey_XXXXXXXXXX.p8`** — **une seule fois
   possible** : gardez-le hors du dépôt (par exemple dans votre gestionnaire de
   mots de passe).
4. Relevez le **Key ID** (dans le nom du fichier) et l'**Issuer ID** (en haut de
   la page).

Dans le dépôt GitHub `rapporteur-ios` → *Settings → Secrets and variables →
Actions → New repository secret*, créez :

| Secret | Valeur |
|---|---|
| `APPLE_EQUIPE` | le Team ID |
| `ASC_CLE_ID` | le Key ID |
| `ASC_EMETTEUR_ID` | l'Issuer ID |
| `ASC_CLE_P8` | le contenu du fichier `.p8`, collé tel quel (les lignes BEGIN/END comprises) |

> **Le compte, tel qu'il est** (relevé le 08/09/2026) : Team ID `HAJ75PNSBY`,
> inscription *personne physique*, Issuer ID `5369585d-d013-472a-b029-cdf1b2f38736`,
> clé de signature `J5KDJK52QC` (Admin). L'*Apple ID* de l'application est
> **6809614915** — c'est le numéro de `https://apps.apple.com/app/id6809614915`.
> Le premier accès à l'API demande un clic « Demander l'accès » (approuvé dans
> la seconde) et l'acceptation des conditions d'App Store Connect.

## 3. L'identifiant de l'application et la fiche App Store Connect

1. https://developer.apple.com/account/resources/identifiers → **+** →
   *App IDs* → *App* → Description `Rapporteur`, **Bundle ID explicit :
   `com.lerapporteur.mobile`**. Capabilities : rien à cocher (pas de push,
   pas de paiement Apple). *Register*.
2. https://appstoreconnect.apple.com → *Apps* → **+** → *New App* :
   - Platforms : **iOS** ; Name : **Rapporteur — Comptes rendus** ; Primary
     language : **French (France)** ; Bundle ID : celui créé ; SKU :
     `rapporteur-ios` ; User Access : *Full Access*.
3. Remplissez la fiche avec les textes de [app-store/fiche.md](app-store/fiche.md)
   (les mêmes que Google Play, adaptés) : sous-titre, description, mots-clés,
   URL d'assistance, URL de confidentialité (`https://lerapporteur.com/confidentialite`),
   catégorie **Productivity**, copyright.
4. **Captures d'écran** : nos fichiers font 1290 × 2796, ce qui est la taille
   **6,9 pouces** — et non celle que la page de la version propose par défaut
   (6,5", qui les refuse). Passez par *Afficher toutes les tailles dans le
   gestionnaire des visuels*, dépliez « Écran de 6,9 pouces » et déposez-les là ;
   Apple les réutilise pour les autres tailles. **Une par une** : un envoi
   groupé les range dans l'ordre d'arrivée, pas dans celui des noms. Le script
   `outils/captures-appstore.mjs` du dépôt `rapporteur-web` les produit
   depuis le site (voir le README de ce dossier). Pas de vidéo obligatoire.
5. **App Privacy** (déclaration de confidentialité, exigée avant l'envoi) :
   *Data collected* → **Contact Info → Email Address** et **User Content →
   Audio Data**, tous deux « Fonctionnalité de l'app », tous deux **liés à
   l'identité**, aucun suivi. L'audio EST lié : il est déposé sous le compte du
   client avant d'être supprimé — déclarer le contraire serait un décalage, et
   Apple retire une application dont la déclaration ne tient pas. La suppression
   après transcription se dit dans la politique, pas ici. *Privacy policy URL* :
   `https://lerapporteur.com/confidentialite`.
6. **Age Rating** : répondre *None* partout → **4+**.
7. **App Review Information** : *Sign-in required* : **oui**, avec un vrai
   couple qui fonctionne — un examinateur qui ne franchit pas la porte refuse
   l'application (règle 2.1). Notre connexion n'a pas de mot de passe, alors le
   serveur en fabrique un pour cette seule adresse : les variables
   `EXAMEN_COURRIEL` et `EXAMEN_CODE` de `rapporteur-web` (Vercel, production)
   ouvrent `demo@lerapporteur.com` avec un code fixe à six chiffres, plafonné à
   trente essais par heure pour tout le site (voir `lib/connexion-courriel.js`).
   On met l'adresse dans *Nom d'utilisateur*, le code dans *Mot de passe*, et
   l'on **retire `EXAMEN_CODE` après l'approbation**. Notes pour l'examinateur :
   voir `app-store/fiche.md` — elles expliquent le micro en arrière-plan,
   l'absence d'achat, et comment se connecter.

## 3 bis. Le statut de commerçant (règlement européen DSA)

Sans cette déclaration, Apple retire l'application de l'App Store **européen** —
mais elle ne bloque pas la soumission. *Business → Compléter les exigences de
conformité* : « J'ai le statut de commerçant », puis l'adresse, le téléphone et
le courriel qui seront **publics sur la fiche** — ceux du site :
22 bis Ndjoku, Ngaliema, Kinshasa ; `sales@lerapporteur.com`. Apple valide
l'adresse par un code courriel, puis le numéro. Aucun RCCM n'a été demandé.

Deux pièges : le champ *Indicatif du pays* doit être choisi explicitement (le
laisser vide fait échouer la validation du numéro sans le dire), et un code
courriel neuf est envoyé à **chaque** tentative — c'est toujours le dernier qui
vaut. Un numéro peut être refusé (« ne peut pas être utilisé pour l'instant ») :
essayez-en un autre.

## 4. Construire et téléverser (GitHub Actions)

1. Dépôt `rapporteur-ios` → onglet **Actions** → *Publier sur App Store
   Connect* → **Run workflow** → version `1.0.0`.
2. Durée : 10 à 15 minutes. La première fois, Xcode crée dans le nuage le
   certificat de distribution et le profil : rien à installer.
3. App Store Connect → votre application → onglet **TestFlight** ou la
   version → le build `1.0.0 (N)` apparaît sous *Build* après 5 à 20 minutes
   de traitement (courriel « has completed processing »). Ne rien faire dans
   TestFlight : le build sert directement à la version.

Deux pièges déjà franchis, corrigés dans `publier.yml` — ne les rouvrez pas :

- **Le Xcode n'est jamais épinglé.** L'image macOS de GitHub ne garde que les
  runtimes de simulateur du Xcode courant ; sur une version plus ancienne,
  `actool` refuse le catalogue d'icônes (« No simulator runtime version …
  available to use with iphonesimulator SDK »), alors même que l'on compile
  pour un appareil. Le workflow prend le plus récent des `Xcode_*.app`.
- **L'archive n'est pas signée.** Signée, `xcodebuild archive` réclame un
  profil *iOS App Development*, qu'Apple refuse de fabriquer tant que l'équipe
  ne déclare aucun appareil — et nous n'en avons pas. On archive donc avec
  `CODE_SIGNING_ALLOWED=NO` et l'on confie la signature de distribution à
  `-exportArchive`. L'application ne porte aucun droit particulier : rien ne se
  perd.

Si l'export échoue sur la signature (« No signing certificate »), la solution
de repli est de créer le certificat *Apple Distribution* soi-même
(developer.apple.com → Certificates → **+** → *Apple Distribution*, avec une
demande CSR générée par `openssl req -new -newkey rsa:2048 -nodes -keyout
distribution.key -out distribution.csr`), de l'exporter en `.p12` et de
l'importer dans le trousseau du runner — mais la voie automatique par clé d'API
est celle de Xcode 13 et suivants, et suffit dans la grande majorité des cas.

## 5. Envoyer à l'examen — sans TestFlight

1. App Store Connect → *App Store* → version **1.0 Prepare for Submission** →
   *Build* → **+** → choisir le build téléversé.
2. **Export compliance** : déjà répondu par l'application
   (`ITSAppUsesNonExemptEncryption = NO`, HTTPS standard seulement).
3. *Version Release* : **Manually release** (vous cliquez vous-même à
   l'approbation) ou *Automatically*.
4. **Add for Review** → **Submit to App Review**.

Délai habituel : 24 à 48 heures, parfois une semaine. Vous êtes prévenu par
courriel à chaque changement d'état (*In Review*, *Approved* / *Rejected*).

## 6. Ce que l'examen regardera de près

- **4.2 Fonctionnalité minimale** (« l'application n'est qu'un site web
  emballé ») : la réponse est la **capture native écran éteint** — une page
  Safari ne sait pas le faire — et la notification de silence. Les notes pour
  l'examen le disent en clair.
- **2.5.4 Audio en arrière-plan** : autorisé pour un enregistreur de réunion
  (comme Dictaphone). La capture doit visiblement continuer écran éteint, et
  s'arrêter quand l'utilisateur appuie sur Arrêter : c'est le cas.
- **3.1.1 Achats** : aucun achat dans l'application, aucun lien vers la
  caisse, aucun texte « allez sur notre site pour payer » — le site masque
  tout quand la boutique est `appstore`. Ne pas contourner.
- **5.1.1 Confidentialité** : texte du micro
  (`NSMicrophoneUsageDescription`) explicite ; la politique du site couvre
  l'audio (supprimé après transcription).
- **Compte de démonstration** fonctionnel : vérifiez avant l'envoi que
  demo@lerapporteur.com a du solde (3 comptes rendus) et que la connexion par
  code courriel répond.

En cas de rejet, la réponse arrive dans *App Review* avec la règle citée ; on
corrige, on relance *Publier* avec la version suivante (`1.0.1`), on rattache
le build et on renvoie — le fil de discussion avec l'examinateur reste ouvert.

## 7. Après l'approbation

1. Relevez l'adresse de la fiche : `https://apps.apple.com/app/id<numéro>` (le
   numéro est l'*Apple ID* de l'application dans *App Information*).
2. Dans `rapporteur-web/vercel.json`, la redirection `/ios` pointe vers cette
   adresse : le **code QR imprimé sur l'accueil** mène alors à l'App Store sans
   être refait. Puis `APPLIS.ios.disponible = true` dans `index.html` et
   `en/index.html`, et `IOS_DISPONIBLE = true` dans `js/compte.js`.
3. Ajoutez la carte « L'application iPhone » sur l'accueil et « iPhone » dans
   les tarifs et la confidentialité — le contrôle `outils/verifier.js` le
   demandera.

## 8. La version Mac de l'application de bureau (même compte)

L'application Windows est une coquille Electron ; electron-builder produit un
`.dmg` sur une machine macOS de GitHub Actions. Sans signature, macOS refuse
d'ouvrir le fichier (« impossible de vérifier ») ; avec le compte développeur,
on **signe et notarise** dans le workflow. Il faut :

- un certificat **Developer ID Application** (developer.apple.com →
  Certificates → **+**), exporté en `.p12` → secrets `MAC_CERT_P12` (base64) et
  `MAC_CERT_MDP` ;
- la clé d'API ci-dessus pour la notarisation : `ASC_CLE_ID`,
  `ASC_EMETTEUR_ID`, `ASC_CLE_P8`.

Le workflow du dépôt `rapporteur-windows` produit alors `Rapporteur.dmg` à
côté de `Rapporteur-Setup.exe` dans la même *Release* ; la redirection `/mac`
du site pointe dessus. Point à vérifier sur un vrai Mac avant d'annoncer :
la capture du son des autres applications (Teams, Zoom) passe par
`audio: "loopback"` d'Electron, dont la prise en charge macOS dépend de la
version — le micro (réunion en salle, haut-parleur) marche dans tous les cas.
