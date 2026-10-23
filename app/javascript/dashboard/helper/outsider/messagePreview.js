// OUTSIDER: prévia da lista de conversas para contato e localização do WhatsApp:
// "👤 Daniel" e "📍 Somos - Matriz" no lugar de "Contato: Nome: ..." e "Localização: Latitude: ...".
// Recebe a mensagem como vem da lista (snake_case).
import { contactCardsOf } from './contactCard';
import { locationPreview } from './location';

export const outsiderPreview = message => {
  if (!message?.content || message.private) return null;
  const attributes = message.content_attributes || {};
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
