// OUTSIDER: o que o botão do telefone faz, no computador/tablet (voice/PhoneFab.vue, canto inferior
// esquerdo) e no celular (responsive/MobileTabbar.vue, meio da barra de baixo).
// - Agente: o botão abre o teclado do telefone (PhonePanel) ou mostra a janela própria dele.
// - Administrador: o botão abre um menu com "Ligar" e os painéis da Telefonia (Painel, Ligações,
//   Gravações, URA, Configurações), os mesmos do item Telefonia do menu lateral.
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { crmState } from '../crm/crmStore';
import { VOICE_ROUTE, voiceSections } from './sections';
import {
  phone,
  panel,
  setPanelOpen,
  showPopout,
  askNotifications,
} from './phone';

// cor do pontinho de estado (classes do Tailwind)
export const PHONE_DOT = {
  ready: 'bg-n-teal-9',
  in_call: 'bg-n-teal-9 animate-pulse',
  connecting: 'bg-n-amber-9',
  offline: 'bg-n-ruby-9',
  failed: 'bg-n-ruby-9',
  other_tab: 'bg-n-slate-8',
};

export const phoneState = () =>
  phone.call && phone.call.state !== 'ended' ? 'in_call' : phone.status;

// abre (ou mostra) o telefone: o painel fixo na tela ou a janela própria
export const revealPhone = (open = true) => {
  askNotifications();
  if (phone.popout && !phone.holder) showPopout();
  else setPanelOpen(open);
};

export const togglePhone = () => revealPhone(!panel.open);

// painéis da Telefonia que o administrador vê no menu do botão (vazio para agentes e com a
// telefonia desligada), já com a rota de cada um
export const usePhonePanels = () => {
  const { isAdmin } = useAdmin();
  const route = useRoute();
  const panels = computed(() =>
    isAdmin.value
      ? voiceSections(crmState.access).map(section => ({
          key: section.key,
          icon: section.icon,
          label: section.label,
          to: {
            name: VOICE_ROUTE,
            params: { accountId: route.params.accountId, tab: section.key },
          },
        }))
      : []
  );
  return { isAdmin, panels };
};
