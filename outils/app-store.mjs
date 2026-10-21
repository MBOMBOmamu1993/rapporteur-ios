// Opérations App Store Connect limitées à Rapporteur. Aucun secret n'est journalisé.
import { sign } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export const APP = '6809614915';
export function clientApple(env = process.env, transport = fetch) {
  for (const nom of ['ASC_CLE_ID', 'ASC_EMETTEUR_ID', 'ASC_CLE_P8']) {
    if (!env[nom]) throw new Error(`Configuration manquante : ${nom}`);
  }
  return async function api(chemin, method = 'GET', data) {
    if (!chemin.startsWith('/v1/')) throw new Error('Chemin Apple invalide');
    const now = Math.floor(Date.now() / 1000);
    const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
    const message = `${b64({ alg: 'ES256', kid: env.ASC_CLE_ID, typ: 'JWT' })}.${b64({ iss: env.ASC_EMETTEUR_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
    const signature = sign('sha256', Buffer.from(message), { key: env.ASC_CLE_P8, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    const r = await transport('https://api.appstoreconnect.apple.com' + chemin, {
      method, headers: { Authorization: `Bearer ${message}.${signature}`, 'Content-Type': 'application/json' },
      ...(data !== undefined ? { body: JSON.stringify({ data }) } : {}), signal: AbortSignal.timeout(45000),
    });
    const corps = r.status === 204 ? {} : await r.json();
    if (!r.ok) throw new Error(`Apple ${method} ${chemin}: ${r.status} ${JSON.stringify(corps.errors?.map(e => ({ code: e.code, title: e.title, detail: e.detail })))}`);
    return corps;
  };
}

export async function etat(api) {
  const app = (await api(`/v1/apps/${APP}?fields[apps]=name,bundleId`)).data;
  if (app.attributes.bundleId !== 'com.lerapporteur.mobile') throw new Error('Application inattendue');
  const versions = await api(`/v1/apps/${APP}/appStoreVersions?filter[platform]=IOS&include=build&limit=50`);
  const builds = await api(`/v1/builds?filter[app]=${APP}&filter[version]=21&include=preReleaseVersion&limit=50`);
  const examens = await api(`/v1/apps/${APP}/reviewSubmissions?include=items&limit=50`);
  const details = [];
  for (const s of examens.data.filter(s => ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'READY_FOR_REVIEW', 'UNRESOLVED_ISSUES'].includes(s.attributes.state))) {
    const items = await api(`/v1/reviewSubmissions/${s.id}/items?include=appStoreVersion&limit=50`);
    details.push({ examen: s.id, items });
  }
  return { app, versions, builds, examens, details };
}

export function resume(e) {
  return {
    app: { id: e.app.id, bundle: e.app.attributes.bundleId },
    versions: e.versions.data.map(v => ({ id: v.id, version: v.attributes.versionString, etat: v.attributes.appStoreState, build: v.relationships.build?.data?.id })),
    builds: e.builds.data.map(b => ({ id: b.id, numero: b.attributes.version, traitement: b.attributes.processingState, expire: b.attributes.expired, chiffrementNonExempte: b.attributes.usesNonExemptEncryption, preRelease: b.relationships.preReleaseVersion?.data?.id })),
    prereleases: e.builds.included?.filter(x => x.type === 'preReleaseVersions').map(x => ({ id: x.id, ...x.attributes })),
    examens: e.examens.data.map(s => ({ id: s.id, etat: s.attributes.state, plateforme: s.attributes.platform, items: s.relationships.items?.data })),
    items: e.details.map(d => ({ examen: d.examen, items: d.items.data.map(x => ({ id: x.id, etat: x.attributes.state, version: x.relationships?.appStoreVersion?.data?.id })) })),
  };
}

const MODIFIABLE = ['DEVELOPER_REJECTED', 'PREPARE_FOR_SUBMISSION', 'REJECTED', 'METADATA_REJECTED', 'READY_FOR_REVIEW'];
const EN_EXAMEN = ['WAITING_FOR_REVIEW', 'IN_REVIEW'];
function unique(liste, message) {
  if (liste.length !== 1) throw new Error(message);
  return liste[0];
}
export function choisir(e) {
  const pre = unique((e.builds.included || []).filter(x => x.type === 'preReleaseVersions' && x.attributes.version === '1.1.17' && x.attributes.platform === 'IOS'), 'Version binaire 1.1.17 iOS introuvable ou ambiguë');
  const build = unique(e.builds.data.filter(b => b.attributes.version === '21' && b.relationships.preReleaseVersion?.data?.id === pre.id), 'Build 21 introuvable ou ambigu');
  if (build.attributes.processingState !== 'VALID' || build.attributes.expired || build.attributes.usesNonExemptEncryption !== false) {
    throw new Error('Le build 21 doit être valide, non expiré et avoir sa déclaration de chiffrement complète. Aucun retrait.');
  }
  const version = unique(e.versions.data.filter(v => v.attributes.platform === 'IOS' && ['1.1.16', '1.1.17'].includes(v.attributes.versionString)), 'Version App Store attendue introuvable ou ambiguë');
  const deja = version.attributes.versionString === '1.1.17' && version.relationships.build?.data?.id === build.id && EN_EXAMEN.includes(version.attributes.appStoreState);
  if (deja) return { version, build, deja };
  if (!MODIFIABLE.includes(version.attributes.appStoreState) && !EN_EXAMEN.includes(version.attributes.appStoreState)) throw new Error('État App Store inattendu : ' + version.attributes.appStoreState);
  const associes = e.details.filter(d => d.items.data.some(i => i.relationships?.appStoreVersion?.data?.id === version.id));
  if (associes.length > 1) throw new Error('Plusieurs examens concernent cette version');
  const detail = associes[0];
  if (detail && (detail.items.links?.next || detail.items.data.length !== 1)) throw new Error('La soumission contient d’autres éléments : aucun retrait automatique');
  const examen = detail && e.examens.data.find(s => s.id === detail.examen);
  if (EN_EXAMEN.includes(version.attributes.appStoreState) && (!examen || !EN_EXAMEN.includes(examen.attributes.state))) throw new Error('Examen actif non identifié avec certitude');
  return { version, build, examen, deja: false };
}

export async function remplacer(api, { pause = ms => new Promise(r => setTimeout(r, ms)), journal = console.log } = {}) {
  const initial = await etat(api);
  const choix = choisir(initial);
  let { version, build, examen } = choix;
  if (choix.deja) return { resultat: 'déjà soumis', version: '1.1.17', build: '21', etat: version.attributes.appStoreState };
  // Lire les notes AVANT le retrait ; les autres métadonnées restent sur la même fiche.
  const locales = await api(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=50`);
  if (locales.links?.next) throw new Error('Liste des langues incomplète');
  const notes = locales.data.map(l => {
    const langue = l.attributes.locale.split('-')[0];
    const note = { fr: "Correction de l’envoi de la voix traduite dans les réunions Zoom ouvertes dans Rapporteur.", en: 'Fixed translated audio being sent to Zoom meetings opened inside Rapporteur.' }[langue];
    const avant = l.attributes.whatsNew || '';
    const texte = note && !avant.includes(note) ? `${avant.trim()}\n\n${note}`.trim() : avant;
    if (texte.length > 4000) throw new Error('Notes trop longues : ' + l.attributes.locale);
    return { id: l.id, texte, changer: texte !== avant };
  });
  if (examen && EN_EXAMEN.includes(examen.attributes.state)) {
    // Relire juste avant la mutation pour détecter une intervention dans la console.
    const controle = choisir(await etat(api));
    if (controle.version.id !== version.id || controle.examen?.id !== examen.id || controle.build.id !== build.id || controle.deja) throw new Error('État modifié depuis le diagnostic');
    journal(`Retrait de la soumission ${examen.id} de la version ${version.attributes.versionString}`);
    await api(`/v1/reviewSubmissions/${examen.id}`, 'PATCH', { type: 'reviewSubmissions', id: examen.id, attributes: { canceled: true } });
    for (let n = 0; n < 60; n++) {
      version = (await api(`/v1/appStoreVersions/${version.id}?include=build`)).data;
      if (MODIFIABLE.includes(version.attributes.appStoreState)) break;
      await pause(5000);
    }
    if (!MODIFIABLE.includes(version.attributes.appStoreState)) throw new Error('Apple traite encore le retrait ; relancer après traitement');
  }
  if (version.attributes.versionString !== '1.1.17') {
    if (version.relationships.build?.data) await api(`/v1/appStoreVersions/${version.id}/relationships/build`, 'PATCH', null);
    version = (await api(`/v1/appStoreVersions/${version.id}`, 'PATCH', { type: 'appStoreVersions', id: version.id, attributes: { versionString: '1.1.17' } })).data;
  }
  await api(`/v1/appStoreVersions/${version.id}/relationships/build`, 'PATCH', { type: 'builds', id: build.id });
  for (const note of notes.filter(n => n.changer)) await api(`/v1/appStoreVersionLocalizations/${note.id}`, 'PATCH', { type: 'appStoreVersionLocalizations', id: note.id, attributes: { whatsNew: note.texte } });
  const relue = (await api(`/v1/appStoreVersions/${version.id}?include=build`)).data;
  if (relue.attributes.versionString !== '1.1.17' || relue.relationships.build?.data?.id !== build.id) throw new Error('Build attaché inattendu : soumission interdite');
  const apres = await etat(api);
  const brouillons = apres.examens.data.filter(s => s.attributes.state === 'READY_FOR_REVIEW' && (!s.attributes.platform || s.attributes.platform === 'IOS'));
  if (brouillons.length > 1) throw new Error('Plusieurs brouillons Apple');
  let nouveau = brouillons[0];
  let items = nouveau && apres.details.find(d => d.examen === nouveau.id)?.items;
  if (nouveau && (!items || items.links?.next || items.data.some(i => i.relationships?.appStoreVersion?.data?.id !== version.id))) throw new Error('Un autre brouillon doit être traité séparément');
  if (!nouveau) nouveau = (await api('/v1/reviewSubmissions', 'POST', { type: 'reviewSubmissions', attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: APP } } } })).data;
  if (!items?.data.length) await api('/v1/reviewSubmissionItems', 'POST', { type: 'reviewSubmissionItems', relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: nouveau.id } }, appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } });
  journal(`Soumission de 1.1.17, build 21, examen ${nouveau.id}`);
  await api(`/v1/reviewSubmissions/${nouveau.id}`, 'PATCH', { type: 'reviewSubmissions', id: nouveau.id, attributes: { submitted: true } });
  for (let n = 0; n < 20; n++) {
    const dernier = (await api(`/v1/appStoreVersions/${version.id}?include=build`)).data;
    if (dernier.attributes.versionString !== '1.1.17' || dernier.relationships.build?.data?.id !== build.id) throw new Error('Version modifiée après envoi');
    if (EN_EXAMEN.includes(dernier.attributes.appStoreState)) return { resultat: 'soumis', version: '1.1.17', build: '21', examen: nouveau.id, etat: dernier.attributes.appStoreState };
    await pause(3000);
  }
  throw new Error('Envoi demandé ; état final Apple à revérifier avant toute nouvelle action');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const action = process.env.ACTION_APPLE || 'verifier';
  const api = clientApple();
  if (action === 'verifier') console.log(JSON.stringify(resume(await etat(api)), null, 2));
  else if (action === 'remplacer' && process.env.CONFIRMATION_APPLE === '1.1.16 -> 1.1.17 (21)') console.log(JSON.stringify(await remplacer(api), null, 2));
  else throw new Error('Action ou confirmation invalide');
}
