<script setup>
// OUTSIDER: aviso dentro da aba quando a lista (tarefas, linha do tempo, auditoria) não carrega,
// com o motivo e um botão para tentar de novo.
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  message: { type: String, required: true },
});

const emit = defineEmits(['retry']);

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-2 px-3 py-3 text-sm rounded-lg bg-n-ruby-2 text-n-ruby-11 outline outline-1 -outline-offset-1 outline-n-ruby-5"
  >
    <Icon icon="i-lucide-circle-alert" class="size-4 shrink-0" />
    <span class="flex-1 min-w-0">{{ message }}</span>
    <Button
      type="button"
      size="xs"
      variant="faded"
      color="ruby"
      icon="i-lucide-refresh-cw"
      :label="t('OUTSIDER_CRM.ERRORS.RETRY')"
      @click="emit('retry')"
    />
  </div>
</template>
