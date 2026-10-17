/*
 * La prise du son de la réunion — posée par Rapporteur, dès le début du document,
 * dans la page de réunion de son panneau (Meet, Teams, Zoom… ouverts DANS
 * l'application). Le pendant de assets/prise-reunion.js de l'application Android.
 *
 * Pourquoi : la réunion est un son d'appel, qu'aucune application ne peut capter.
 * L'interprète ne l'entendait que par le micro, et sa voix y serait revenue : il
 * restait en sous-titres. Pris ici, à la source, le son des correspondants arrive à
 * l'interprète sans passer par le micro — sa voix peut sortir au haut-parleur
 * (demande de Felly, 16-17/10/2026).
 *
 * Ce qu'elle prend : les flux REÇUS que la page joue (la voix des correspondants),
 * jamais le micro du client ni rien d'autre de la page. Elle ne fait rien tant que
 * l'interprète ne la demande pas (capter(true, niveau)), et rend tout à l'arrêt.
 * iOS ignore le volume d'un élément audio : pour baisser la réunion, l'élément est
 * rendu muet et son flux rejoué au niveau voulu, puis rendu tel quel.
 *
 * L'autre sens (demande de Felly, 17/10/2026 : « mes interlocuteurs entendent
 * l'interprète plutôt que moi, plus fort, dans leur langue ») : quand la salle le
 * demande (parler(true, niveau)), ce que la page ENVOIE aux correspondants devient
 * la voix de l'interprète au premier plan, celle du client en fond ; pendant ce
 * temps seulement, l'interprète entend le micro du client tel que la réunion le
 * prend, dont la prise remet une copie à la salle. À l'arrêt, chaque envoi
 * retrouve le micro de la page.
 */
(function () {
  "use strict";
  if (window.__rapporteurPrise) { return; }
  /* Les services de réunion connus seulement (la liste de PanneauReunion.swift) ;
     l'application vérifie de nouveau chaque message. */
  var hote = String(location.hostname || "").toLowerCase();
  function domaine(d) { return hote === d || hote.slice(-(d.length + 1)) === "." + d; }
  var connu = hote === "meet.google.com" || domaine("teams.microsoft.com") || domaine("teams.live.com") ||
    domaine("zoom.us") || hote.slice(-10) === ".webex.com" || hote === "meet.jit.si" || domaine("whereby.com");
  if (location.protocol !== "https:" || !connu) { return; }
  var canal = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rapporteurReunion;
  if (!canal) { return; }
  function envoyer(type, b64, taux) {
    try { canal.postMessage({ type: type, b64: b64, taux: taux }); } catch (e) { /* l'application est partie */ }
  }

  var flux = [];       /* les flux reçus que la page a montrés */
  var elements = [];   /* { el, f } : les éléments audio ou vidéo qui les jouent */
  var branches = [];   /* { f, source } branchés au mélange */
  var liaisons = [];   /* les liaisons de la page : leurs envois portent le micro du client */
  var ctx = null, melange = null, relecture = null;
  var actif = false;
  var niveau = 1;

  function estFlux(f) {
    try { return Boolean(f) && typeof f.getAudioTracks === "function" && f.getAudioTracks().length > 0; } catch (e) { return false; }
  }

  function noter(f, element) {
    if (!estFlux(f)) { return; }
    if (flux.indexOf(f) < 0) { flux.push(f); if (actif) { brancher(f); } }
    if (element && !elements.some(function (x) { return x.el === element; })) {
      elements.push({ el: element, f: f });
      if (actif) { poserNiveau(); }
    }
  }

  /* Une MediaStream confiée à un élément audio ou vidéo : c'est ainsi que Meet
     et Teams font entendre les correspondants. */
  var srcObject = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, "srcObject");
  if (srcObject && srcObject.set && srcObject.configurable) {
    Object.defineProperty(HTMLMediaElement.prototype, "srcObject", {
      configurable: true,
      enumerable: srcObject.enumerable,
      get: function () { return srcObject.get.call(this); },
      set: function (valeur) {
        srcObject.set.call(this, valeur);
        try { if (valeur && typeof MediaStream !== "undefined" && valeur instanceof MediaStream) { noter(valeur, this); } } catch (e) { /* rien */ }
      },
    });
  }

  /* Les pistes reçues par une liaison, même jouées autrement. Posée dès le début du
     document, la prise voit naître toutes les liaisons de la page. */
  var Liaison = window.RTCPeerConnection;
  if (typeof Liaison === "function") {
    var Prise = function (a, b) {
      var pc = new Liaison(a, b);
      liaisons.push(pc);
      pc.addEventListener("track", function (e) {
        if (e.track && e.track.kind === "audio") { noter((e.streams && e.streams[0]) || new MediaStream([e.track]), null); }
      });
      return pc;
    };
    Prise.prototype = Liaison.prototype;
    try {
      Object.getOwnPropertyNames(Liaison).forEach(function (cle) {
        if (["length", "name", "prototype", "caller", "arguments"].indexOf(cle) < 0) { Prise[cle] = Liaison[cle]; }
      });
    } catch (e) { /* rien */ }
    window.RTCPeerConnection = Prise;
  }

  /* Les éléments déjà dans la page. */
  function balayer() {
    var liste = document.querySelectorAll("audio, video");
    for (var i = 0; i < liste.length; i++) {
      var f = null;
      try { f = liste[i].srcObject; } catch (e) { f = null; }
      if (f && typeof MediaStream !== "undefined" && f instanceof MediaStream) { noter(f, liste[i]); }
    }
  }

  function sourceDe(f) {
    for (var i = 0; i < branches.length; i++) { if (branches[i].f === f) { return branches[i].source; } }
    return null;
  }

  function brancher(f) {
    if (!ctx || sourceDe(f)) { return; }
    try {
      var source = ctx.createMediaStreamSource(f);
      source.connect(melange);
      branches.push({ f: f, source: source, rejoue: false });
    } catch (e) { /* flux fini : rien à prendre */ }
  }

  /** Un morceau de son en 16 bits, base 64 — la forme que l'application vérifie. */
  function enMorceau(d) {
    var octets = new Uint8Array(d.length * 2);
    for (var i = 0; i < d.length; i++) {
      var v = d[i] > 1 ? 1 : (d[i] < -1 ? -1 : d[i]);
      var s = (v < 0 ? v * 32768 : v * 32767) | 0;
      octets[2 * i] = s & 255;
      octets[2 * i + 1] = (s >> 8) & 255;
    }
    var binaire = "";
    for (var j = 0; j < octets.length; j += 8192) { binaire += String.fromCharCode.apply(null, octets.subarray(j, j + 8192)); }
    return btoa(binaire);
  }

  /* Le mélange des correspondants, en morceaux de 16 bits vers l'application ; et la
     relecture de la réunion, au niveau voulu, pendant que ses éléments sont muets. */
  function ouvrir() {
    if (ctx) { if (ctx.state !== "running") { ctx.resume().catch(function () {}); } return; }
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    melange = ctx.createGain();
    relecture = ctx.createGain();
    relecture.connect(ctx.destination);
    var traitement = ctx.createScriptProcessor(2048, 1, 1);
    var muet = ctx.createGain();
    muet.gain.value = 0;
    melange.connect(traitement);
    traitement.connect(muet);
    muet.connect(ctx.destination);
    traitement.onaudioprocess = function (e) {
      /* Rien tant qu'aucun flux reçu n'est branché : la salle comprend alors que la
         page ne donne pas son son. */
      if (!actif || !branches.length) { return; }
      envoyer("son", enMorceau(e.inputBuffer.getChannelData(0)), ctx.sampleRate);
    };
    ctx.resume().catch(function () {});
  }

  /* iOS ne règle pas le volume d'un élément : la réunion baissée, c'est l'élément
     muet et son flux rejoué au niveau voulu ; à 1 (ou à l'arrêt), tout est rendu. */
  function poserNiveau() {
    var baisser = actif && niveau < 1 && Boolean(ctx);
    if (relecture) { relecture.gain.value = niveau; }
    elements.forEach(function (x) {
      var source = ctx ? sourceDe(x.f) : null;
      try {
        if (baisser && source && !x.baisse) {
          x.muetAvant = x.el.muted;
          x.el.muted = true;
          source.connect(relecture);
          x.baisse = true;
        } else if (!baisser && x.baisse) {
          x.el.muted = x.muetAvant;
          if (source) { try { source.disconnect(relecture); } catch (e) { /* déjà débranché */ } }
          x.baisse = false;
        }
      } catch (e) { /* la page garde la main */ }
    });
  }

  /* ---------------------------------------------- la voix de l'interprète, envoyée */

  var parole = null;

  /** Les envois de son de la page — chacun porte le micro du client, ou rien (coupé). */
  function envoisAudio() {
    var liste = [];
    liaisons = liaisons.filter(function (pc) { try { return pc.signalingState !== "closed"; } catch (x) { return false; } });
    liaisons.forEach(function (pc) {
      try {
        pc.getSenders().forEach(function (e) { if (e.track && e.track.kind === "audio") { liste.push(e); } });
      } catch (x) { /* liaison fermée */ }
    });
    return liste;
  }

  /** Le micro de la page, au mélange envoyé (en fond) et en copie vers la salle. */
  function brancherClient(piste) {
    if (parole.origine === piste) { return; }
    if (parole.source) { try { parole.source.disconnect(); } catch (e) { /* déjà débranché */ } }
    parole.origine = piste;
    parole.source = null;
    try {
      parole.source = parole.ctx.createMediaStreamSource(new MediaStream([piste]));
      parole.source.connect(parole.gainClient);
      parole.source.connect(parole.traitement);
    } catch (e) { parole.source = null; }
  }

  function ouvrirParole(n) {
    if (!parole) {
      var c = new (window.AudioContext || window.webkitAudioContext)();
      var p = { ctx: c, curseur: 0, reserve: 0.4, envois: [], voix: 0, micro: 0, trous: 0, sautes: 0, silences: 0, ouvert: false };
      p.sortie = c.createMediaStreamDestination();
      p.piste = p.sortie.stream.getAudioTracks()[0];
      p.gainVoix = c.createGain();
      p.gainVoix.connect(p.sortie);
      p.gainClient = c.createGain();
      p.gainClient.connect(p.sortie);
      p.traitement = c.createScriptProcessor(4096, 1, 1);
      var muet = c.createGain();
      muet.gain.value = 0;
      p.traitement.connect(muet);
      muet.connect(c.destination);
      p.traitement.onaudioprocess = function (e) {
        // Le client coupé dans la réunion : l'interprète n'entend rien non plus.
        if (parole !== p || !p.ouvert || !p.source) { return; }
        envoyer("micro", enMorceau(e.inputBuffer.getChannelData(0)), c.sampleRate);
        p.micro++;
      };
      parole = p;
    }
    parole.niveau = typeof n === "number" && n >= 0 && n <= 1 ? n : 0.15;
    parole.ctx.resume().catch(function () {});
    suivreParole();
  }

  /** Chaque envoi de la page passe à la voix de l'interprète ; la page garde la main
      sur le micro : une piste qu'elle pose devient le nouveau micro, la coupure
      (piste désactivée) fait taire l'envoi. */
  function suivreParole() {
    if (!parole) { return; }
    envoisAudio().forEach(function (e) {
      var piste = e.track;
      if (piste === parole.piste) { return; }
      brancherClient(piste);
      var connu2 = parole.envois.filter(function (x) { return x.e === e; })[0];
      if (connu2) { connu2.origine = piste; } else { parole.envois.push({ e: e, origine: piste }); }
      e.replaceTrack(parole.piste).catch(function () { /* la page garde son micro */ });
    });
    var o = parole.origine;
    parole.ouvert = Boolean(o && o.readyState === "live" && o.enabled);
    parole.gainVoix.gain.value = parole.ouvert ? 1 : 0;
    parole.gainClient.gain.value = parole.ouvert ? parole.niveau : 0;
  }

  function fermerParole() {
    if (!parole) { return; }
    var p = parole;
    parole = null;
    p.envois.forEach(function (x) {
      try {
        if (x.e.track === p.piste) { x.e.replaceTrack(x.origine && x.origine.readyState === "live" ? x.origine : null).catch(function () {}); }
      } catch (e) { /* liaison fermée */ }
    });
    try { if (p.source) { p.source.disconnect(); } } catch (e) { /* déjà débranché */ }
    p.traitement.onaudioprocess = null;
    try { p.ctx.close(); } catch (e) { /* déjà fermé */ }
  }

  window.__rapporteurPrise = {
    /* oui : prendre le son des correspondants ; n : leur niveau dans la page
       pendant ce temps (la voix de l'interprète passe devant), 1 à l'arrêt. */
    capter: function (oui, n) {
      actif = Boolean(oui);
      niveau = typeof n === "number" && n >= 0 && n <= 1 ? n : 1;
      if (actif) { balayer(); ouvrir(); flux.forEach(brancher); }
      poserNiveau();
    },
    /* oui : les correspondants entendent l'interprète ; n : la voix du client
       derrière lui. Non : chaque envoi retrouve le micro de la page. */
    parler: function (oui, n) {
      if (oui) { ouvrirParole(n); } else { fermerParole(); }
    },
    /* Un morceau de la voix de l'interprète (16 bits, base 64), à envoyer. */
    voix: function (b64, taux) {
      var p = parole;
      if (!p || !p.ouvert) { return; }
      var o = atob(b64);
      var n = o.length >> 1;
      if (!n) { return; }
      var maintenant = p.ctx.currentTime;
      var tampon = p.ctx.createBuffer(1, n, taux);
      var canalVoix = tampon.getChannelData(0);
      var crete = 0;
      for (var i = 0; i < n; i++) {
        var v = o.charCodeAt(2 * i) | (o.charCodeAt(2 * i + 1) << 8);
        canalVoix[i] = (v > 32767 ? v - 65536 : v) / 32768;
        if (canalVoix[i] > crete) { crete = canalVoix[i]; } else if (-canalVoix[i] > crete) { crete = -canalVoix[i]; }
      }
      /* Une réserve, 400 ms au départ : les morceaux arrivent par à-coups (deux pages,
         l'application entre elles), la voix reste continue. Chaque trou l'allonge de
         200 ms, jusqu'à une seconde ; le retard se rattrape sur les SILENCES de
         l'interprète, jamais sur sa voix ; seule une rafale de plus de 3 s fait
         sauter un morceau (Felly, 17/10/2026). */
      var avance = p.curseur - maintenant;
      if (avance > p.reserve + 0.2 && crete < 0.01) { p.silences++; return; }
      if (avance > 3) { p.sautes++; return; }
      if (avance < 0.02) {
        if (p.voix > 0) { p.trous++; p.reserve = Math.min(1, p.reserve + 0.2); }
        p.curseur = maintenant + p.reserve;
      }
      var lecture = p.ctx.createBufferSource();
      lecture.buffer = tampon;
      lecture.connect(p.gainVoix);
      lecture.start(p.curseur);
      p.curseur += tampon.duration;
      p.voix++;
    },
    etat: function () {
      return JSON.stringify({ actif: actif, flux: flux.length, elements: elements.length, branches: branches.length, niveau: niveau,
        baisses: elements.filter(function (x) { return x.baisse; }).length, contexte: ctx ? ctx.state : null,
        parole: parole ? { ouvert: parole.ouvert, envois: envoisAudio().filter(function (e) { return e.track === parole.piste; }).length,
          voix: parole.voix, micro: parole.micro, trous: parole.trous, sautes: parole.sautes, silences: parole.silences,
          reserve: parole.reserve, niveau: parole.niveau } : null });
    },
  };

  setInterval(function () {
    if (!actif) { return; }
    balayer();
    flux.forEach(brancher);
    poserNiveau();
  }, 1000);
  setInterval(suivreParole, 500);
})();
