// OUTSIDER: as mesmas regras do motor do bot (Outsider::Bot::ReplyMatcher, Hours e Runner#render),
// para o "Testar" do editor rodar o fluxo na tela sem mandar nada a ninguém.

const KEYCAPS = {
  '0️⃣': '0',
  '1️⃣': '1',
  '2️⃣': '2',
  '3️⃣': '3',
  '4️⃣': '4',
  '5️⃣': '5',
  '6️⃣': '6',
  '7️⃣': '7',
  '8️⃣': '8',
  '9️⃣': '9',
  '🔟': '10',
};

export const fold = text =>
  String(text || '')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();

export const splitWords = text => fold(text).split(' ').filter(Boolean);

const byNumber = (options, text) => {
  const plain = Object.entries(KEYCAPS).reduce(
    (value, [cap, digit]) => value.split(cap).join(digit),
    text
  );
  const number = Number(plain.match(/^\D{0,10}?(\d{1,2})\W*$/)?.[1]);
  return number > 0 ? options[number - 1] : undefined;
};

const byLabel = (options, text) => {
  const folded = fold(text);
  if (!folded) return undefined;
  const words = folded.split(' ');
  return (
    options.find(option => fold(option.label) === folded) ||
    options.find(option => {
      const label = fold(option.label);
      return label && !label.includes(' ') && words.includes(label);
    }) ||
    options.find(option => {
      const label = fold(option.label);
      return label.length >= 4 && folded.includes(label);
    })
  );
};

// a opção do menu que o cliente escolheu (número, "2️⃣" ou o texto), ou undefined
export const matchOption = (options, text) => {
  const value = String(text || '').trim();
  if (!value) return undefined;
  return byNumber(options, value) || byLabel(options, value);
};

// a primeira regra da Pergunta cuja palavra aparece na resposta
export const matchRoute = (routes, text) => {
  const folded = ` ${fold(text)} `;
  return (routes || []).find(route =>
    (route.keywords || []).some(word => {
      const key = fold(word);
      return key && folded.includes(` ${key} `);
    })
  );
};

const WEEKDAYS = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const toMinutes = value => {
  const [hour, minute] = String(value || '0:0')
    .split(':')
    .map(Number);
  return (hour || 0) * 60 + (minute || 0);
};

// dentro do horário do bloco Horário de atendimento, no fuso do bloco
export const openNow = (data, date = new Date()) => {
  let parts;
  try {
    parts = new Intl.DateTimeFormat('en-US', {
      timeZone: data.timezone || 'America/Sao_Paulo',
      weekday: 'short',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(date);
  } catch {
    return false;
  }
  const part = type => parts.find(item => item.type === type)?.value;
  const weekday = WEEKDAYS[part('weekday')] ?? 0;
  const minute = Number(part('hour')) * 60 + Number(part('minute'));
  const hours = data.hours || {};
  const inside = (day, overnight) => {
    if (!day?.enabled) return false;
    const start = toMinutes(day.start);
    const end = toMinutes(day.end);
    if (overnight) return start > end && minute < end;
    return start <= end ? minute >= start && minute < end : minute >= start;
  };
  return (
    inside(hours[String(weekday)], false) ||
    inside(hours[String((weekday + 6) % 7)], true)
  );
};

export const SAMPLE_CONTACT = {
  name: 'Maria Souza',
  phone_number: '+5511987654321',
  email: 'maria@exemplo.com.br',
};

// troca {{contato.nome}} e as respostas guardadas, como o servidor
export const renderText = (text, variables, contact = SAMPLE_CONTACT) =>
  String(text || '').replace(/\{\{\s*([a-z0-9_.]+)\s*\}\}/gi, (_, key) => {
    switch (key.toLowerCase()) {
      case 'contato.nome':
      case 'nome_contato':
        return contact.name;
      case 'contato.primeiro_nome':
      case 'primeiro_nome':
        return contact.name.split(' ')[0];
      case 'contato.telefone':
        return contact.phone_number;
      case 'contato.email':
        return contact.email;
      default:
        return variables[key.toLowerCase()] ?? '';
    }
  });

// *negrito*, _itálico_ e ~riscado~ do WhatsApp, com o texto já escapado
export const whatsappHtml = text =>
  String(text || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\*([^*\n]+)\*/g, '<strong>$1</strong>')
    .replace(/(^|\s)_([^_\n]+)_/g, '$1<em>$2</em>')
    .replace(/~([^~\n]+)~/g, '<s>$1</s>')
    .replace(/\n/g, '<br>');

export const NUMBERS = [
  '1️⃣',
  '2️⃣',
  '3️⃣',
  '4️⃣',
  '5️⃣',
  '6️⃣',
  '7️⃣',
  '8️⃣',
  '9️⃣',
  '🔟',
];
