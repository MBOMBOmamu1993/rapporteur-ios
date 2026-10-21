// NODE_PATH=<dossier node_modules contenant playwright> node tests/essai-zoom.mjs
// Vraie circulation Web Audio ; Zoom et le fournisseur sont simulés, pas une réunion réelle.
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { chromium } = createRequire(import.meta.url)('playwright');
const prise = readFileSync(new URL('../Rapporteur/Ressources/prise-reunion.js', import.meta.url), 'utf8');
const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required', '--disable-background-timer-throttling', '--disable-renderer-backgrounding'] });
try {
  for (const host of ['app.zoom.us', 'teams.microsoft.com']) {
    const page = await browser.newPage();
    await page.route('https://' + host + '/**', r => r.fulfill({ contentType: 'text/html', body: '<!doctype html><title>Audio</title>' }));
    await page.goto('https://' + host + '/test');
    await page.evaluate(() => {
      window.sons = { micro: [], sortie: [], reunion: [] };
      window.webkit = { messageHandlers: { rapporteurReunion: { postMessage(e) { (e.type === 'micro' ? sons.micro : sons.reunion).push(e.b64); } } } };
      window.rapporteurReunion = {
        son(b) { sons.reunion.push(b); }, micro(b) { sons.micro.push(b); }
      };
      const md = typeof MediaDevices === 'undefined' ? Object.getPrototypeOf(navigator.mediaDevices) : MediaDevices.prototype;
      md.getUserMedia = async function () {
        const c = new AudioContext({ sampleRate: 48000 });
        const o = c.createOscillator(), g = c.createGain(), d = c.createMediaStreamDestination();
        o.frequency.value = 220; g.gain.value = .1;
        o.connect(g).connect(d); o.start(); await c.resume();
        window.original = d.stream.getAudioTracks()[0];
        window.fluxOriginal = d.stream;
        return d.stream;
      };
    });
    await page.addScriptTag({ content: prise });
    const identity = await page.evaluate(async () => {
      window.f = await navigator.mediaDevices.getUserMedia({ audio: true });
      window.p = f.getAudioTracks()[0];
      // Un clone est lu par la page. Le vieux crochet ne reconnaissait plus le micro.
      window.clone = p.clone();
      const c = new AudioContext({ sampleRate: 48000 });
      const s = c.createMediaStreamSource(new MediaStream([clone]));
      const proc = c.createScriptProcessor(2048, 1, 1), mute = c.createGain();
      mute.gain.value = 0;
      s.connect(proc).connect(mute).connect(c.destination);
      proc.onaudioprocess = e => sons.sortie.push(Array.from(e.inputBuffer.getChannelData(0)));
      await c.resume();
      return p === original;
    });
    if (host.startsWith('teams')) {
      assert.equal(identity, true, 'Teams garde sa piste originale');
      console.log('OK Teams : getUserMedia inchangé');
      await page.close();
      continue;
    }
    await page.evaluate(() => {
      __rapporteurPrise.parler(true, .15);
      const pcm = new Int16Array(4800);
      for (let i = 0; i < pcm.length; i++) pcm[i] = Math.sin(2 * Math.PI * 880 * i / 48000) * 6553;
      const b = btoa(String.fromCharCode(...new Uint8Array(pcm.buffer)));
      window.voixTimer = setInterval(() => __rapporteurPrise.voix(b, 48000), 100);
    });
    await page.waitForTimeout(4500);
    const measure = async () => page.evaluate(() => {
      function amplitude(frames, hz) {
        const values = frames.slice(-8).map(frame => {
          let re = 0, im = 0;
          for (let i = 0; i < frame.length; i++) {
            re += frame[i] * Math.cos(2 * Math.PI * hz * i / 48000);
            im += frame[i] * Math.sin(2 * Math.PI * hz * i / 48000);
          }
          return 2 * Math.hypot(re, im) / frame.length;
        });
        return values.reduce((a,b) => a+b, 0) / (values.length || 1);
      }
      function decode(b) {
        const s = atob(b), a = [];
        for (let i = 0; i < s.length; i += 2) { const n = s.charCodeAt(i) | s.charCodeAt(i+1) << 8; a.push((n > 32767 ? n-65536 : n) / 32768); }
        return a;
      }
      return { client: amplitude(sons.sortie, 220), voix: amplitude(sons.sortie, 880),
        micro: amplitude(sons.micro.map(decode), 220), retour: amplitude(sons.micro.map(decode), 880),
        etat: JSON.parse(__rapporteurPrise.etat()) };
    });
    let m = await measure();
    console.log('Zoom actif', JSON.stringify(m));
    assert.ok(m.voix > .15, 'la traduction atteint le clone lu par Zoom');
    assert.ok(m.client > .009 && m.client < .025, 'la voix originale reste à 15 %');
    assert.ok(m.micro > .08 && m.retour < .005, "l'interprète entend seulement le micro brut");
    await page.evaluate(() => { clone.enabled = false; });
    await page.waitForTimeout(1800);
    m = await measure();
    assert.ok(m.voix < .002 && m.client < .002, 'micro Zoom coupé : aucun envoi');
    await page.evaluate(() => { clone.enabled = true; clearInterval(voixTimer); __rapporteurPrise.parler(false); });
    await page.waitForTimeout(1800);
    m = await measure();
    assert.ok(m.client > .08 && m.voix < .005, "à l'arrêt le micro retrouve son volume");
    await page.evaluate(() => { p.stop(); });
    await page.waitForTimeout(300);
    assert.equal(await page.evaluate(() => original.readyState), 'live', 'un clone actif conserve la source');
    await page.evaluate(() => { clone.stop(); });
    await page.waitForTimeout(300);
    assert.equal(await page.evaluate(() => original.readyState), 'ended', 'le dernier arrêt libère le micro');
    console.log('OK Zoom : traduction, copie brute, mute, arrêt et clones');
    await page.close();
  }
} finally { await browser.close(); }
