<script setup>
// OUTSIDER: pergunta o motivo ao soltar um card em "Perdido" no Kanban.
// O motivo só é obrigatório quando a conta tem motivos de perda ativos (mesma regra do backend).
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  lostReasons: { type: Array, required: true },
});

const emit = defineEmits(['confirm', 'cancel']);

const { t } = useI18n();

const dialogRef = ref(null);
const opportunity = ref(null);
const reasonId = ref('');
let confirmed = false;

const options = computed(() =>
  props.lostReasons
    .filter(reason => reason.active && reason.kind !== 'forward')
    .map(reason => ({ value: reason.id, label: reason.name }))
);

const isValid = computed(() => !options.value.length || !!reasonId.value);

const open = item => {
  opportunity.value = item;
  reasonId.value = '';
  confirmed = false;
  dialogRef.value?.open();
};

const confirm = () => {
  if (!isValid.value) return;
  confirmed = true;
  emit('confirm', opportunity.value, reasonId.value || null);
  dialogRef.value?.close();
};

const onClose = () => {
  if (!confirmed) emit('cancel', opportunity.value);
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_CRM.BOARD.LOST_TITLE', { title: opportunity?.title })"
    :description="t('OUTSIDER_CRM.BOARD.LOST_DESCRIPTION')"
    :confirm-button-label="t('OUTSIDER_CRM.BOARD.MARK_LOST')"
    :disable-confirm-button="!isValid"
    @confirm="confirm"
    @close="onClose"
  >
    <label v-if="options.length" class="flex flex-col gap-1">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.OPPORTUNITY.LOST_REASON') }}
      </span>
      <Select
        v-model="reasonId"
        :options="options"
        :placeholder="t('OUTSIDER_CRM.BOARD.CHOOSE_REASON')"
        class="!w-full [&>select]:w-full"
      />
    </label>
  </Dialog>
</template>
