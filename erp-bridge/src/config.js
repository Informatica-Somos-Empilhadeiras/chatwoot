const env = process.env;

// "Campo:Endpoint,Campo2:Endpoint2" -> { Campo: 'Endpoint', ... }
function parseFields(raw) {
  const out = {};
  for (const pair of String(raw || '').split(',')) {
    const [campo, ep] = pair.split(':').map(s => (s || '').trim());
    if (campo && ep) out[campo] = ep;
  }
  return out;
}

export const config = {
  port: Number(env.PORT || 4000),
  erpBaseUrl: (env.ERP_BASE_URL || 'https://somos-backend.inntegra.com.br').replace(/\/$/, ''),
  empresas: (env.ERP_EMPRESAS || 'somosemp').split(',').map(s => s.trim()).filter(Boolean),
  deviceId: env.ERP_DEVICE_ID || '',
  lookbackDays: Number(env.OS_LOOKBACK_DAYS || 180),
  forwardDays: Number(env.OS_FORWARD_DAYS || 365),
  tipoData: env.OS_TIPO_DATA || 'DataEntrada',
  cacheTtlMs: Number(env.CACHE_TTL_SECONDS || 120) * 1000,
  timeoutMs: Number(env.ERP_TIMEOUT_MS || 15000),
  userAgent: env.ERP_USER_AGENT || 'somos-chatwoot-bridge/0.1',
  mock: String(env.MOCK || 'false').toLowerCase() === 'true',
  bridgeToken: env.BRIDGE_TOKEN || '',
  // Escrita (OFF por padrao). So habilite apontando no ERP real com cuidado.
  writeEnabled: String(env.WRITE_ENABLED || 'false').toLowerCase() === 'true',
  idUsuario: env.ERP_ID_USUARIO || '0',
  // Campos de update extras que VOCE confirma no proprio DevTools (sem probing/HAR).
  // Ex.: ERP_UPDATE_FIELDS="Observacoes:UpdateObservacoes,Previsao:UpdatePrevisao"
  updateFields: parseFields(env.ERP_UPDATE_FIELDS),
};
