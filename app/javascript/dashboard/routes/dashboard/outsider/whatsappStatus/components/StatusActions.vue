<script setup>
// OUTSIDER: ações de um dos meus status (ver, copiar texto, editar, republicar e baixar).
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Button from 'dashboard/components-next/button/Button.vue';
import { canRepublish, hasMedia } from '../helpers';

const props = defineProps({
  status: { type: Object, required: true },
  // o que o usuário pode fazer (ver Outsider::WhatsappStatusPermissions)
  can: { type: Object, default: () => ({}) },
  downloading: { type: Boolean, default: false },
});

const emit = defineEmits(['view', 'edit', 'republish', 'download']);

const { t } = useI18n();

const copyText = async () => {
  await copyTextToClipboard(props.status.text);
  useAlert(t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.COPIED'));
};
</script>

<template>
  <div class="flex items-center flex-shrink-0 gap-0.5">
    <Button
      v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.VIEW')"
      icon="i-lucide-eye"
      size="xs"
      variant="ghost"
      color="slate"
      :disabled="status.deleted"
      @click="emit('view')"
    />
    <Button
      v-if="status.text"
      v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.COPY_TEXT')"
      icon="i-lucide-copy"
      size="xs"
      variant="ghost"
      color="slate"
      @click="copyText"
    />
    <Button
      v-if="can.edit"
      v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.EDIT')"
      icon="i-lucide-pencil"
      size="xs"
      variant="ghost"
      color="slate"
      :disabled="!canRepublish(status)"
      @click="emit('edit')"
    />
    <Button
      v-if="can.republish"
      v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.REPUBLISH')"
      icon="i-lucide-repeat-2"
      size="xs"
      variant="ghost"
      color="slate"
      :disabled="!canRepublish(status)"
      @click="emit('republish')"
    />
    <Button
      v-if="can.download && hasMedia(status)"
      v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.DOWNLOAD')"
      icon="i-lucide-download"
      size="xs"
      variant="ghost"
      color="slate"
      :disabled="status.deleted"
      :is-loading="downloading"
      @click="emit('download')"
    />
  </div>
</template>
