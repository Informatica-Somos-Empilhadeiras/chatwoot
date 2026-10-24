import { evolutionNoticeOf } from '../evolutionNotice';

describe('evolutionNoticeOf', () => {
  it('recognizes the invalid number notice in any Evolution language', () => {
    [
      '🚨 A mensagem não foi enviada, pois o contato não é um número válido do WhatsApp.',
      '🚨 The message was not sent as the contact is not a valid Whatsapp number.',
    ].forEach(content => {
      expect(evolutionNoticeOf({ content })).toMatchObject({
        type: 'NUMBER_NOT_ON_WHATSAPP',
        level: 'error',
      });
    });
  });

  it('keeps the reason of a sending error and knows the common ones', () => {
    expect(
      evolutionNoticeOf({
        content:
          '🚨 Não foi possível enviar a mensagem. Verifique sua conexão. _Error: Connection Closed_',
      })
    ).toMatchObject({
      type: 'NOT_SENT',
      detail: 'Error: Connection Closed',
      detailKey: 'CONNECTION_CLOSED',
    });
  });

  it('reads the instance and the state of connection notices', () => {
    expect(
      evolutionNoticeOf({ content: '⚠️ CENTRAL instance status: *open*.' })
    ).toMatchObject({
      type: 'INSTANCE_STATUS',
      level: 'info',
      inbox: 'CENTRAL',
      state: 'open',
    });
    expect(
      evolutionNoticeOf({
        content: '🚨 Instância *CENTRAL* desconectada do WhatsApp.',
      })
    ).toMatchObject({ type: 'DISCONNECTED', inbox: 'CENTRAL' });
  });

  it('ignores normal messages and messages with files', () => {
    expect(evolutionNoticeOf({ content: 'Bom dia!' })).toBeNull();
    expect(
      evolutionNoticeOf({
        content: '🚀 Conectado com sucesso!',
        attachments: [{ id: 1 }],
      })
    ).toBeNull();
  });
});
