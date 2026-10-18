<script setup>
// OUTSIDER: republicar meus status (um ou vários) como status novos.
import { ref, reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappStatusAPI from 'dashboard/api/outsider/whatsappStatus';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import StatusColorPicker from './StatusColorPicker.vue';
import StatusAudiencePicker from './StatusAudiencePicker.vue';
import {
  BACKGROUND_COLORS,
  audienceParams,
  canRepublish,
  errorMessage,
  parseNumbers,
} from '../helpers';

const props = defineProps({
  inboxId: { type: Number, required: true },
});

const emit = defineEmits(['republished']);

const { t } = useI18n();

const dialogRef = ref(null);
const items = ref([]);
const skipped = ref(0);
const color = ref(BACKGROUND_COLORS[0]);
const audience = reactive({ mode: 'contacts', numbers: '' });
const audienceCount = ref(null);
const isRunning = ref(false);
const current = ref(0);

const hasText = computed(() => items.value.some(item => item.type === 'text'));

const isValid = computed(
  () =>
    items.value.length > 0 &&
    (audience.mode !== 'numbers' || parseNumbers(audience.numbers).length > 0)
);

const confirmLabel = computed(() =>
  isRunning.value
    ? t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.PROGRESS', {
        current: current.value,
        total: items.value.length,
      })
    : t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.CONFIRM')
);

const open = async statuses => {
  items.value = statuses.filter(canRepublish);
  skipped.value = statuses.length - items.value.length;
  color.value = BACKGROUND_COLORS[0];
  Object.assign(audience, { mode: 'contacts', numbers: '' });
  audienceCount.value = null;
  dialogRef.value.open();

  try {
    const { data } = await WhatsappStatusAPI.getAudience(props.inboxId);
    audienceCount.value = data.count;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const republishOne = async (status, results) => {
  current.value += 1;
  try {
    const { data } = await WhatsappStatusAPI.republish({
      inbox_id: props.inboxId,
      id: status.id,
      background_color: color.value,
      ...audienceParams(audience),
    });
    if (data.pending) results.pending += 1;
    else results.done += 1;
  } catch (error) {
    results.failed += 1;
    results.error = errorMessage(t, error);
  }
};

const republish = async () => {
  if (!isValid.value || isRunning.value) return;

  isRunning.value = true;
  current.value = 0;
  const results = { done: 0, pending: 0, failed: 0, error: '' };
  // um de cada vez: a Evolution só responde depois de enviar o status para todos
  await items.value.reduce(
    (chain, status) => chain.then(() => republishOne(status, results)),
    Promise.resolve()
  );
  isRunning.value = false;
  dialogRef.value.close();

  if (results.failed) {
    useAlert(
      t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.FAILED', {
        count: results.failed,
        error: results.error,
      })
    );
  } else if (results.pending) {
    useAlert(t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.PENDING'));
  } else {
    useAlert(
      t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.SUCCESS', { count: results.done })
    );
  }
  if (results.done || results.pending) emit('republished');
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.TITLE')"
    width="xl"
    overflow-y-auto
    :confirm-button-label="confirmLabel"
    :is-loading="isRunning"
    :disable-confirm-button="!isValid"
    @confirm="republish"
  >
    <div class="flex flex-col gap-5">
      <p class="mb-0 text-sm text-n-slate-11">
        {{
          t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.DESCRIPTION', {
            count: items.length,
          })
        }}
      </p>
      <p v-if="skipped" class="mb-0 text-sm text-n-amber-11">
        {{
          t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.SKIPPED', { count: skipped })
        }}
      </p>
      <div v-if="hasText" class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_WHATSAPP_STATUS.REPUBLISH.COLOR') }}
        </span>
        <StatusColorPicker v-model="color" />
      </div>
      <StatusAudiencePicker
        v-model:mode="audience.mode"
        v-model:numbers="audience.numbers"
        id-prefix="republish"
        :count="audienceCount"
      />
    </div>
  </Dialog>
</template>
