import { contactCardsOf, isContactCardMessage } from '../contactCard';
import { comparableNumber } from '../contactLookup';
import { isVoiceWithHeader, placeholderWaveform } from '../voiceNote';

describe('contactCard', () => {
  it('reads the contact text Evolution writes, in any of its languages', () => {
    expect(
      contactCardsOf({
        content:
          '*Contato:*\n\n_Nome:_ Daniel\n_Número (1):_ +55 62 9183-4188\n_Número (2):_ +55 62 3333-0000',
      })
    ).toEqual({
      header: null,
      cards: [
        { name: 'Daniel', phones: ['+55 62 9183-4188', '+55 62 3333-0000'] },
      ],
    });
    const many = contactCardsOf({
      content:
        '**+55 62 99999-0003 - Marcos:**\n\n*Contact:*\n\n_Name:_ Ana\n_Number (1):_ +1 555\n\n*Contact:*\n\n_Name:_ Bia\n_Number (1):_ +2 666',
    });
    expect(many.header).toBe('+55 62 99999-0003 - Marcos');
    expect(many.cards.map(card => card.name)).toEqual(['Ana', 'Bia']);
  });

  it('prefers the card data saved when the contact went out from Chatwoot', () => {
    expect(
      contactCardsOf({
        content: '*Contato:*\n\n_Nome:_ X',
        contentAttributes: {
          outsiderContacts: [
            { name: 'Daniel', phone: '+55 62 9183-4188', company: 'Somos' },
          ],
        },
      }).cards
    ).toEqual([
      {
        name: 'Daniel',
        phones: ['+55 62 9183-4188'],
        company: 'Somos',
        email: undefined,
      },
    ]);
  });

  it('leaves normal text, notes and attachments alone', () => {
    expect(isContactCardMessage({ content: 'Contato: Daniel' })).toBe(false);
    expect(
      isContactCardMessage({
        content: '*Contato:*\n\n_Nome:_ Daniel\nobrigado!',
      })
    ).toBe(false);
    expect(
      isContactCardMessage({
        content: '*Contato:*\n\n_Nome:_ Daniel',
        private: true,
      })
    ).toBe(false);
    expect(
      isContactCardMessage({
        content: '*Contato:*\n\n_Nome:_ Daniel',
        attachments: [{}],
      })
    ).toBe(false);
    expect(
      isContactCardMessage({ content: '*Contato:*\n\n_Nome:_ Daniel' })
    ).toBe(true);
  });

  it('matches Brazilian mobiles with and without the ninth digit', () => {
    expect(comparableNumber('+55 62 99183-4188')).toBe(
      comparableNumber('556291834188')
    );
    expect(comparableNumber('+1 555 0100')).toBe('15550100');
  });
});

describe('voiceNote', () => {
  it('keeps group voice notes as voice notes and draws a stable placeholder', () => {
    const audio = [{ fileType: 'audio' }];
    expect(
      isVoiceWithHeader({
        content: '**+55 62 9999 - Marcos:**',
        attachments: audio,
      })
    ).toBe(true);
    expect(
      isVoiceWithHeader({
        content: '**+55 62 9999 - Marcos:** oi',
        attachments: audio,
      })
    ).toBe(false);
    expect(isVoiceWithHeader({ content: '', attachments: audio })).toBe(false);
    expect(placeholderWaveform(42)).toEqual(placeholderWaveform(42));
    expect(placeholderWaveform(42)).toHaveLength(44);
  });
});
