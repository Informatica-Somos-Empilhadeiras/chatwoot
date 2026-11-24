// OUTSIDER: pequenos ajudantes das telas de e-mail dos Aplicativos.
const TONES = [
  'bg-n-blue-3 text-n-blue-11',
  'bg-n-teal-3 text-n-teal-11',
  'bg-n-amber-3 text-n-amber-11',
  'bg-n-ruby-3 text-n-ruby-11',
  'bg-n-iris-3 text-n-iris-11',
  'bg-n-slate-3 text-n-slate-11',
];

export const initialsOf = name => {
  const words = String(name || '?')
    .replace(/<.*>/, '')
    .replace(/@.*/, '')
    .trim()
    .split(/[\s._-]+/)
    .filter(Boolean);
  if (!words.length) return '?';
  const first = words[0][0] || '';
  const last = words.length > 1 ? words[words.length - 1][0] : '';
  return `${first}${last}`.toUpperCase();
};

// cor estável por remetente
export const avatarTone = key => {
  const text = String(key || '');
  let hash = 0;
  for (let i = 0; i < text.length; i += 1)
    hash = (hash * 31 + text.charCodeAt(i)) % 9973;
  return TONES[hash % TONES.length];
};

export const fullDate = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        weekday: 'short',
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';

export const peopleText = list =>
  (list || []).map(person => person.name || person.email).join(', ');

// texto citado para encaminhar/responder no Chatwoot (o servidor já põe o original embaixo; aqui é só o assunto)
// Outlook em português usa "RE:" e "ENC:"; o Gmail usa "Re:" e "Fwd:"
export const replySubject = (mode, subject, provider = 'microsoft') => {
  const clean = String(subject || '');
  const gmail = provider === 'google';
  if (mode === 'forward') {
    if (/^(enc|fw|fwd):/i.test(clean)) return clean;
    return `${gmail ? 'Fwd' : 'ENC'}: ${clean}`;
  }
  if (/^(re|res):/i.test(clean)) return clean;
  return `${gmail ? 'Re' : 'RE'}: ${clean}`;
};
