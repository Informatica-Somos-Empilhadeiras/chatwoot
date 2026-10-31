// OUTSIDER: tipos de conexão oferecidos ao cadastrar (cada um já deixa o formulário certo) e como mostrar
// uma conexão salva na lista.
export const PRESETS = {
  api: {
    icon: 'i-lucide-plug-zap',
    form: { kind: 'http', auth_type: 'header', header_name: 'X-API-Key' },
  },
  supabase: {
    icon: 'i-lucide-database-zap',
    form: { kind: 'http', auth_type: 'headers' },
  },
  postgres: { icon: 'i-lucide-database', form: { kind: 'postgres' } },
  graphql: {
    icon: 'i-lucide-braces',
    form: { kind: 'http', auth_type: 'bearer' },
  },
  webhook: {
    icon: 'i-lucide-webhook',
    form: { kind: 'http', auth_type: 'none', allow_write: true },
  },
  nextcloud: {
    icon: 'i-lucide-cloud',
    form: {
      kind: 'nextcloud',
      base_url: 'https://nuvem.somosempilhadeiras.com',
      root_folder: '/',
    },
  },
};

export const connectionIcon = connection => {
  if (connection.kind === 'nextcloud') return PRESETS.nextcloud.icon;
  if (connection.kind === 'postgres') return PRESETS.postgres.icon;
  if (/supabase\.(co|com)/.test(connection.base_url || '')) {
    return PRESETS.supabase.icon;
  }
  return PRESETS.api.icon;
};

// endereço para mostrar: o do banco sem senha, o do Nextcloud com usuário e pasta
export const connectionAddress = (connection, t) => {
  const settings = connection.settings || {};
  if (connection.kind === 'postgres') {
    const match = String(connection.base_url || '').match(
      /^postgresql:\/\/(.+):(\d+)\/(.+)$/
    );
    if (!match) return connection.base_url;
    return t('OUTSIDER_TOOLS.BOT.CONNECTIONS.PG_ADDRESS', {
      host: match[1],
      port: match[2],
      database: match[3],
      user: settings.username || '—',
    });
  }
  if (connection.kind === 'nextcloud') {
    return t('OUTSIDER_TOOLS.BOT.CONNECTIONS.NC_ADDRESS', {
      url: connection.base_url,
      user: settings.username || '—',
      folder: settings.root_folder || '/',
    });
  }
  return connection.base_url;
};

export const authLabel = (connection, t) => {
  if (connection.kind !== 'http') return '';
  const settings = connection.settings || {};
  return t(
    `OUTSIDER_TOOLS.BOT.CONNECTIONS.AUTH_SHORT.${connection.auth_type}`,
    {
      header: settings.header_name || 'X-API-Key',
      param: settings.query_param || 'api_key',
      names: (connection.secret_headers || []).join(', ') || '—',
    }
  );
};

// falta senha ou chave para a conexão funcionar
export const missingSecret = connection => {
  if (connection.secrets_unreadable) return true;
  if (connection.kind === 'http' && connection.auth_type === 'headers') {
    return !(connection.secret_headers || []).length;
  }
  return Object.values(connection.secrets_set || {}).some(value => !value);
};
