// OUTSIDER: reações, edição e encaminhamento das mensagens do WhatsApp (Entrega 21). As reações e as
// edições chegam da Evolution como mensagens novas; o servidor marca (Outsider::WhatsappMessageEcho) e a
// lista esconde essas mensagens: a reação vira o emoji no balão reagido e a edição já mudou o texto da
// original. As mensagens aqui estão em camelCase (vêm do MessageList.vue).

export const EVOLUTION_WEBHOOK = /\/chatwoot\/webhook\//;
export const QUICK_REACTIONS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
// o WhatsApp só aceita editar até 15 minutos depois do envio
export const EDIT_WINDOW_SECONDS = 15 * 60;

const OUTGOING = 1;

export const isEvolutionInbox = inbox =>
  inbox?.channel_type === 'Channel::Api' &&
  EVOLUTION_WEBHOOK.test(inbox.webhook_url || '');

export const isHiddenEcho = message =>
  Boolean(
    message.contentAttributes?.outsiderReaction ||
      message.contentAttributes?.outsiderEditOf
  );

// quem reagiu: a empresa (mensagem enviada), o participante do grupo (vem da Evolution) ou o contato
const reactorOf = (message, reaction) => {
  if (message.messageType === OUTGOING) return { key: 'me', isMe: true };
  const { from } = reaction;
  if (from) {
    return {
      key: from.jid || from.phone || from.name,
      name: from.name || '',
      phone: from.phone || '',
    };
  }
  return {
    key: `contact-${message.senderId ?? message.sender?.id ?? message.id}`,
    name: message.sender?.name || '',
    phone: message.sender?.phoneNumber || '',
    thumbnail: message.sender?.thumbnail || '',
  };
};

/**
 * Reações por mensagem reagida: Map(id da mensagem => [{ key, emoji, name, phone, isMe, createdAt }]).
 * Vale a última reação de cada pessoa (trocar o emoji troca a reação); a removida sai.
 */
export const collectReactions = messages => {
  const byTarget = new Map();
  messages
    .filter(message => message.contentAttributes?.outsiderReaction)
    .sort((a, b) => a.createdAt - b.createdAt || a.id - b.id)
    .forEach(message => {
      const targetId = message.contentAttributes.inReplyTo;
      if (!targetId) return;
      const reaction = message.contentAttributes.outsiderReaction;
      const reactor = reactorOf(message, reaction);
      const people = byTarget.get(targetId) || new Map();
      if (reaction.removed) {
        people.delete(reactor.key);
      } else {
        people.set(reactor.key, {
          ...reactor,
          emoji: reaction.emoji,
          createdAt: message.createdAt,
        });
      }
      byTarget.set(targetId, people);
    });

  const result = new Map();
  byTarget.forEach((people, targetId) => {
    if (people.size) result.set(targetId, [...people.values()]);
  });
  return result;
};

// emojis na ordem de quem tem mais reações, com a contagem
export const reactionSummary = reactions => {
  const counts = new Map();
  reactions.forEach(({ emoji }) =>
    counts.set(emoji, (counts.get(emoji) || 0) + 1)
  );
  return [...counts.entries()]
    .map(([emoji, count]) => ({ emoji, count }))
    .sort((a, b) => b.count - a.count);
};

// "5562999990002" -> "+55 62 99999-0002"
export const formatWhatsappPhone = phone => {
  const digits = String(phone || '').replace(/\D/g, '');
  const match = digits.match(/^55(\d{2})(\d{4,5})(\d{4})$/);
  if (!match) return digits ? `+${digits}` : '';
  return `+55 ${match[1]} ${match[2]}-${match[3]}`;
};
