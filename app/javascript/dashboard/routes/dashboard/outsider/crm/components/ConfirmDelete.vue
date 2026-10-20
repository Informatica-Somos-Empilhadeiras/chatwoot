<script setup>
// OUTSIDER: confirmação antes de apagar algo do CRM. Quem chama passa o título, o texto e a ação;
// se a API recusar (ver Outsider::Crm::Remover), o aviso diz o que impede e o diálogo continua aberto.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { errorMessage } from '../helpers';

const { t } = useI18n();

const dialogRef = ref(null);
const isLoading = ref(false);
const state = ref({ title: '', description: '', action: null });

const open = (title, description, action) => {
  state.value = { title, description, action };
  dialogRef.value?.open();
};

const confirm = async () => {
  isLoading.value = true;
  try {
    await state.value.action();
    dialogRef.value?.close();
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="state.title"
    :description="state.description"
    :confirm-button-label="t('OUTSIDER_CRM.DELETE.CONFIRM')"
    :is-loading="isLoading"
    @confirm="confirm"
  />
</template>
