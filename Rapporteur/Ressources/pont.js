/* Le pont, côté page — injecté par l'application au tout début du chargement,
   dans le cadre principal seulement.

   window.rapporteurIOS reprend l'interface du pont Android (version,
   plateforme, boutique, enregistrementDemarre/Termine) et y ajoute `capture`,
   la capture native : WebKit coupe le micro d'une page dès que l'écran
   s'éteint, l'application enregistre donc elle-même et rend le fichier ici.
   window.rapporteurAndroid en est l'ALIAS : pour le site, il veut dire
   « application mobile » — ses branches Android valent, et il lit
   rapporteurIOS là où l'iPhone diffère.

   ouvrirReunion : sur iPhone, une réunion tenue dans l'application Teams ou
   Zoom garde le micro pour elle (le système l'impose). Ouverte ICI, en
   version web, dans le panneau du haut, elle reste dans notre application :
   la réunion et l'enregistreur partagent le micro, comme sur Android. */
(function () {
  "use strict";
  if (window.rapporteurIOS) { return; }

  var attentes = {};
  var suivant = 1;
  /* La réunion du panneau (1.1.13) : l'application pousse son état (_etatReunion),
     la page le lit sans attendre. */
  var etatReunion = { possible: false };
  /* Les écouteurs (1.1.13) : l'application pousse leur état (_ecouteurs) au chargement
     et à chaque changement ; l'interprète le lit à chaque tour. */
  var etatEcouteurs = { branches: false };

  function appeler(action, params) {
    return new Promise(function (resolve, reject) {
      var id = suivant++;
      attentes[id] = { resolve: resolve, reject: reject, morceaux: [] };
      try {
        window.webkit.messageHandlers.rapporteur.postMessage({ id: id, action: action, params: params || {} });
      } catch (e) {
        delete attentes[id];
        reject(e);
      }
    });
  }

  function versOctets(b64) {
    var bin = atob(b64);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) { out[i] = bin.charCodeAt(i); }
    return out;
  }

  var pont = {
    version: function () { return "__VERSION__"; },
    plateforme: function () { return "ios"; },
    /* « appstore » : comme « play », les achats se font hors de l'application
       (règle 3.1.1 de l'App Store) — le site masque prix et caisses. */
    boutique: function () { return "appstore"; },
    enregistrementDemarre: function () { appeler("enregistrementDemarre"); },
    enregistrementTermine: function () { appeler("enregistrementTermine"); },
    notifier: function (titre, texte) { appeler("notifier", { titre: titre, texte: texte }); },
    ouvrirReunion: function (lien) {
      appeler("ouvrirReunion", { lien: String(lien || "") }).catch(function () {});
    },
    fermerReunion: function () { appeler("fermerReunion").catch(function () {}); },
    /* L'interprète vocal parle à l'oreille : le système baisse les autres
       applications (YouTube, Teams…), puis les rend (application 1.1.12). */
    autresSons: function (baisser) {
      return appeler("autresSons", { baisser: Boolean(baisser) }).catch(function () {});
    },
    /* L'interprète et la réunion ouverte dans le panneau (1.1.13), comme sur Android :
       il l'écoute à la source (règle 6) — le son arrive par window.rapporteurSonReunion —
       et y parle à la place du client (règle 7) — le micro du client arrive par
       window.rapporteurMicroReunion, sa voix repart par voixReunion. */
    sonReunionPossible: function () { return etatReunion.possible; },
    paroleReunionPossible: function () { return etatReunion.possible; },
    sonReunion: function (capter, niveau) {
      appeler("sonReunion", { capter: Boolean(capter), niveau: Number(niveau) }).catch(function () {});
    },
    paroleReunion: function (parler, niveau) {
      appeler("paroleReunion", { parler: Boolean(parler), niveau: Number(niveau) }).catch(function () {});
    },
    /* Une dizaine de morceaux par seconde : sans réponse attendue. */
    voixReunion: function (morceau, taux) {
      try {
        window.webkit.messageHandlers.rapporteur.postMessage({ id: 0, action: "voixReunion",
          params: { morceau: String(morceau || ""), taux: Number(taux) } });
      } catch (e) { /* l'application est partie */ }
    },
    _etatReunion: function (etat) { etatReunion.possible = Boolean(etat && etat.possible); },
    /* Écouteurs ou AirPods (1.1.13) : avec eux, l'interprète écoute la salle par le micro
       de l'iPhone, que l'application prend elle-même (WebKit prendrait celui des AirPods) ;
       le son arrive par window.rapporteurMicroInterprete. Pendant un enregistrement (1.1.14),
       c'est une COPIE du micro du compte rendu : aucun second micro ne s'ouvre. */
    ecouteurs: function () { return etatEcouteurs; },
    _ecouteurs: function (etat) { etatEcouteurs = { branches: Boolean(etat && etat.branches) }; },
    microInterprete: function (capter) { return appeler("microInterprete", { capter: Boolean(capter) }); },

    capture: {
      /* Poussé par l'application dix fois par seconde, à l'échelle du vu-mètre. */
      niveau: 0,
      /* Poussé avec le niveau : depuis combien de secondes le système a retiré
         le micro à l'application (appel, Siri, autre application) — 0 tant que
         la capture tourne. La salle le dit au client sans attendre. */
      interrompueSec: 0,
      demarrer: function () { return appeler("demarrer"); },
      pause: function () { return appeler("pause"); },
      reprendre: function () { return appeler("reprendre"); },
      /* Les trois dernières minutes en .m4a, ou null s'il n'y a rien à juger. */
      extrait: function () {
        return appeler("extrait").then(function (r) {
          return r && r.octets && r.octets.length ? new Blob(r.octets, { type: "audio/mp4" }) : null;
        });
      },
      /* Le fichier de la séance, en UNE partie : la liste que la page attend. */
      arreter: function () {
        return appeler("arreter").then(function (r) {
          return r && r.octets && r.octets.length ? [new Blob(r.octets, { type: "audio/mp4" })] : [];
        });
      }
    },

    _morceau: function (id, b64) {
      var a = attentes[id];
      if (a) { a.morceaux.push(versOctets(b64)); }
    },
    _repondre: function (id, reponse) {
      var a = attentes[id];
      if (!a) { return; }
      delete attentes[id];
      if (reponse && reponse.erreur) { a.reject(new Error(reponse.erreur)); return; }
      reponse = reponse || {};
      if (a.morceaux.length) { reponse.octets = a.morceaux; }
      a.resolve(reponse);
    }
  };

  Object.defineProperty(window, "rapporteurIOS", { value: pont, writable: false, configurable: false });
  Object.defineProperty(window, "rapporteurAndroid", { value: pont, writable: false, configurable: false });
})();
