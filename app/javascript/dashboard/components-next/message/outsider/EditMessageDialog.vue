<script setup>
// OUTSIDER: editar uma mensagem enviada pelo WhatsApp (Entrega 21). Aberta pelo menu da mensagem (evento
// OUTSIDER_EDIT_MESSAGE); o texto muda no WhatsApp do cliente e aqui, com "Editada" no balão. O WhatsApp só
// aceita até 15 minutos depois do envio (ver app/services/outsider/whatsapp_message_actions.rb).
import { computed, ref, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import WhatsappMessagesAPI from 'dashboard/api/outsider/whatsappMessages';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const MAX_LENGTH = 4096;

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const message = ref(null);
const text = ref('');
const isSaving = ref(false);

const changed = computed(
  () =>
    text.value.trim() && text.value.trim() !== message.value?.content?.trim()
);

const open = data => {
  message.value = data;
  text.value = data.content || '';
  dialogRef.value?.open();
};

const errorMessage = error => {
  const code = error?.response?.data?.error;
  const key = `OUTSIDER_WHATSAPP.EDIT.ERRORS.${String(code || '').toUpperCase()}`;
  if (code && t(key) !== key) return t(key);
  return (
    error?.response?.data?.message || t('OUTSIDER_WHATSAPP.EDIT.ERRORS.DEFAULT')
  );
};

const save = async () => {
  if (!changed.value || isSaving.value) return;
  isSaving.value = true;
  try {
    const { data } = await WhatsappMessagesAPI.edit(
      message.value.id,
      text.value.trim()
    );
    store.dispatch('updateMessage', data.message);
    dialogRef.value?.close();
    useAlert(t('OUTSIDER_WHATSAPP.EDIT.DONE'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSaving.value = false;
  }
};

onMounted(() => emitter.on('OUTSIDER_EDIT_MESSAGE', open));
onUnmounted(() => emitter.off('OUTSIDER_EDIT_MESSAGE', open));
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_WHATSAPP.EDIT.TITLE')"
    :description="t('OUTSIDER_WHATSAPP.EDIT.DESCRIPTION')"
    :confirm-button-label="t('OUTSIDER_WHATSAPP.EDIT.SAVE')"
    :disable-confirm-button="!changed"
    :is-loading="isSaving"
    width="md"
    @confirm="save"
  >
    <textarea
      v-model="text"
      rows="4"
      :maxlength="MAX_LENGTH"
      class="w-full !mb-0 px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
      data-edit-message
      @keydown.enter.exact.prevent="save"
    />
  </Dialog>
</template>
