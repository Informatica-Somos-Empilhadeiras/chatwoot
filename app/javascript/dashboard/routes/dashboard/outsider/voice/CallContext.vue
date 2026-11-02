<script setup>
// OUTSIDER: o cliente da ligação no telefone (Entrega 26): por onde passou na URA, o cadastro (abrir ou, para
// número desconhecido, cadastrar na hora com o número da ligação) e o negócio do CRM vinculado à ligação
// (trocar, vincular ou desvincular durante a conversa; a ligação entra na linha do tempo do negócio).
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DealPicker from './DealPicker.vue';
import IvrTrail from './IvrTrail.vue';
import { useCallInfo } from './useCallInfo';
import { nationalNumber } from './brazil';
import { linkCallContact, linkCallDeal } from './phone';
import { crmState } from '../crm/crmStore';

const { t } = useI18n();
const {
  call,
  contact,
  deals,
  linkedDeal,
  ivr,
  conversationId,
  openDeal,
  openContact,
  openConversation,
} = useCallInfo();

const picking = ref(false);
const creating = ref(false);
const contactName = ref('');
const busy = ref(false);

const external = computed(() => (call.value?.number || '').length > 4);
const national = computed(() => nationalNumber(call.value?.number));
const crmEnabled = computed(() => crmState.access.enabled);

const pickDeal = async deal => {
  busy.value = true;
  const error = await linkCallDeal(deal);
  busy.value = false;
  if (error) {
    useAlert(t('OUTSIDER_VOICE.DEAL_LINK.FAILED'));
    return;
  }
  picking.value = false;
  useAlert(
    deal
      ? t('OUTSIDER_VOICE.DEAL_LINK.LINKED', { title: deal.title })
      : t('OUTSIDER_VOICE.DEAL_LINK.UNLINKED')
  );
};

// número brasileiro vira +55 (o formato do Chatwoot); o resto vai como chegou, com o "+"
const createContact = async () => {
  const name = contactName.value.trim();
  if (!name || busy.value) return;
  busy.value = true;
  try {
    const phoneNumber = national.value
      ? `+55${national.value}`
      : `+${call.value.number.replace(/\D/g, '')}`;
    const { data } = await ContactAPI.create({
      name,
      phone_number: phoneNumber,
    });
    const created = data.payload?.contact || data.payload || data;
    await linkCallContact(created.id);
    creating.value = false;
    contactName.value = '';
    useAlert(t('OUTSIDER_VOICE.CALL.CONTACT_CREATED'));
    openContact(created.id);
  } catch {
    useAlert(t('OUTSIDER_VOICE.CALL.CONTACT_FAILED'));
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <div
    v-if="call && external"
    class="flex flex-col gap-2"
    data-testid="outsider-call-context"
  >
    <IvrTrail :ivr="ivr" compact />

    <!-- cadastro do cliente -->
    <div class="flex flex-wrap justify-center gap-1.5">
      <button
        v-if="contact"
        type="button"
        class="flex items-center gap-1.5 px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
        data-testid="outsider-call-open-contact"
        @click="openContact()"
      >
        <Icon icon="i-lucide-contact-round" class="size-3.5 text-n-slate-11" />
        {{ t('OUTSIDER_VOICE.CALL.OPEN_CONTACT') }}
      </button>
      <button
        v-else-if="!creating"
        type="button"
        class="flex items-center gap-1.5 px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
        data-testid="outsider-call-create-contact"
        @click="creating = true"
      >
        <Icon icon="i-lucide-user-plus" class="size-3.5 text-n-slate-11" />
        {{ t('OUTSIDER_VOICE.CALL.CREATE_CONTACT') }}
      </button>
      <button
        v-if="conversationId"
        type="button"
        class="flex items-center gap-1.5 px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
        @click="openConversation"
      >
        <Icon icon="i-lucide-message-circle" class="size-3.5 text-n-slate-11" />
        {{ t('OUTSIDER_VOICE.CALL.OPEN_CONVERSATION') }}
      </button>
    </div>
    <form
      v-if="creating && !contact"
      class="flex items-center gap-1.5"
      @submit.prevent="createContact"
    >
      <input
        v-model="contactName"
        autocomplete="off"
        maxlength="100"
        :placeholder="t('OUTSIDER_VOICE.CALL.CONTACT_NAME')"
        class="flex-1 min-w-0 !mb-0 h-9 px-3 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
        data-testid="outsider-call-contact-name"
      />
      <Button
        type="submit"
        sm
        :label="t('OUTSIDER_VOICE.CALL.SAVE_CONTACT')"
        :is-loading="busy"
        :disabled="!contactName.trim()"
      />
      <Button
        type="button"
        sm
        ghost
        slate
        icon="i-lucide-x"
        @click="creating = false"
      />
    </form>

    <!-- negócio vinculado -->
    <template v-if="crmEnabled">
      <div
        v-if="!picking"
        class="flex items-center justify-center gap-1.5 text-xs"
        data-testid="outsider-call-deal"
      >
        <button
          v-if="linkedDeal"
          type="button"
          class="flex items-center min-w-0 gap-1.5 px-2.5 py-1.5 rounded-lg bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12"
          :title="t('OUTSIDER_VOICE.CALL.OPEN_DEAL')"
          @click="openDeal(linkedDeal.id)"
        >
          <Icon icon="i-lucide-kanban" class="size-3.5 text-n-slate-11" />
          <span class="truncate">{{ linkedDeal.title }}</span>
        </button>
        <button
          type="button"
          class="flex items-center gap-1 px-2 py-1.5 rounded-lg text-n-blue-11 hover:bg-n-alpha-2"
          data-testid="outsider-call-link-deal"
          @click="picking = true"
        >
          <Icon icon="i-lucide-link" class="size-3.5" />
          {{
            linkedDeal
              ? t('OUTSIDER_VOICE.DEAL_LINK.CHANGE')
              : t('OUTSIDER_VOICE.DEAL_LINK.LINK')
          }}
        </button>
      </div>
      <DealPicker
        v-else
        :suggestions="deals"
        :current="linkedDeal"
        :busy="busy"
        @pick="pickDeal"
        @cancel="picking = false"
      />
    </template>
  </div>
</template>
