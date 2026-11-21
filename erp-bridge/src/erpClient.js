import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { config } from './config.js';

const __dir = dirname(fileURLToPath(import.meta.url));

// Cache em memoria: 1 entrada por janela de consulta.
// Objetivo "bom-cidadao": N aberturas de painel => no maximo 1 chamada ao ERP por TTL.
const cache = new Map();
// Single-flight: se varias requisicoes chegam com o cache frio, so UMA vai ao ERP.
let inFlight = null;

function ymd(d) { return d.toISOString().slice(0, 10); }

function windowDates() {
  const now = new Date();
  const ini = new Date(now); ini.setDate(ini.getDate() - config.lookbackDays);
  const fim = new Date(now); fim.setDate(fim.getDate() + config.forwardDays);
  return { vDataInicial: ymd(ini), vDataFinal: ymd(fim) };
}

function buildValoresDashUrl() {
  const { vDataInicial, vDataFinal } = windowDates();
  const p = new URLSearchParams();
  for (const e of config.empresas) p.append('listaEmpresas[]', e);
  p.set('idUsuario', '0');
  p.set('respeitarRegrasHierarquia', '1');
  p.set('diasPrevisao', String(config.forwardDays));
  p.set('vDataInicial', vDataInicial);
  p.set('vDataFinal', vDataFinal);
  p.set('myTipoData', config.tipoData);
  return `${config.erpBaseUrl}/KanbanOrdemServico/api/valoresDash?${p.toString()}`;
}

// GET no ERP com timeout cobrindo tambem a leitura do corpo (read recebe o Response).
export async function erpGet(url, accept, read) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), config.timeoutMs);
  try {
    const headers = { Accept: accept, 'User-Agent': config.userAgent };
    if (config.deviceId) headers['x-device-id'] = config.deviceId;
    const res = await fetch(url, { headers, signal: ctrl.signal });
    if (!res.ok) throw new Error(`ERP respondeu ${res.status}`);
    return await read(res);
  } finally {
    clearTimeout(t);
  }
}

const httpGetJson = url => erpGet(url, 'application/json', res => res.json());

async function loadMock() {
  const raw = await readFile(join(__dir, '..', 'mock', 'valoresDash.sample.json'), 'utf8');
  return JSON.parse(raw);
}

async function fetchFresh(stale) {
  let data;
  if (config.mock) {
    data = await loadMock();
  } else {
    const url = buildValoresDashUrl();
    try {
      data = await httpGetJson(url);
    } catch (err) {
      // Uma tentativa extra com backoff curto; se falhar, serve cache velho se houver.
      await new Promise(r => setTimeout(r, 1000));
      try {
        data = await httpGetJson(url);
      } catch (err2) {
        if (stale) return stale.data; // stale-while-error: nao derruba a UI por um soluco
        throw err2;
      }
    }
  }
  if (!Array.isArray(data)) data = [];
  cache.set('valoresDash', { at: Date.now(), data });
  return data;
}

// Busca a lista completa de OS (todas empresas, janela de datas), cacheada + single-flight.
export async function fetchAllOs() {
  const hit = cache.get('valoresDash');
  if (hit && (Date.now() - hit.at) < config.cacheTtlMs) return hit.data;
  if (inFlight) return inFlight; // ja ha uma busca em andamento: aproveita a mesma
  inFlight = fetchFresh(hit).finally(() => { inFlight = null; });
  return inFlight;
}
