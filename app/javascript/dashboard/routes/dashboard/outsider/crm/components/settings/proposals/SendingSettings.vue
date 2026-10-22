<script setup>
// OUTSIDER: textos que abrem a janela de envio da proposta (mensagem e assunto do e-mail, com campos
// trocados na hora) e se a proposta aceita marca o negócio ligado como ganho (desligado de início).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { settingsError } from './proposalSettings';

const props = defineProps({
  settings: { type: Object, required: true },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();

const fromSettings = () => ({
  send_message: props.settings.send_texts?.send_message || '',
  email_subject: props.settings.send_texts?.email_subject || '',
  win_deal_on_accept: !!props.settings.win_deal_on_accept,
});

const form = ref(fromSettings());
const isSaving = ref(false);

watch(
  () => props.settings,
  () => {
    form.value = fromSettings();
  }
);

const isDirty = computed(
  () => JSON.stringify(form.value) !== JSON.stringify(fromSettings())
);

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateProposalGeneral(form.value);
    emit('updated', data);
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.SENDING.SAVED'));
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="save">
    <p class="mb-0 text-sm text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.SENDING.DESCRIPTION') }}
    </p>
    <label class="flex flex-col gap-1 text-xs">
      <span class="text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.SENDING.MESSAGE') }}
      </span>
      <textarea
        v-model="form.send_message"
        rows="3"
        maxlength="2000"
        :placeholder="settings.default_send_texts?.send_message"
        class="!mb-0 !text-sm rounded-lg"
      />
    </label>
    <label class="flex flex-col gap-1 text-xs">
      <span class="text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.SENDING.SUBJECT') }}
      </span>
      <input
        v-model="form.email_subject"
        type="text"
        maxlength="200"
        :placeholder="settings.default_send_texts?.email_subject"
        class="!mb-0 !text-sm rounded-lg"
      />
    </label>
    <p class="-mt-2 mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.SENDING.VARIABLES') }}
    </p>
    <div class="flex items-start gap-3 p-3 rounded-xl bg-n-alpha-1">
      <Switch v-model="form.win_deal_on_accept" class="mt-0.5" />
      <div class="flex flex-col gap-0.5">
        <span class="text-sm text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.SENDING.WIN_ON_ACCEPT') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.SENDING.WIN_ON_ACCEPT_HELP') }}
        </span>
      </div>
    </div>
    <div class="flex justify-end">
      <Button
        type="submit"
        size="sm"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="!isDirty"
      />
    </div>
  </form>
</template>
