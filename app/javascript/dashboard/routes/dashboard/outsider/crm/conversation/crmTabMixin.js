// OUTSIDER: aba "CRM" no ConversationBox.vue (Options API, por isso um mixin). Entra depois das
// abas de Dashboard Apps, com o número de negócios abertos do contato no selo. O painel do
// contato pede para abrir a aba pelo evento OPEN_CRM_TAB_EVENT.
import { defineAsyncComponent } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import {
  OPEN_CRM_TAB_EVENT,
  crmState,
  ensureCrmContext,
  loadContactSummary,
  summaryKey,
} from '../crmStore';
import { formatMoneyShort } from '../helpers';

// o componente vai registrado no próprio ConversationBox (o lint não enxerga componentes de mixin);
// carregado só quando a aba é aberta, para não pesar a tela de conversas
export const CrmConversationTab = defineAsyncComponent(
  () => import('./CrmConversationTab.vue')
);

export default {
  computed: {
    outsiderCrmSummary() {
      const contactId = this.currentChat?.meta?.sender?.id;
      return crmState.summaries[summaryKey(contactId, this.currentChat?.id)];
    },
    outsiderCrmTabs() {
      const summary = this.outsiderCrmSummary;
      // grupos do WhatsApp não têm negócio: sem aba
      if (!crmState.access.enabled || !this.currentChat?.id || summary?.group) {
        return [];
      }
      const value = summary?.open_value_cents;
      return [
        {
          key: 'outsider-crm',
          index: this.dashboardApps.length + 1,
          name: value
            ? `${this.$t('OUTSIDER_CRM.CONVERSATION.TAB')} · ${formatMoneyShort(value)}`
            : this.$t('OUTSIDER_CRM.CONVERSATION.TAB'),
          count: summary?.open_count || 0,
          showBadge: !!summary?.open_count,
        },
      ];
    },
    outsiderCrmTabActive() {
      const [tab] = this.outsiderCrmTabs;
      return !!tab && this.activeIndex === tab.index;
    },
  },
  watch: {
    'currentChat.id': {
      immediate: true,
      handler() {
        const contactId = this.currentChat?.meta?.sender?.id;
        loadContactSummary(contactId, this.currentChat?.id).catch(() => {});
      },
    },
  },
  mounted() {
    ensureCrmContext();
    emitter.on(OPEN_CRM_TAB_EVENT, this.outsiderOpenCrmTab);
  },
  beforeUnmount() {
    emitter.off(OPEN_CRM_TAB_EVENT, this.outsiderOpenCrmTab);
  },
  methods: {
    outsiderOpenCrmTab() {
      const [tab] = this.outsiderCrmTabs;
      if (tab) this.activeIndex = tab.index;
    },
  },
};
