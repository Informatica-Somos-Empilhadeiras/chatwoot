// OUTSIDER: prévia da lista de conversas para contato, localização e edição do WhatsApp:
// "👤 Daniel", "📍 Somos - Matriz" e "✏️ texto novo" no lugar de "Contato: Nome: ...",
// "Localização: Latitude: ..." e "`Mensagem editada:` ...".
// Recebe a mensagem como vem da lista (snake_case).
import { contactCardsOf } from './contactCard';
import { locationPreview } from './location';

// edição que a Evolution manda como mensagem ("`Mensagem editada:` texto"), Entrega 21
const EDIT_PREFIX =
  /^\s*`(?:Mensagem editada|Edited Message|Mensaje editado):`\s*/;

export const outsiderPreview = message => {
  if (!message?.content || message.private) return null;
  const attributes = message.content_attributes || {};
  if (EDIT_PREFIX.test(message.content)) {
    return `✏️ ${message.content.replace(EDIT_PREFIX, '').trim()}`;
  }
  const location = locationPreview({
    content: message.content,
    contentAttributes: { outsiderLocation: attributes.outsider_location },
  });
  if (location) return location;

  const contacts = contactCardsOf({
    content: message.content,
    contentAttributes: { outsiderContacts: attributes.outsider_contacts },
  });
  if (!contacts?.cards.length) return null;
  const [first, ...others] = contacts.cards;
  return `👤 ${first.name}${others.length ? ` +${others.length}` : ''}`;
};
