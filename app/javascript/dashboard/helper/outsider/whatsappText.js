// OUTSIDER: textos que a Evolution grava no lugar de contato e localização ("*Contato:*", "_Nome:_ ...").
// Nas mensagens recebidas (e nas enviadas pelo celular) ela troca a marcação do WhatsApp pela do
// Chatwoot: *negrito* vira **negrito** e _itálico_ vira *itálico*. Então "*Contato:*" chega como
// "**Contato:**" e "_Nome:_" como "*Nome:*". Os leitores aceitam as duas formas.
import { splitSenderHeader } from './mediaAlbum';

// "*Rótulo:*" ou "**Rótulo:**" sozinho na linha
export const typeHeaderRegex = words =>
  new RegExp(`^\\*{1,2}(?:${words})[^*:]*:\\*{1,2}$`, 'i');

// "_Rótulo:_ valor" ou "*Rótulo:* valor"
export const FIELD = /^[_*]([^:_*]+):[_*]\s*(.*)$/;

// Separa quem enviou (grupos) do resto. Sem grupo, o "**Contato:**" do começo parece o cabeçalho
// de quem enviou; nesse caso ele volta para o texto.
export const splitTypedContent = (content, typeHeader) => {
  const split = splitSenderHeader(content);
  if (split.header && typeHeader.test(`**${split.header}:**`)) {
    return { header: null, body: String(content || '').trim() };
  }
  return split;
};
