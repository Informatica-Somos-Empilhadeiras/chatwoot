// OUTSIDER: lê o texto que a operadora manda (e-mail, PDF copiado, mensagem) e tira dele os dados da conta
// SIP (Entrega 22): servidor, porta, transporte, usuário, senha, IPs e números. Cada linha "Rótulo: valor"
// é reconhecida pelo rótulo, em português ou inglês. A tela preenche o formulário e a pessoa confere.
import { nationalNumber } from './brazil';

// a ordem importa: "usuário de autenticação" antes de "usuário"; "IP do servidor" é servidor
const LABELS = [
  [
    'auth_username',
    /auth(entication|orization)?[ _-]?(id|user|name|usuario)|usuario (de|para) autentica/,
  ],
  ['password', /senha|password|secret|\bpass\b/],
  ['host', /servidor|server|proxy|dominio|domain|host|registrar|realm/],
  ['ips', /\bips?\b/],
  ['username', /usuario|user|login|conta|account|ramal sip/],
  ['port', /porta|\bport\b/],
  ['transport', /transporte|transport|protocolo|protocol/],
  ['numbers', /\bdids?\b|numero|telefone|linha|tronco/],
];

const IP = /\b\d{1,3}(?:\.\d{1,3}){3}(?:\/\d{1,2})?\b/g;
const HOST =
  /(?:sips?:)?(?:[^@\s]+@)?((?:[a-z0-9-]+\.)+[a-z]{2,}|\d{1,3}(?:\.\d{1,3}){3})(?::(\d{2,5}))?/i;
const PHONE = /(?:\+?55[\s.-]?)?\(?0?\d{2}\)?[\s.-]?\d{4,5}[\s.-]?\d{4}/g;

const plain = text => text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

const readLine = (result, field, value) => {
  if (field === 'host') {
    const match = value.match(HOST);
    if (!match) return;
    result.trunk.host ||= match[1].toLowerCase();
    if (match[2]) result.trunk.port ||= Number(match[2]);
  } else if (field === 'port') {
    const port = Number(value.match(/\d{2,5}/)?.[0]);
    if (port) result.trunk.port = port;
  } else if (field === 'transport') {
    const transport = /tcp/i.test(value) ? 'tcp' : /udp/i.test(value) && 'udp';
    if (transport) result.trunk.transport = transport;
  } else if (field === 'ips') {
    result.trunk.ips.push(...(value.match(IP) || []));
  } else if (field === 'numbers') {
    result.numbers.push(
      ...(value.match(PHONE) || []).map(nationalNumber).filter(Boolean)
    );
  } else {
    result.trunk[field] ||= value.trim();
  }
};

export const parseOperatorText = text => {
  const result = {
    trunk: { ips: [] },
    numbers: [],
  };
  String(text || '')
    .split(/\r?\n/)
    .forEach(line => {
      const match = line.match(
        /^\s*[-•*]?\s*([^:=]{2,60}?)\s*[:=]\s*(.+?)\s*$/
      );
      if (!match) return;
      const label = plain(match[1]);
      const entry = LABELS.find(([, pattern]) => pattern.test(label));
      if (entry) readLine(result, entry[0], match[2]);
    });

  const { trunk } = result;
  trunk.ips = [...new Set(trunk.ips)];
  // muitas operadoras usam o próprio número como usuário e nem listam os números
  if (!result.numbers.length && nationalNumber(trunk.username)) {
    result.numbers.push(nationalNumber(trunk.username));
  }
  result.numbers = [...new Set(result.numbers)];
  if (trunk.username && trunk.password) trunk.auth = 'register';
  else if (!trunk.username && trunk.ips.length) trunk.auth = 'ip';
  return result;
};
