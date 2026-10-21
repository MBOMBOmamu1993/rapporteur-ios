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
      ...(data ? { body: JSON.stringify({ data }) } : {}), signal: AbortSignal.timeout(45000),
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
  return { app, versions, builds, examens };
}

export function resume(e) {
  return {
    app: { id: e.app.id, bundle: e.app.attributes.bundleId },
    versions: e.versions.data.map(v => ({ id: v.id, version: v.attributes.versionString, etat: v.attributes.appStoreState, build: v.relationships.build?.data?.id })),
    builds: e.builds.data.map(b => ({ id: b.id, numero: b.attributes.version, traitement: b.attributes.processingState, expire: b.attributes.expired, chiffrementNonExempte: b.attributes.usesNonExemptEncryption, preRelease: b.relationships.preReleaseVersion?.data?.id })),
    prereleases: e.builds.included?.filter(x => x.type === 'preReleaseVersions').map(x => ({ id: x.id, ...x.attributes })),
    examens: e.examens.data.map(s => ({ id: s.id, etat: s.attributes.state, plateforme: s.attributes.platform, items: s.relationships.items?.data })),
    items: e.examens.included?.filter(x => x.type === 'reviewSubmissionItems').map(x => ({ id: x.id, etat: x.attributes.state, version: x.relationships.appStoreVersion?.data?.id })),
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if ((process.env.ACTION_APPLE || 'verifier') !== 'verifier') throw new Error('Action non implémentée');
  console.log(JSON.stringify(resume(await etat(clientApple())), null, 2));
}
