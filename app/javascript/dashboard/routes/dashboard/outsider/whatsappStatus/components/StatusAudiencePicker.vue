<script setup>
// OUTSIDER: quem recebe o status: os contatos da caixa ou só alguns números (para testar).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { parseNumbers } from '../helpers';

const props = defineProps({
  idPrefix: { type: String, required: true },
  // contatos da caixa que recebem; null enquanto carrega
  count: { type: Number, default: null },
});

const mode = defineModel('mode', { type: String, default: 'contacts' });
const numbers = defineModel('numbers', { type: String, default: '' });

const { t } = useI18n();

const contactsDescription = computed(() =>
  props.count === null
    ? t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.CONTACTS_DESCRIPTION')
    : t('OUTSIDER_WHATSAPP_STATUS.AUDIENCE.CONTACTS_COUNT', {
        count: props.count,
      })
);

const validNumbers = computed(() => parseNumbers(numbers.value).length);
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
  </div>
</template>
