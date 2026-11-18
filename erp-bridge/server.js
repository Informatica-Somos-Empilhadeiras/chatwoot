import express from 'express';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { config } from './src/config.js';
import { fetchAllOs } from './src/erpClient.js';
import { normalizeOs } from './src/normalize.js';
import { matchOsForContact } from './src/match.js';

const __dir = dirname(fileURLToPath(import.meta.url));
const app = express();

// Protecao opcional do proprio bridge (nao do ERP).
app.use((req, res, next) => {
  if (config.bridgeToken && req.path.startsWith('/api/')) {
    if (req.get('X-Bridge-Token') !== config.bridgeToken) {
      return res.status(401).json({ error: 'token invalido' });
    }
  }
  next();
});

app.get('/healthz', (req, res) => res.json({ ok: true, mock: config.mock }));

// Espelho read-only: busca ao vivo (cacheada) e filtra para o contato. Nada e gravado.
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

app.use(express.static(join(__dir, 'public')));

app.listen(config.port, () => {
  console.log(`erp-bridge ouvindo em http://localhost:${config.port} (mock=${config.mock})`);
});
