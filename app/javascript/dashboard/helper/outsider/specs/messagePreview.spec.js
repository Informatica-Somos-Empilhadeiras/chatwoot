import { outsiderPreview } from '../messagePreview';

describe('outsiderPreview', () => {
  it('shows the place and contact names in the conversation list', () => {
    expect(
      outsiderPreview({
        content:
          '**Localização:**\n\n*Latitude:* 1 \n*Longitude:* 2 \n*Nome:* Matriz\n',
      })
    ).toBe('📍 Matriz');
    expect(
      outsiderPreview({
        content:
          '**Contato:**\n\n*Nome:* Daniel\n*Número (1):* +55 62 9183-4188\n\n**Contato:**\n\n*Nome:* Ana\n*Número (1):* +55 11 98888-7777',
      })
    ).toBe('👤 Daniel +1');
    expect(outsiderPreview({ content: 'Bom dia' })).toBeNull();
    expect(
      outsiderPreview({ content: '\n\n`Mensagem editada:`\n\nBom dia a todos' })
    ).toBe('✏️ Bom dia a todos');
    expect(
      outsiderPreview({
        content: '*Contato:*\n\n_Nome:_ X\n_Número (1):_ 1',
        private: true,
      })
    ).toBeNull();
  });
});
