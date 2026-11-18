import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { config } from './config.js';

const __dir = dirname(fileURLToPath(import.meta.url));

// Cache em memoria: 1 entrada por janela de consulta.
// Objetivo "bom-cidadao": N aberturas de painel => no maximo 1 chamada ao ERP por TTL.
const cache = new Map();

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

async function httpGetJson(url) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), config.timeoutMs);
  try {
    const headers = { Accept: 'application/json', 'User-Agent': config.userAgent };
    if (config.deviceId) headers['x-device-id'] = config.deviceId;
    const res = await fetch(url, { headers, signal: ctrl.signal });
    if (!res.ok) throw new Error(`ERP respondeu ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(t);
  }
}

async function loadMock() {
  const raw = await readFile(join(__dir, '..', 'mock', 'valoresDash.sample.json'), 'utf8');
  return JSON.parse(raw);
}

// Busca a lista completa de OS (todas empresas, janela de datas), cacheada.
export async function fetchAllOs() {
  const key = 'valoresDash';
  const hit = cache.get(key);
  if (hit && (Date.now() - hit.at) < config.cacheTtlMs) return hit.data;

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
        if (hit) return hit.data; // stale-while-error: nao derruba a UI por um soluco
        throw err2;
      }
    }
  }
  if (!Array.isArray(data)) data = [];
  cache.set(key, { at: Date.now(), data });
  return data;
}
