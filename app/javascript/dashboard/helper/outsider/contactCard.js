// OUTSIDER: cartão de contato do WhatsApp.
// A Evolution grava o contato recebido (ou enviado pelo celular) como texto, no idioma dela:
//   *Contato:*\n\n_Nome:_ Daniel\n_Número (1):_ +55 62 9183-4188
// Nas recebidas a marcação vem trocada ("**Contato:**", "*Nome:*"; ver whatsappText.js).
// Vários contatos vêm separados por linha em branco. Nos grupos, o texto começa com quem
// enviou ("**+55 ... - Nome:**"). O contato enviado pelo Chatwoot (botão Contato) traz os
// dados prontos em content_attributes.outsider_contacts. Daqui sai a lista de cartões que o
// Message.vue desenha com o ContactCard.vue.
import { splitTypedContent, typeHeaderRegex } from './whatsappText';

const NAME = /^[_*](?:Nome|Name|Nombre):[_*]\s*(.*)$/;
const NUMBER = /^[_*](?:Número|Number|Numero)\s*\(\d+\):[_*]\s*(.*)$/;
const BLOCK_START = typeHeaderRegex('Contato|Contact|Contacto');

const digitsOf = phone => String(phone || '').replace(/\D/g, '');

const parseBlock = lines => {
  const card = { name: '', phones: [] };
  let valid = true;
  lines.forEach(line => {
    const name = line.match(NAME);
    const number = line.match(NUMBER);
    if (name) card.name = name[1].trim();
    else if (number) card.phones.push(number[1].trim());
    else if (line.trim()) valid = false;
  });
  return valid && card.name ? card : null;
};

// devolve null quando o texto não é só contatos (aí fica a bolha de texto normal)
export const parseContactText = content => {
  const { header, body } = splitTypedContent(content, BLOCK_START);
  if (!body || !BLOCK_START.test(body.split('\n')[0].trim())) return null;

  const blocks = [];
  body.split('\n').forEach(raw => {
    const line = raw.trim();
    if (BLOCK_START.test(line)) blocks.push([]);
    else if (line) blocks[blocks.length - 1].push(line);
  });
  const cards = blocks.map(parseBlock);
  if (!cards.length || cards.some(card => !card)) return null;
  return { header, cards };
};

export const contactCardsOf = ({ content, contentAttributes } = {}) => {
  const sent = contentAttributes?.outsiderContacts;
  if (Array.isArray(sent) && sent.length) {
    const { header } = splitTypedContent(content, BLOCK_START);
    return {
      header,
      cards: sent.map(card => ({
        name: card.name,
        phones: [card.phone].filter(Boolean),
        company: card.company,
        email: card.email,
      })),
    };
  }
  return parseContactText(content);
};

export const isContactCardMessage = props =>
  !props.private && !props.attachments?.length && !!contactCardsOf(props);

export const phoneDigits = digitsOf;
