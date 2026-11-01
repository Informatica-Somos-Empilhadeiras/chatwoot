// OUTSIDER: clicar na foto/nome no cabeçalho da conversa abre (ou fecha) o painel do contato,
// como no WhatsApp e no Telegram. Faz o mesmo que o botão do canto (SidepanelSwitch.vue).
import { useUISettings } from 'dashboard/composables/useUISettings';

export const useContactPanelToggle = () => {
  const { uiSettings, updateUISettings } = useUISettings();

  const toggleContactPanel = event => {
    // botões e links dentro do cabeçalho (voltar, copiar o número da conversa) seguem iguais
    if (event?.target?.closest?.('button, a, input')) return;
    const isOpen = !!uiSettings.value.is_contact_sidebar_open;
    updateUISettings({
      is_contact_sidebar_open: !isOpen,
      is_copilot_panel_open: false,
    });
  };

  return { toggleContactPanel };
};
