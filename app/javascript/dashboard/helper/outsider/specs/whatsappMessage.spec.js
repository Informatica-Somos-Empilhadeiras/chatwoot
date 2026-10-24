import {
  collectReactions,
  formatWhatsappPhone,
  isEvolutionInbox,
  isHiddenEcho,
  reactionSummary,
} from '../whatsappMessage';

const reaction = (id, emoji, extra = {}) => ({
  id,
  messageType: 0,
  createdAt: id,
  senderId: 7,
  sender: { id: 7, name: 'Ana', phoneNumber: '+5562999990001' },
  contentAttributes: { inReplyTo: 1, outsiderReaction: { emoji } },
  ...extra,
});

describe('whatsappMessage', () => {
  it('recognizes the Evolution inbox by its webhook', () => {
    expect(
      isEvolutionInbox({
        channel_type: 'Channel::Api',
        webhook_url: 'http://evolution:8080/chatwoot/webhook/CENTRAL',
      })
    ).toBe(true);
    expect(
      isEvolutionInbox({
        channel_type: 'Channel::Api',
        webhook_url: 'https://example.com',
      })
    ).toBe(false);
  });

  it('hides reactions and the Evolution copy of edits', () => {
    expect(isHiddenEcho(reaction(2, '👍'))).toBe(true);
    expect(isHiddenEcho({ contentAttributes: { outsiderEditOf: 1 } })).toBe(
      true
    );
    expect(isHiddenEcho({ contentAttributes: {} })).toBe(false);
  });

  it('keeps the last reaction of each person and drops removed ones', () => {
    const groupFrom = from => ({
      contentAttributes: {
        inReplyTo: 1,
        outsiderReaction: { emoji: '❤️', from },
      },
    });
    const messages = [
      reaction(2, '👍'),
      reaction(3, '😂'),
      reaction(4, '❤️', groupFrom({ jid: 'b@s.whatsapp.net', name: 'Bruno' })),
      reaction(5, '🙏', { messageType: 1 }),
      reaction(6, '🙏', {
        messageType: 1,
        contentAttributes: {
          inReplyTo: 1,
          outsiderReaction: { emoji: '🙏', removed: true },
        },
      }),
    ];

    const reactions = collectReactions(messages).get(1);

    expect(reactions.map(item => [item.name, item.emoji])).toEqual([
      ['Ana', '😂'],
      ['Bruno', '❤️'],
    ]);
  });

  it('counts each emoji, the most used first', () => {
    expect(
      reactionSummary([{ emoji: '👍' }, { emoji: '❤️' }, { emoji: '❤️' }])
    ).toEqual([
      { emoji: '❤️', count: 2 },
      { emoji: '👍', count: 1 },
    ]);
  });

  it('formats the participant number', () => {
    expect(formatWhatsappPhone('5562999990002')).toBe('+55 62 99999-0002');
    expect(formatWhatsappPhone('14155550100')).toBe('+14155550100');
  });
});
