import test from 'node:test';
import assert from 'node:assert/strict';
import { APP, remplacer } from '../outils/app-store.mjs';

function banc({ invalide = false, autre = false, deja = false, mauvaisBuild = false } = {}) {
  const version = { id: 'v', type: 'appStoreVersions', attributes: { platform: 'IOS', versionString: deja ? '1.1.17' : '1.1.16', appStoreState: 'IN_REVIEW' }, relationships: { build: { data: { type: 'builds', id: deja ? 'b' : 'ancien' } } } };
  const build = { id: 'b', type: 'builds', attributes: { version: '21', processingState: invalide ? 'PROCESSING' : 'VALID', expired: false, usesNonExemptEncryption: false }, relationships: { preReleaseVersion: { data: { id: 'pre' } } } };
  const examens = [{ id: 'ancien-examen', attributes: { state: 'IN_REVIEW', platform: 'IOS' } }];
  const item = id => ({ id: 'item-' + id, attributes: { state: 'READY_FOR_REVIEW' }, relationships: { appStoreVersion: { data: { id } } } });
  const items = { 'ancien-examen': [item('v'), ...(autre ? [item('autre')] : [])] };
  const ecritures = [];
  const api = async (path, method = 'GET', data) => {
    const p = path.split('?')[0];
    if (method !== 'GET') ecritures.push({ p, method, data: structuredClone(data) });
    let result;
    if (method === 'GET') {
      if (p === `/v1/apps/${APP}`) result = { data: { id: APP, attributes: { bundleId: 'com.lerapporteur.mobile' } } };
      else if (p.endsWith('/appStoreVersions')) result = { data: [version] };
      else if (p === '/v1/builds') result = { data: [build], included: [{ type: 'preReleaseVersions', id: 'pre', attributes: { version: '1.1.17', platform: 'IOS' } }] };
      else if (p.endsWith('/reviewSubmissions')) result = { data: examens };
      else if (p.endsWith('/items')) result = { data: items[p.split('/')[3]] };
      else if (p === '/v1/appStoreVersions/v') result = { data: version };
      else if (p.endsWith('/appStoreVersionLocalizations')) result = { data: [{ id: 'fr', attributes: { locale: 'fr-FR', whatsNew: 'Améliorations existantes.' } }] };
    } else if (p.startsWith('/v1/reviewSubmissions/') && data.attributes?.canceled) {
      examens[0].attributes.state = 'CANCELED'; version.attributes.appStoreState = 'DEVELOPER_REJECTED'; result = {};
    } else if (p === '/v1/appStoreVersions/v/relationships/build') {
      version.relationships.build.data = mauvaisBuild && data ? { id: 'inattendu' } : data; result = {};
    } else if (p === '/v1/appStoreVersions/v') {
      Object.assign(version.attributes, data.attributes); result = { data: version };
    } else if (p.startsWith('/v1/appStoreVersionLocalizations/')) result = {};
    else if (p === '/v1/reviewSubmissions') {
      const s = { id: 'nouveau', attributes: { state: 'READY_FOR_REVIEW', platform: 'IOS' } };
      examens.push(s); items.nouveau = []; result = { data: s };
    } else if (p === '/v1/reviewSubmissionItems') { items.nouveau.push(item('v')); result = {}; }
    else if (p === '/v1/reviewSubmissions/nouveau' && data.attributes.submitted) {
      version.attributes.appStoreState = 'WAITING_FOR_REVIEW'; examens.at(-1).attributes.state = 'WAITING_FOR_REVIEW'; result = {};
    }
    if (!result) throw new Error(`Appel imprévu ${method} ${path}`);
    return structuredClone(result);
  };
  return { api, ecritures };
}
const options = { pause: async () => {}, journal() {} };
test('build encore en traitement : aucun retrait ni écriture', async () => {
  const b = banc({ invalide: true });
  await assert.rejects(remplacer(b.api, options), /build 21 doit être valide/);
  assert.equal(b.ecritures.length, 0);
});
test('soumission contenant un autre élément : aucun retrait', async () => {
  const b = banc({ autre: true });
  await assert.rejects(remplacer(b.api, options), /autres éléments/);
  assert.equal(b.ecritures.length, 0);
});
test('retrait puis remplacement exact du build et soumission vérifiée', async () => {
  const b = banc();
  assert.equal((await remplacer(b.api, options)).etat, 'WAITING_FOR_REVIEW');
  assert.equal(b.ecritures[0].data.attributes.canceled, true);
  assert.equal(b.ecritures[1].data, null);
  assert.equal(b.ecritures[2].data.attributes.versionString, '1.1.17');
  assert.equal(b.ecritures[3].data.id, 'b');
  assert.match(b.ecritures[4].data.attributes.whatsNew, /^Améliorations existantes\./);
  assert.equal(b.ecritures.at(-1).data.attributes.submitted, true);
});
test('build relu différent : aucune soumission', async () => {
  const b = banc({ mauvaisBuild: true });
  await assert.rejects(remplacer(b.api, options), /Build attaché inattendu/);
  assert.ok(!b.ecritures.some(e => e.data?.attributes?.submitted));
});
test('nouvelle version déjà en examen : aucune écriture', async () => {
  const b = banc({ deja: true });
  assert.equal((await remplacer(b.api, options)).resultat, 'déjà soumis');
  assert.equal(b.ecritures.length, 0);
});
