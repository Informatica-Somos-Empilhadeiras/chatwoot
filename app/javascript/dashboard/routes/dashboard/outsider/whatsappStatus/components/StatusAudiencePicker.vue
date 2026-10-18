<script setup>
// OUTSIDER: quem recebe o status: todos os contatos da caixa, os escolhidos na lista
// (com busca, região, estado e DDD) ou números digitados.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import StatusContactPicker from './StatusContactPicker.vue';
import { parseNumbers } from '../helpers';

const props = defineProps({
  idPrefix: { type: String, required: true },
  inboxId: { type: Number, required: true },
  // { count, areas }; null enquanto carrega
  summary: { type: Object, default: null },
});

const mode = defineModel('mode', { type: String, default: 'contacts' });
const contactIds = defineModel('contactIds', { type: Array, default: () => [] });
const numbers = defineModel('numbers', { type: String, default: '' });

const { t } = useI18n();

const pickerRef = ref(null);

const contactsDescription = computed(() =>
  props.summary
    ? t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.CONTACTS_COUNT', {
        count: props.summary.count,
      })
    : t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.CONTACTS_DESCRIPTION')
);

const validNumbers = computed(() => parseNumbers(numbers.value).length);

const openPicker = () => pickerRef.value.open(contactIds.value);

const selectChosen = () => {
  mode.value = 'selected';
  if (!contactIds.value.length) openPicker();
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.TITLE') }}
    </span>
    <RadioCard
      :id="`${idPrefix}-audience-contacts`"
      :label="t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.CONTACTS')"
      :description="contactsDescription"
      :is-active="mode === 'contacts'"
      @select="mode = 'contacts'"
    />
    <RadioCard
      :id="`${idPrefix}-audience-selected`"
      :label="t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.SELECTED')"
      :description="t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.SELECTED_DESCRIPTION')"
      :is-active="mode === 'selected'"
      @select="selectChosen"
    >
      <div
        v-if="mode === 'selected'"
        class="flex flex-wrap items-center justify-between w-full gap-2"
      >
        <span class="text-sm text-n-slate-12">
          {{
            t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.SELECTED_COUNT', {
              count: contactIds.length,
            })
          }}
        </span>
        <Button
          type="button"
          size="sm"
          variant="faded"
          icon="i-lucide-users"
          :label="
            contactIds.length
              ? t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.CHANGE_SELECTION')
              : t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.CHOOSE')
          "
          @click.prevent="openPicker"
        />
      </div>
    </RadioCard>
    <RadioCard
      :id="`${idPrefix}-audience-numbers`"
      :label="t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.NUMBERS')"
      :description="t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.NUMBERS_DESCRIPTION')"
      :is-active="mode === 'numbers'"
      @select="mode = 'numbers'"
    >
      <TextArea
        v-if="mode === 'numbers'"
        v-model="numbers"
        class="w-full"
        :placeholder="
          t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.NUMBERS_PLACEHOLDER')
        "
        :max-length="2000"
        auto-height
        :message="
          t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.NUMBERS_COUNT', {
            count: validNumbers,
          })
        "
      />
    </RadioCard>
    <p class="flex gap-2 mb-0 text-xs text-n-slate-11">
      <Icon icon="i-lucide-info" class="flex-shrink-0 size-4" />
      {{ t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.OWN_NUMBER') }}
    </p>
    <StatusContactPicker
      ref="pickerRef"
      :inbox-id="inboxId"
      :summary="summary"
      @confirm="ids => (contactIds = ids)"
    />
  </div>
</template>
