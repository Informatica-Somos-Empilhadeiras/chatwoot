import { config } from './config.js';

// Campos de UPDATE de OS existente.
// CONFIRMADOS por captura do app oficial + os que VOCE adicionar em ERP_UPDATE_FIELDS
// (confirmando o nome do endpoint no seu proprio DevTools, sem probing).
// SubStatus NAO entra aqui: tem fluxo proprio (updateSubStatus) com o par GravaHistorico.
const CONFIRMADOS = {
  Defeitos: 'UpdateDefeitos',
};
const ENDPOINTS = { ...CONFIRMADOS, ...config.updateFields };

async function put(path, body) {
  if (config.mock) return { mock: true, path, body }; // em mock NAO chama o ERP
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), config.timeoutMs);
  try {
    const headers = {
      'Content-Type': 'application/json;charset=UTF-8',
      'User-Agent': config.userAgent,
    };
    if (config.deviceId) headers['x-device-id'] = config.deviceId;
    const res = await fetch(`${config.erpBaseUrl}${path}`, {
      method: 'PUT', headers, body: JSON.stringify(body), signal: ctrl.signal,
    });
    if (!res.ok) throw new Error(`ERP respondeu ${res.status}`);
    return await res.json().catch(() => []);
  } finally {
    clearTimeout(t);
  }
}

export function campoSuportado(campo) {
  return Boolean(ENDPOINTS[campo]);
}

export function camposDisponiveis() {
  return Object.keys(ENDPOINTS);
}

// Atualiza um campo simples de uma OS existente (ex.: Defeitos).
export async function updateCampo(codigoOS, campo, valor, empresa) {
  const ep = ENDPOINTS[campo];
  if (!ep) throw new Error(`campo nao mapeado: ${campo} (adicione em ERP_UPDATE_FIELDS)`);
  const body = { [campo]: valor, listaEmpresas: config.empresas, Empresa: empresa };
  return put(`/KanbanOrdemServico/api/${ep}/${codigoOS}`, body);
}

// Troca de substatus: a UI faz o par Update + GravaHistorico. Respeitamos esse contrato
// para nao quebrar o historico do ERP (tabela logalterasubstatusos).
export async function updateSubStatus(codigoOS, { subStatusNovo, subStatusAntigo, empresa, idUsuario }) {
  await put(`/KanbanOrdemServico/api/UpdateSubStatusOS/${codigoOS}`, {
    SubStatus: subStatusNovo,
    listaEmpresas: config.empresas,
    Empresa: empresa,
  });
  await put(`/KanbanOrdemServico/api/GravaHistoricoSubStatusOS/${codigoOS}`, {
    SubStatusAntigo: subStatusAntigo ?? subStatusNovo,
    SubStatusNovo: subStatusNovo,
    listaEmpresas: config.empresas,
    idUsuario: String(idUsuario ?? config.idUsuario),
    Empresa: empresa,
  });
  return { ok: true };
}
