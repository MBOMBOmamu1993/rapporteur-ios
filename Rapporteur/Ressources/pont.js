/* Le pont, côté page — injecté par l'application au tout début du chargement,
   dans le cadre principal seulement.

   window.rapporteurIOS reprend l'interface du pont Android (version,
   plateforme, boutique, enregistrementDemarre/Termine) et y ajoute `capture`,
   la capture native : WebKit coupe le micro d'une page dès que l'écran
   s'éteint, l'application enregistre donc elle-même et rend le fichier ici.
   window.rapporteurAndroid en est l'ALIAS : pour le site, il veut dire
   « application mobile » — ses branches Android valent, et il lit
   rapporteurIOS là où l'iPhone diffère.

   Pas de ouvrirReunion : sur iPhone, une réunion tenue dans une autre
   application garde le micro pour elle (le système l'impose) — la salle ne
   propose donc pas d'ouvrir la réunion ici. */
(function () {
  "use strict";
  if (window.rapporteurIOS) { return; }

  var attentes = {};
  var suivant = 1;

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

    capture: {
      /* Poussé par l'application dix fois par seconde, à l'échelle du vu-mètre. */
      niveau: 0,
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
