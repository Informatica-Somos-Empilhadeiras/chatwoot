// OUTSIDER: mensagens do bot na conversa. O menu que o bot mandou (content_attributes.outsider_bot,
// ver Outsider::Bot::Sender) aparece como o cliente vê no WhatsApp; a escolha do cliente na lista ou
// no botão (a Evolution grava "*List Response:*\n\n_Title_: ...\n_ID_: ...") aparece só com a opção.
const RESPONSE = /^[\W_]*(List|Button|Lista|Bot[aã]o)\s*(Response|Resposta)/i;
const TITLE = /(?:^|\n)[\W_]*(?:Title|T[ií]tulo)[\W_]*:\s*([^\n]+)/i;
const DESCRIPTION =
  /(?:^|\n)[\W_]*(?:Description|Descri[cç][aã]o)[\W_]*:\s*([^\n]+)/i;

// tira só a marcação das pontas
const clean = value =>
  String(value || '')
    .trim()
    .replace(/^[*_~]+|[*_~]+$/g, '')
    .trim();

export const botMenuOf = ({ contentAttributes }) => {
  const bot = contentAttributes?.outsiderBot || contentAttributes?.outsider_bot;
  if (bot?.kind !== 'menu' || bot.style === 'text' || !bot.options?.length) {
    return null;
  }
  return {
    text: bot.text || '',
    title: bot.title || '',
    footer: bot.footer || '',
    menuStyle: bot.style,
    buttonLabel: bot.buttonLabel || bot.button_label || '',
    options: bot.options,
  };
};

export const menuReplyOf = content => {
  const text = String(content || '');
  const header = text.match(RESPONSE);
  const title = header && text.match(TITLE)?.[1];
  if (!title) return null;
  return {
    kind: /button|bot/i.test(header[1]) ? 'button' : 'list',
    title: clean(title),
    description: clean(text.match(DESCRIPTION)?.[1]),
  };
};

export const isBotMenuMessage = props =>
  !props.private &&
  !props.attachments?.length &&
  (!!botMenuOf(props) || !!menuReplyOf(props.content));
