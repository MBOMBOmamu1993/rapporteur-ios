// NODE_PATH=<dossier node_modules contenant playwright> node tests/essai-reserve.mjs
// La réserve de lecture de la voix de l'interprète dans la réunion (règle 7, prise-reunion.js) :
// vraie circulation Web Audio dans Chromium ; la salle, l'application et la page de réunion
// (Teams) sont simulées — des morceaux de 2048 échantillons à 48 kHz poussés à la cadence réelle,
// puis retenus (à-coup de la page), tus (la salle se tait) ou muets (silence de l'interprète).
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = createRequire(import.meta.url)('playwright');
const prise = readFileSync(new URL('../Rapporteur/Ressources/prise-reunion.js', import.meta.url), 'utf8');
const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required', '--disable-background-timer-throttling', '--disable-renderer-backgrounding'] });
try {
  const page = await browser.newPage();
  await page.route('https://teams.microsoft.com/**', r => r.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Audio</title>' }));
  await page.goto('https://teams.microsoft.com/test');
  await page.evaluate(() => {
    window.etats = []; window.micros = 0;
    // Le pont de l'application iPhone : son, micro, et l'état de la prise (1.1.18).
    window.webkit = { messageHandlers: { rapporteurReunion: { postMessage(e) {
      if (e.type === 'micro') { micros++; }
      if (e.type === 'etat') { etats.push({ taux: e.taux, etat: JSON.parse(atob(e.b64)) }); }
    } } } };
  });
  await page.addScriptTag({ content: prise });
  await page.evaluate(async () => {
    // La page de réunion : un micro (220 Hz) envoyé par une liaison bouclée ; ce que reçoit l'autre
    // bout, c'est ce qu'entendraient les correspondants.
    const c = new AudioContext({ sampleRate: 48000 });
    const o = c.createOscillator(), g = c.createGain(), d = c.createMediaStreamDestination();
    o.frequency.value = 220; g.gain.value = 0.1; o.connect(g).connect(d); o.start(); await c.resume();
    window.micro = d.stream.getAudioTracks()[0];
    const pc1 = new RTCPeerConnection(), pc2 = new RTCPeerConnection();
    pc1.onicecandidate = e => { if (e.candidate) pc2.addIceCandidate(e.candidate); };
    pc2.onicecandidate = e => { if (e.candidate) pc1.addIceCandidate(e.candidate); };
    pc1.addTrack(micro, d.stream);
    const recu = new Promise(fin => { pc2.ontrack = e => fin(e.streams[0] || new MediaStream([e.track])); });
    const offre = await pc1.createOffer(); await pc1.setLocalDescription(offre); await pc2.setRemoteDescription(offre);
    const reponse = await pc2.createAnswer(); await pc2.setLocalDescription(reponse); await pc1.setRemoteDescription(reponse);
    const flux = await recu;
    const audio = new Audio(); audio.muted = true; audio.srcObject = flux; audio.play().catch(() => {});
    const mesure = new AudioContext({ sampleRate: 48000 });
    const proc = mesure.createScriptProcessor(2048, 1, 1), muet = mesure.createGain(); muet.gain.value = 0;
    mesure.createMediaStreamSource(flux).connect(proc); proc.connect(muet).connect(mesure.destination);
    window.recus = [];
    proc.onaudioprocess = e => { recus.push(Array.from(e.inputBuffer.getChannelData(0))); if (recus.length > 300) recus.shift(); };
    await mesure.resume();
    window.pc1 = pc1;
    // La salle : des morceaux de 2048 échantillons à 48 kHz — voix (880 Hz) ou silence —, à la cadence réelle.
    let phase = 0;
    window.morceau = voix => {
      const pcm = new Int16Array(2048);
      for (let i = 0; i < 2048; i++) { pcm[i] = voix ? Math.sin(phase) * 9830 : 0; phase += 2 * Math.PI * 880 / 48000; }
      return btoa(String.fromCharCode(...new Uint8Array(pcm.buffer)));
    };
    // L'horloge de la salle : celle de l'audio (sans carte son, Chromium rend le son à son propre rythme,
    // pas celui de la pendule) — un morceau toutes les 42,67 ms de son rendu.
    const horlogeCtx = new AudioContext({ sampleRate: 48000 }); await horlogeCtx.resume();
    window.horloge = () => horlogeCtx.currentTime * 1000;
    window.salle = { marche: false, voix: true, retenus: [], retientJusqua: 0, taitJusqua: 0, envoyes: 0, suivant: 0 };
    function tic() {
      const maintenant = horloge();
      if (salle.marche) {
        while (salle.suivant <= maintenant) {
          salle.suivant += 2048000 / 48000;
          if (maintenant < salle.taitJusqua) { continue; }           // la salle se tait : rien ne part
          const b = morceau(salle.voix);
          if (maintenant < salle.retientJusqua) { salle.retenus.push(b); continue; }   // la page est occupée : retenu
          if (salle.retenus.length) { salle.retenus.forEach(x => __rapporteurPrise.voix(x, 48000)); salle.retenus = []; }
          __rapporteurPrise.voix(b, 48000); salle.envoyes++;
        }
      }
      setTimeout(tic, 5);
    }
    tic();
    window.demarrer = () => { salle.suivant = horloge(); salle.marche = true; };
    window.retenir = ms => { salle.retientJusqua = horloge() + ms; };
    window.taire = ms => { salle.taitJusqua = horloge() + ms; };
    window.parole = () => JSON.parse(__rapporteurPrise.etat()).parole;
    window.amplitude = hz => {
      const trames = recus.slice(-8);
      const v = trames.map(frame => {
        let re = 0, im = 0;
        for (let i = 0; i < frame.length; i++) { re += frame[i] * Math.cos(2 * Math.PI * hz * i / 48000); im += frame[i] * Math.sin(2 * Math.PI * hz * i / 48000); }
        return 2 * Math.hypot(re, im) / frame.length;
      });
      return v.reduce((a, b) => a + b, 0) / (v.length || 1);
    };
  });

  // 1. L'interprète prend la parole : l'envoi de la page passe à la prise, puis la voix coule.
  await page.evaluate(() => __rapporteurPrise.parler(true, 0.15));
  await page.waitForFunction(() => parole() && parole().ouvert, null, { timeout: 5000 });
  await page.evaluate(() => demarrer());
  await page.waitForTimeout(4000);
  let p = await page.evaluate(() => parole());
  console.log('cadence réelle', JSON.stringify(p));
  assert.equal(p.trous, 0, 'aucun trou à la cadence réelle');
  assert.equal(p.reserve, 0.15, 'la réserve reste à 150 ms');
  // Sans carte son, le contexte de la prise part avec un retard de démarrage (jusqu'à 0,2 s) qui reste dans
  // l'avance : on vérifie qu'elle est bornée, pas sa valeur exacte.
  assert.ok(p.avance > 0.08 && p.avance < 0.6, "l'avance de lecture est bornée : " + p.avance);
  const voix = await page.evaluate(() => amplitude(880)), client = await page.evaluate(() => amplitude(220));
  assert.ok(voix > 0.15, 'les correspondants entendent la voix : ' + voix);
  assert.ok(client > 0.009 && client < 0.025, 'la voix du client reste à 15 % : ' + client);

  // 2. Un à-coup de la page qui vide la réserve (son avance, plus 150 ms) : un trou, et la réserve
  //    grandit — du retard constaté, pas plus.
  const niveau = await page.evaluate(() => parole().avance);
  const acoup = Math.round((niveau + 0.15) * 1000);
  await page.evaluate(ms => retenir(ms), acoup);
  await page.waitForTimeout(1500);
  p = await page.evaluate(() => parole());
  console.log('après un à-coup de ' + acoup + ' ms', JSON.stringify(p));
  assert.equal(p.trous, 1, 'un trou');
  assert.ok(p.reserve >= 0.25 && p.reserve <= niveau + 0.3, 'réserve agrandie du retard constaté : ' + p.reserve);
  assert.equal(p.reserveMax, p.reserve);

  // 3. Les silences de l'interprète rattrapent l'avance en trop (jamais sa voix).
  await page.evaluate(() => { salle.voix = false; });
  await page.waitForTimeout(1500);
  await page.evaluate(() => { salle.voix = true; });
  p = await page.evaluate(() => parole());
  console.log('après 1,5 s de silence', JSON.stringify(p));
  assert.ok(p.silences >= 3, 'des morceaux muets sautés : ' + p.silences);
  assert.ok(p.avance < p.reserve + 0.1, "l'avance est revenue à la réserve : " + p.avance);
  assert.equal(p.sautes, 0, 'aucun morceau de voix sauté');

  // 4. Quinze secondes sans trou : la réserve redescend d'un cran ; trois fenêtres plus tard, près de 150 ms.
  await page.waitForTimeout(16000);
  p = await page.evaluate(() => parole());
  console.log('après 16 s de calme', JSON.stringify(p));
  assert.ok(p.baisses >= 1, 'la réserve a baissé : ' + p.baisses);
  assert.ok(p.reserve < p.reserveMax, 'réserve sous son maximum : ' + p.reserve);
  await page.waitForTimeout(32000);
  p = await page.evaluate(() => parole());
  console.log('après 48 s de calme', JSON.stringify(p));
  // Sans carte son, Chromium rend le son par à-coups de quelques dizaines de ms : la réserve se cale sur
  // ce retard-là (plus la garde), jamais plus bas que 150 ms.
  assert.ok(p.reserve < 0.2 && p.baisses >= 3, 'redescendue près de 150 ms : ' + p.reserve);
  assert.equal(p.trous, 1, 'toujours un seul trou');
  const avantPause = p.reserve;

  // 5. La salle se tait deux secondes (voix tue, fin de phrase) : une pause, pas un trou.
  await page.evaluate(() => taire(2000));
  await page.waitForTimeout(3000);
  p = await page.evaluate(() => parole());
  console.log('après 2 s de pause', JSON.stringify(p));
  assert.equal(p.pauses, 1, 'une pause comptée');
  assert.equal(p.trous, 1, 'pas un trou de plus');
  assert.equal(p.reserve, avantPause, 'la réserve ne grandit pas');

  // 6. L'état remis à la salle : à 2 s puis toutes les 10 s, des comptes seulement.
  const etats = await page.evaluate(() => etats);
  assert.ok(etats.length >= 3, "des relevés sont remis : " + etats.length);
  const dernier = etats[etats.length - 1];
  // Le taux est celui du contexte de la prise : 48 kHz ici, 44,1 kHz sur d'autres hôtes (GitHub Actions).
  assert.ok(dernier.taux >= 8000 && dernier.taux <= 96000, 'le relevé porte le taux du contexte : ' + dernier.taux);
  for (const champ of ['reserve', 'reserveMax', 'trous', 'silences', 'sautes', 'pauses', 'baisses', 'avance', 'creux', 'retardMax']) {
    assert.ok(champ in dernier.etat.parole, 'le relevé porte ' + champ);
  }
  assert.ok(JSON.stringify(dernier.etat).length < 4096, 'relevé borné');
  assert.ok((await page.evaluate(() => micros)) > 20, 'le micro du client est remis à la salle');

  // 7. À l'arrêt, la page retrouve son micro.
  await page.evaluate(() => { salle.marche = false; __rapporteurPrise.parler(false); });
  await page.waitForTimeout(500);
  assert.equal(await page.evaluate(() => pc1.getSenders()[0].track === micro), true, "l'envoi retrouve le micro de la page");
  console.log('OK réserve : cadence, à-coup, silences, calme, pause, relevés, arrêt');
  await page.close();
} finally { await browser.close(); }
