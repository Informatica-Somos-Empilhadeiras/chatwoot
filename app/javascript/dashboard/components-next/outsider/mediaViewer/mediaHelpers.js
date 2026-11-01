// OUTSIDER: ajudantes do visualizador de mídia e do painel do contato (anexos em snake_case,
// como vêm da API).
export const VIEWABLE_TYPES = ['image', 'video', 'ig_reel', 'audio'];
export const DOCUMENT_TYPES = ['file'];

export const isViewable = attachment =>
  VIEWABLE_TYPES.includes(attachment?.file_type) && !!attachment?.data_url;

// mais antigas primeiro, como a fila de miniaturas do WhatsApp
export const byOldest = (a, b) =>
  (a.created_at || 0) - (b.created_at || 0) || (a.id || 0) - (b.id || 0);

export const fileNameOf = attachment => {
  const url = attachment?.data_url || '';
  const last = url.split('?')[0].split('/').pop() || '';
  try {
    return decodeURIComponent(last);
  } catch (error) {
    return last;
  }
};

export const formatSize = bytes => {
  if (!bytes) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let size = bytes;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size.toFixed(unit ? 1 : 0).replace('.', ',')} ${units[unit]}`;
};

const startOfMonth = date => new Date(date.getFullYear(), date.getMonth(), 1);

// "Neste mês", "Setembro", "Outubro de 2025" (mais novas primeiro)
export const groupByMonth = (
  items,
  { locale = 'pt-BR', thisMonth = 'Neste mês', now = new Date() } = {}
) => {
  const lang = String(locale).replace('_', '-');
  const current = startOfMonth(now).getTime();
  const groups = new Map();
  [...items]
    .sort((a, b) => byOldest(b, a))
    .forEach(item => {
      const date = new Date((item.created_at || 0) * 1000);
      const key = startOfMonth(date).getTime();
      if (!groups.has(key)) {
        let label = thisMonth;
        if (key !== current) {
          const options = { month: 'long' };
          if (date.getFullYear() !== now.getFullYear())
            options.year = 'numeric';
          label = date.toLocaleDateString(lang, options);
          label = label.charAt(0).toUpperCase() + label.slice(1);
        }
        groups.set(key, { key, label, items: [] });
      }
      groups.get(key).items.push(item);
    });
  return [...groups.values()];
};

const URL_REGEX = /\bhttps?:\/\/[^\s<>"'`)\]]+/gi;

// links que aparecem nas mensagens (mais novos primeiro, sem repetir)
export const linksFromMessages = messages => {
  const seen = new Set();
  const links = [];
  [...messages]
    .filter(message => message.content && !message.private)
    .sort((a, b) => (b.created_at || 0) - (a.created_at || 0))
    .forEach(message => {
      (message.content.match(URL_REGEX) || []).forEach(raw => {
        const url = raw.replace(/[.,;:!?*_]+$/, '');
        if (seen.has(url)) return;
        seen.add(url);
        let host = url;
        try {
          host = new URL(url).hostname.replace(/^www\./, '');
        } catch (error) {
          // fica o texto
        }
        links.push({
          url,
          host,
          messageId: message.id,
          createdAt: message.created_at,
          text: message.content
            .replace(URL_REGEX, '')
            .replace(/[*_~`]/g, '')
            .trim(),
        });
      });
    });
  return links;
};
