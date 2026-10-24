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
 *
 * Zoom (20/10/2026, essai de Felly sur une vraie réunion : l'interprète « actif »,
 * sans voix ni sous-titres — la prise n'avait trouvé AUCUN son) : la version web de
 * Zoom ne joue pas les correspondants par des flux WebRTC ; elle décode elle-même
 * leur son et le joue par Web Audio, et lit le micro par Web Audio pour l'encoder
 * elle-même. Sur ses pages seulement, la prise écoute donc la SORTIE Web Audio de la
 * page (ce qui va vers le haut-parleur passe par un gain à elle, dont elle garde une
 * copie) et fait passer le micro du client, là où la page le branche, par un mélange
 * à elle : tel quel d'ordinaire, la voix de l'interprète devant quand la salle le
 * demande. Les pages de Teams, de Meet et des autres services ne sont pas touchées.
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

  /* ------------------------------------------------ Zoom : le son par Web Audio */

  var ZOOM = domaine("zoom.us");
  var nosContextes = [];   /* les contextes de la prise : jamais écoutés ni détournés */
  var taps = [];           /* { c, entree, baisse, copie } : la sortie d'un contexte de la page */
  var micros = [];         /* les pistes de micro que la page a demandées */
  var melanges = [];       /* { c, source, client, voix, sortie, cibles, lie, entreeVoix } : le micro tel que la page le branche */
  var lecteurs = [];       /* { origine, ctx, client, voix, piste, entreeVoix } : le micro tel que la page le lit trame par trame */
  var connecter = AudioNode.prototype.connect;
  var deconnecter = AudioNode.prototype.disconnect;

  function estANous(c) { return nosContextes.indexOf(c) >= 0; }
  function estDestination(n) { return typeof AudioDestinationNode !== "undefined" && n instanceof AudioDestinationNode; }

  /** La sortie d'un contexte de la page : entrée (copie gardée) → baisse (le niveau de la réunion) → haut-parleur. */
  function tapDe(c, creer) {
    for (var i = 0; i < taps.length; i++) { if (taps[i].c === c) { return taps[i]; } }
    if (!creer || typeof c.createMediaStreamDestination !== "function") { return null; }
    try {
      var t = { c: c, entree: c.createGain(), baisse: c.createGain(), copie: c.createMediaStreamDestination() };
      t.baisse.gain.value = actif && niveau < 1 ? niveau : 1;
      connecter.call(t.entree, t.baisse);
      connecter.call(t.baisse, c.destination);
      connecter.call(t.entree, t.copie);
      taps.push(t);
      // Les correspondants de Zoom : un flux comme ceux de Teams, que l'interprète écoute.
      noter(t.copie.stream, null);
      return t;
    } catch (e) { return null; }
  }

  function estMicroDeLaPage(n) {
    try {
      if (typeof MediaStreamAudioSourceNode === "undefined" || !(n instanceof MediaStreamAudioSourceNode) || !n.mediaStream) { return false; }
      return n.mediaStream.getAudioTracks().some(function (p) { return micros.indexOf(p) >= 0; });
    } catch (e) { return false; }
  }

  function melangeDe(source, creer) {
    for (var i = 0; i < melanges.length; i++) { if (melanges[i].source === source) { return melanges[i]; } }
    if (!creer) { return null; }
    var c = source.context;
    var m = { c: c, source: source, client: c.createGain(), voix: c.createGain(), sortie: c.createGain(), cibles: [], lie: false, entreeVoix: null };
    m.voix.gain.value = 0;
    connecter.call(m.client, m.sortie);
    connecter.call(m.voix, m.sortie);
    melanges.push(m);
    poserParole();
    return m;
  }

  /** Le micro lu trame par trame (MediaStreamTrackProcessor) : la page lit à sa place la piste
      d'un mélange à la prise — le micro tel quel, la voix de l'interprète devant quand il parle. */
  function lecteurDe(p) {
    for (var i = 0; i < lecteurs.length; i++) { if (lecteurs[i].origine === p) { return lecteurs[i]; } }
    var c = new (window.AudioContext || window.webkitAudioContext)();
    nosContextes.push(c);
    var sortie = c.createMediaStreamDestination();
    var l = { origine: p, ctx: c, client: c.createGain(), voix: c.createGain(), piste: sortie.stream.getAudioTracks()[0], entreeVoix: null, pistes: [] };
    l.voix.gain.value = 0;
    c.createMediaStreamSource(new MediaStream([p])).connect(l.client);
    l.client.connect(sortie);
    l.voix.connect(sortie);
    c.resume().catch(function () {});
    lecteurs.push(l);
    poserParole();
    return l;
  }

  /* Zoom peut cloner ou transférer son micro à un worker : aucun crochet sur
     AudioNode.connect ou window.MediaStreamTrackProcessor ne voit alors sa lecture.
     On lui remet le mélange DÈS getUserMedia. Sa copie vers l'interprète reste la
     piste brute, conservée dans micros. Aucun changement pour Teams/Meet.
     Les clones gardent le mélange, et le dernier stop libère le vrai micro. */
  function pistePourZoom(l, p) {
    l.pistes.push(p);
    var stop = p.stop.bind(p), clone = p.clone.bind(p);
    p.stop = function () {
      stop();
      if (!l.pistes.some(function (x) { return x.readyState === "live"; })) {
        l.origine.stop();
        l.ctx.close().catch(function () {});
      }
    };
    p.clone = function () { return pistePourZoom(l, clone()); };
    // La page doit toujours retrouver le périphérique choisi et pouvoir le régler.
    ["getSettings", "getConstraints", "getCapabilities", "applyConstraints"].forEach(function (nom) {
      if (typeof l.origine[nom] === "function") { p[nom] = l.origine[nom].bind(l.origine); }
    });
    return p;
  }

  /** La voix de l'interprète dans chaque mélange de Zoom (règle 7), ou le micro tel quel. */
  function poserParole() {
    var parle = Boolean(parole && parole.ouvert);
    lecteurs.forEach(function (l) {
      if (parole && parole.sortieVoix && !l.entreeVoix) {
        try { l.entreeVoix = l.ctx.createMediaStreamSource(parole.sortieVoix.stream); l.entreeVoix.connect(l.voix); } catch (e) { l.entreeVoix = null; }
      }
      if (!parole && l.entreeVoix) {
        try { l.entreeVoix.disconnect(); } catch (e) { /* déjà débranchée */ }
        l.entreeVoix = null;
      }
      l.voix.gain.value = parle ? 1 : 0;
      l.client.gain.value = parle ? parole.niveau : 1;
      if (l.ctx.state !== "running") { l.ctx.resume().catch(function () {}); }
    });
    melanges.forEach(function (m) {
      if (parole && parole.sortieVoix && !m.entreeVoix) {
        try { m.entreeVoix = m.c.createMediaStreamSource(parole.sortieVoix.stream); connecter.call(m.entreeVoix, m.voix); } catch (e) { m.entreeVoix = null; }
      }
      if (!parole && m.entreeVoix) {
        try { deconnecter.call(m.entreeVoix); } catch (e) { /* déjà débranchée */ }
        m.entreeVoix = null;
      }
      m.voix.gain.value = parle ? 1 : 0;
      m.client.gain.value = parle ? parole.niveau : 1;
    });
  }

  function dernierMicroVivant() {
    micros = micros.filter(function (p) { return p.readyState !== "ended"; });
    return micros.length ? micros[micros.length - 1] : null;
  }

  if (ZOOM && typeof connecter === "function" && typeof deconnecter === "function") {
    /* Les micros que la page demande : la prise les reconnaîtra là où elle les branche. Sur le
       prototype : une page peut appeler la méthode de MediaDevices directement. */
    var md = typeof MediaDevices !== "undefined" ? MediaDevices.prototype : navigator.mediaDevices;
    if (md && typeof md.getUserMedia === "function") {
      var demander = md.getUserMedia;
      md.getUserMedia = function () {
        return demander.apply(this, arguments).then(function (f) {
          f.getAudioTracks().forEach(function (p) {
            if (micros.indexOf(p) < 0) { micros.push(p); }
            try {
              var l = lecteurDe(p);
              var mixte = pistePourZoom(l, l.piste);
              f.removeTrack(p);
              f.addTrack(mixte);
              p.addEventListener("ended", function () {
                l.pistes.forEach(function (x) { x.stop(); });
              });
            } catch (e) { /* Si le mélange est indisponible, la réunion garde son micro. */ }
          });
          return f;
        });
      };
    }
    // MediaStream.clone natif ne passe pas par la méthode clone de chaque piste.
    var clonerFlux = MediaStream.prototype.clone;
    MediaStream.prototype.clone = function () {
      var pistes = this.getTracks();
      var notreMicro = pistes.some(function (p) {
        return lecteurs.some(function (l) { return l.pistes.indexOf(p) >= 0; });
      });
      return notreMicro ? new MediaStream(pistes.map(function (p) { return p.clone(); })) : clonerFlux.call(this);
    };
    /* Zoom peut aussi lire le micro trame par trame (MediaStreamTrackProcessor) : il lit alors la
       piste d'un mélange à la prise (lecteurDe). La page garde, elle, sa vraie piste. */
    if (typeof window.MediaStreamTrackProcessor === "function") {
      var Processeur = window.MediaStreamTrackProcessor;
      var Detourne = function (options) {
        try {
          var p = options && options.track;
          if (p && p.kind === "audio" && micros.indexOf(p) >= 0) {
            var copie = {};
            for (var cle in options) { copie[cle] = options[cle]; }
            copie.track = lecteurDe(p).piste;
            return new Processeur(copie);
          }
        } catch (e) { /* la page garde sa piste */ }
        return new Processeur(options);
      };
      Detourne.prototype = Processeur.prototype;
      window.MediaStreamTrackProcessor = Detourne;
    }
    AudioNode.prototype.connect = function (cible) {
      try {
        if (cible && !estANous(this.context)) {
          var a = Array.prototype.slice.call(arguments);
          if (estDestination(cible)) {
            var t = tapDe(this.context, true);
            if (t) { a[0] = t.entree; connecter.apply(this, a); return cible; }
          } else if (cible instanceof AudioNode && estMicroDeLaPage(this)) {
            var m = melangeDe(this, true);
            if (!m.lie) { connecter.call(this, m.client); m.lie = true; }
            connecter.call(m.sortie, cible, 0, a.length > 2 ? a[2] : 0);
            if (m.cibles.indexOf(cible) < 0) { m.cibles.push(cible); }
            return cible;
          }
        }
      } catch (e) { /* la page garde la main */ }
      return connecter.apply(this, arguments);
    };
    AudioNode.prototype.disconnect = function (cible) {
      try {
        if (!estANous(this.context)) {
          var m = melangeDe(this, false);
          if (arguments.length && cible instanceof AudioNode) {
            if (estDestination(cible)) {
              var t = tapDe(this.context, false);
              if (t) { var a = Array.prototype.slice.call(arguments); a[0] = t.entree; return deconnecter.apply(this, a); }
            } else if (m && m.cibles.indexOf(cible) >= 0) {
              m.cibles.splice(m.cibles.indexOf(cible), 1);
              return deconnecter.call(m.sortie, cible);
            }
          } else if (m) {
            // Tout débranché : le mélange aussi ; il se rebranchera au prochain branchement de la page.
            m.cibles = [];
            m.lie = false;
            try { deconnecter.call(m.sortie); } catch (e) { /* rien de branché */ }
          }
        }
      } catch (e) { /* la page garde la main */ }
      return deconnecter.apply(this, arguments);
    };
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
    nosContextes.push(ctx);
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
    // Zoom : ce que la page joue par Web Audio baisse par le gain de sa sortie ; la copie, elle, reste entière.
    taps.forEach(function (t) { try { t.baisse.gain.value = baisser ? niveau : 1; } catch (e) { /* contexte fermé */ } });
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

  /* La réserve de lecture de la voix (24/10/2026, Felly : « le retard de l'interprète de mes
     interlocuteurs est criant, il doit être instantané ») : 150 ms au départ — 400 jusqu'à la
     version précédente —, et seulement ce que les à-coups réclament. À chaque trou (réserve vide
     pendant la voix), elle grandit de 100 ms, ou jusqu'au retard constaté plus une garde de 50 ms,
     800 ms au plus ; après 15 s sans trou, elle redescend d'au plus 100 ms vers le plus grand
     retard vu dans la fenêtre (plus la garde), jamais sous 150 ms. Un silence de plus de 1,5 s
     n'est pas un trou : c'est la salle qui s'est tue, la réserve n'en grandit pas. Le retard se
     rattrape sur les SILENCES de l'interprète, jamais sur sa voix : un morceau muet est sauté dès
     que l'avance dépasse la réserve de 60 ms ; seule une rafale de plus de 3 s fait sauter un
     morceau de voix. */
  var RESERVE_DEPART = 0.15, RESERVE_PAS = 0.1, RESERVE_MAX = 0.8, RESERVE_GARDE = 0.05, RESERVE_MARGE = 0.06;
  var FENETRE_CALME_S = 15, PAUSE_S = 1.5;

  /** L'état de la prise (des comptes, jamais un mot) remis à la salle pour son relevé : à 2 s,
      puis toutes les 10 s pendant que l'interprète parle dans la réunion, et à l'arrêt. */
  function rapporter() {
    var p = parole;
    if (!p || !p.ouvert) { return; }
    try { envoyer("etat", btoa(window.__rapporteurPrise.etat()), p.ctx.sampleRate); p.rapports++; } catch (e) { /* l'application est partie */ }
  }

  function ouvrirParole(n) {
    if (!parole) {
      var c = new (window.AudioContext || window.webkitAudioContext)();
      nosContextes.push(c);
      var p = { ctx: c, curseur: 0, reserve: RESERVE_DEPART, reserveMax: RESERVE_DEPART, attendu: 0, retardMax: 0, creux: 0, calmeDepuis: 0,
        baisses: 0, pauses: 0, rapports: 0, tics: 0, envois: [], voix: 0, micro: 0, trous: 0, sautes: 0, silences: 0, ouvert: false };
      p.sortie = c.createMediaStreamDestination();
      p.piste = p.sortie.stream.getAudioTracks()[0];
      p.gainVoix = c.createGain();
      p.gainVoix.connect(p.sortie);
      // Zoom : la voix seule, que chaque mélange de la page reçoit (poserParole).
      p.sortieVoix = c.createMediaStreamDestination();
      p.gainVoix.connect(p.sortieVoix);
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
    /* Zoom : le micro que la page a demandé, et sa voix dans les mélanges de la page — pas
       d'envoi à remplacer. Sans mélange (Zoom qui enverrait par une liaison), comme Teams. */
    var parMelange = ZOOM && (melanges.length > 0 || lecteurs.length > 0);
    if (ZOOM) {
      var micro = dernierMicroVivant();
      if (micro) { brancherClient(micro); }
    }
    if (!parMelange) {
      envoisAudio().forEach(function (e) {
        var piste = e.track;
        if (piste === parole.piste) { return; }
        brancherClient(piste);
        var connu2 = parole.envois.filter(function (x) { return x.e === e; })[0];
        if (connu2) { connu2.origine = piste; } else { parole.envois.push({ e: e, origine: piste }); }
        e.replaceTrack(parole.piste).catch(function () { /* la page garde son micro */ });
      });
    }
    var o = parole.origine;
    var lecture = lecteurs.filter(function (l) { return l.origine === o; })[0];
    var pageOuverte = !lecture || lecture.pistes.some(function (p) { return p.readyState === "live" && p.enabled; });
    parole.ouvert = Boolean(o && o.readyState === "live" && o.enabled && pageOuverte);
    parole.gainVoix.gain.value = parole.ouvert ? 1 : 0;
    parole.gainClient.gain.value = parole.ouvert ? parole.niveau : 0;
    if (ZOOM) { poserParole(); }
  }

  function fermerParole() {
    if (!parole) { return; }
    rapporter();
    var p = parole;
    parole = null;
    // Zoom : chaque mélange redonne le micro tel quel, avant que la voix ne s'éteigne.
    poserParole();
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
      /* La réserve (RESERVE_DEPART et suivantes) : les morceaux arrivent par à-coups (deux pages,
         l'application entre elles), la voix reste continue (Felly, 17/10/2026 : « elle sort
         entrecoupée, haletante », « au démarrage il y avait ces à-coups »). */
      var avance = p.curseur - maintenant;
      // Le retard de ce morceau sur l'heure où il était attendu : le précédent, plus sa durée.
      var retard = p.attendu ? Math.max(0, maintenant - p.attendu) : 0;
      p.attendu = maintenant + tampon.duration;
      if (avance > p.reserve + RESERVE_MARGE && crete < 0.01) { p.silences++; return; }
      if (avance > 3) { p.sautes++; return; }
      if (avance < 0.02) {
        if (p.voix > 0 && retard >= PAUSE_S) {
          // La salle s'était tue : pas un trou, la réserve reste.
          p.pauses++;
        } else if (p.voix > 0) {
          // Réserve vide pendant la voix : un trou (le premier morceau n'en est pas un) — elle grandit.
          p.trous++;
          p.reserve = Math.min(RESERVE_MAX, Math.max(p.reserve + RESERVE_PAS, retard + RESERVE_GARDE));
          if (p.reserve > p.reserveMax) { p.reserveMax = p.reserve; }
        }
        p.curseur = maintenant + p.reserve;
        p.retardMax = 0;
        p.creux = p.reserve;
        p.calmeDepuis = maintenant;
      } else {
        if (retard > p.retardMax) { p.retardMax = retard; }
        if (avance < p.creux) { p.creux = avance; }
        // Quinze secondes sans trou : la réserve redescend vers ce que les à-coups ont réclamé.
        if (maintenant - p.calmeDepuis >= FENETRE_CALME_S) {
          var voulue = Math.max(RESERVE_DEPART, p.retardMax + RESERVE_GARDE);
          if (voulue < p.reserve) { p.reserve = Math.max(voulue, p.reserve - RESERVE_PAS); p.baisses++; }
          p.retardMax = 0;
          p.creux = avance;
          p.calmeDepuis = maintenant;
        }
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
          reserve: Math.round(parole.reserve * 1000) / 1000, reserveMax: Math.round(parole.reserveMax * 1000) / 1000,
          baisses: parole.baisses, pauses: parole.pauses, rapports: parole.rapports,
          retardMax: Math.round(parole.retardMax * 1000) / 1000, creux: Math.round(parole.creux * 1000) / 1000,
          niveau: parole.niveau, contexte: parole.ctx.state, avance: Math.round((parole.curseur - parole.ctx.currentTime) * 1000) / 1000 } : null,
        // Zoom : les sorties Web Audio écoutées, les micros demandés, les mélanges où l'interprète parle.
        zoom: ZOOM ? { taps: taps.length, micros: micros.length, melanges: melanges.length, lecteurs: lecteurs.length,
          lies: melanges.filter(function (m) { return m.lie && m.cibles.length; }).length,
          voix: melanges.filter(function (m) { return Boolean(m.entreeVoix); }).length,
          cibles: melanges.map(function (m) { return m.cibles.map(function (c) { return (c.constructor && c.constructor.name) || "?"; }).join("+"); }).join(","),
          baisse: taps.length ? taps[0].baisse.gain.value : null } : null });
    },
  };

  setInterval(function () {
    if (!actif) { return; }
    balayer();
    flux.forEach(brancher);
    poserNiveau();
  }, 1000);
  setInterval(function () {
    suivreParole();
    // Le relevé de la prise pour la salle : à 2 s, puis toutes les 10 s, tant que l'interprète y parle.
    if (parole && parole.ouvert) { parole.tics++; if (parole.tics === 4 || parole.tics % 20 === 0) { rapporter(); } }
  }, 500);
})();
