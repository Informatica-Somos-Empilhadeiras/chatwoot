import express from 'express';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { config } from './src/config.js';
import { fetchAllOs } from './src/erpClient.js';
import { normalizeOs } from './src/normalize.js';
import { matchOsForContact } from './src/match.js';
import { updateCampo, updateSubStatus, campoSuportado, camposDisponiveis } from './src/erpWrite.js';
import {
  relatorioOs, fotoChecklist, logoEmissor, codigoValido, empresaValida, refValida, NaoEncontrado,
} from './src/kanbanReport.js';

const __dir = dirname(fileURLToPath(import.meta.url));
const app = express();
app.use(express.json());

// Protecao opcional do proprio bridge (nao do ERP).
app.use((req, res, next) => {
  if (config.bridgeToken && req.path.startsWith('/api/')) {
    if (req.get('X-Bridge-Token') !== config.bridgeToken) {
      return res.status(401).json({ error: 'token invalido' });
    }
  }
  next();
});

// Escrita so passa se explicitamente habilitada.
function requireWrite(req, res, next) {
  if (!config.writeEnabled) {
    return res.status(403).json({ error: 'escrita desabilitada (WRITE_ENABLED=false)' });
  }
  next();
}

app.get('/healthz', (req, res) => res.json({
  ok: true,
  mock: config.mock,
  writeEnabled: config.writeEnabled,
  camposUpdate: camposDisponiveis(),
}));

// ---- Leitura (espelho): busca ao vivo (cacheada) e filtra para o contato. Nada e gravado. ----
app.get('/api/os', async (req, res) => {
  try {
    const all = await fetchAllOs();
    const os = matchOsForContact(all, {
      codigoCliente: req.query.codigoCliente,
      nome: req.query.nome,
      os: req.query.os,
    })
      .map(normalizeOs)
      .sort((a, b) => String(b.dataEntrada).localeCompare(String(a.dataEntrada)));
    res.json({ count: os.length, mock: config.mock, os });
  } catch (err) {
    res.status(502).json({ error: 'falha ao consultar o ERP', detail: String(err.message || err) });
  }
});

// ---- Relatorio da OS (o mesmo do kanban de KPI) e fotos do checklist. So leitura. ----
// OS so com digitos e empresa da lista configurada: a ponte nao vira proxy aberto do ERP.
function osValida(req, res, next) {
  if (config.mock) return res.status(409).json({ error: 'relatorio indisponivel no modo de exemplo (MOCK=true)' });
  const empresa = String(req.query.empresa || '');
  if (!codigoValido(req.params.codigo) || !empresaValida(empresa)) {
    return res.status(400).json({ error: 'OS ou empresa invalida' });
  }
  req.empresa = empresa;
  next();
}

function falhaRelatorio(res, err) {
  res.status(err instanceof NaoEncontrado ? 404 : 502).json({ error: String(err.message || err) });
}

function enviarImagem(res, img) {
  res.set({ 'Content-Type': img.type, 'Cache-Control': 'private, max-age=1800', 'X-Content-Type-Options': 'nosniff' });
  res.send(img.body);
}

app.get('/api/os/:codigo/relatorio', osValida, async (req, res) => {
  try {
    const { data } = await relatorioOs(req.params.codigo, req.empresa);
    res.json(data);
  } catch (err) {
    falhaRelatorio(res, err);
  }
});

app.get('/api/os/:codigo/imagem/:ref', osValida, async (req, res) => {
  if (!refValida(req.params.codigo, req.params.ref)) return res.status(400).json({ error: 'imagem invalida' });
  try {
    enviarImagem(res, await fotoChecklist(req.params.ref, req.empresa));
  } catch (err) {
    falhaRelatorio(res, err);
  }
});

app.get('/api/os/:codigo/logo', osValida, async (req, res) => {
  try {
    enviarImagem(res, await logoEmissor(req.params.codigo, req.empresa));
  } catch (err) {
    falhaRelatorio(res, err);
  }
});

// ---- Escrita (parcial, confirmada por captura): update de campos de OS existente. ----
// Troca de substatus (faz o par Update + GravaHistorico).
app.put('/api/os/:codigo/substatus', requireWrite, async (req, res) => {
  try {
    const { subStatusNovo, subStatusAntigo, empresa, idUsuario } = req.body || {};
    if (!subStatusNovo || !empresa) {
      return res.status(400).json({ error: 'subStatusNovo e empresa sao obrigatorios' });
    }
    const result = await updateSubStatus(req.params.codigo, { subStatusNovo, subStatusAntigo, empresa, idUsuario });
    res.json({ ok: true, mock: config.mock, result });
  } catch (err) {
    res.status(502).json({ error: String(err.message || err) });
  }
});

// Update de um campo simples confirmado (ex.: Defeitos).
app.put('/api/os/:codigo/campo/:campo', requireWrite, async (req, res) => {
  try {
    const { campo } = req.params;
    if (!campoSuportado(campo)) {
      return res.status(400).json({ error: `campo nao suportado/confirmado: ${campo}` });
    }
    const { valor, empresa } = req.body || {};
    if (empresa == null) return res.status(400).json({ error: 'empresa e obrigatoria' });
    const result = await updateCampo(req.params.codigo, campo, valor, empresa);
    res.json({ ok: true, mock: config.mock, result });
  } catch (err) {
    res.status(502).json({ error: String(err.message || err) });
  }
});

app.use(express.static(join(__dir, 'public')));

app.listen(config.port, () => {
  console.log(`erp-bridge ouvindo em http://localhost:${config.port} (mock=${config.mock}, write=${config.writeEnabled})`);
});
