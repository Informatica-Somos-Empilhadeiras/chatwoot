<script setup>
// OUTSIDER: etiqueta do dia ("Hoje", "Ontem", "Quinta-feira" e a data), usada
// no separador de dia e na etiqueta que acompanha a rolagem.
// Clicar abre o calendário para ir a outra data.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  dateFromKey,
  dayLabel,
} from 'dashboard/helper/outsider/conversationHistory';
import {
  openCalendar,
  todayKey,
} from 'dashboard/composables/outsider/useConversationHistory';

const props = defineProps({
  dateKey: { type: String, required: true },
});

const { t, locale } = useI18n();

const label = computed(() =>
  dayLabel(
    props.dateKey,
    locale.value,
    {
      today: t('CONVERSATION.OUTSIDER_HISTORY.TODAY'),
      yesterday: t('CONVERSATION.OUTSIDER_HISTORY.YESTERDAY'),
    },
    dateFromKey(todayKey.value)
  )
);

const isToday = computed(() => props.dateKey === todayKey.value);
</script>

<template>
  <button
    type="button"
    class="flex items-center gap-2 px-4 py-1.5 text-sm rounded-full shadow-md pointer-events-auto ring-1 transition-transform hover:scale-105"
    :class="
      isToday
        ? 'bg-n-teal-9 text-white ring-n-teal-10'
        : 'bg-n-solid-1 text-n-slate-12 ring-n-strong'
    "
    :title="t('CONVERSATION.OUTSIDER_HISTORY.GO_TO_DATE')"
    @click="openCalendar(dateKey)"
  >
    <span class="i-lucide-calendar-days size-4 shrink-0" />
    <span class="font-semibold">{{ label.title }}</span>
    <span :class="isToday ? 'text-white/85' : 'text-n-slate-11'">
      {{ label.subtitle }}
    </span>
  </button>
</template>
