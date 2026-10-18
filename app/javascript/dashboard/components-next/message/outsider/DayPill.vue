<script setup>
// OUTSIDER: etiqueta do dia ("Hoje", "Ontem", "Quinta-feira" e a data), usada
// no separador de dia e na etiqueta que acompanha a rolagem.
// Clicar abre o calendário para ir a outra data. `compact` mostra só "Hoje",
// "Ontem" ou "qua., 14/10" (etiqueta flutuante ao lado do card da busca).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  dateFromKey,
  dayLabel,
  formatDate,
  shiftKey,
} from 'dashboard/helper/outsider/conversationHistory';
import {
  openCalendar,
  todayKey,
} from 'dashboard/composables/outsider/useConversationHistory';

const props = defineProps({
  dateKey: { type: String, required: true },
  compact: { type: Boolean, default: false },
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

const compactLabel = computed(() => {
  if (isToday.value) return t('CONVERSATION.OUTSIDER_HISTORY.TODAY');
  if (props.dateKey === shiftKey(todayKey.value, -1)) {
    return t('CONVERSATION.OUTSIDER_HISTORY.YESTERDAY');
  }
  const sameYear = props.dateKey.slice(0, 4) === todayKey.value.slice(0, 4);
  return formatDate(dateFromKey(props.dateKey), locale.value, {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    ...(sameYear ? {} : { year: '2-digit' }),
  });
});
</script>

<template>
  <button
    type="button"
    class="flex items-center gap-2 py-1.5 text-sm rounded-full shadow-md pointer-events-auto ring-1 transition-transform hover:scale-105 whitespace-nowrap"
    :class="[
      compact ? 'px-3' : 'px-4',
      isToday
        ? 'bg-n-teal-9 text-white ring-n-teal-10'
        : 'bg-n-solid-1 text-n-slate-12 ring-n-strong',
    ]"
    :title="t('CONVERSATION.OUTSIDER_HISTORY.GO_TO_DATE')"
    @click="openCalendar(dateKey)"
  >
    <span class="i-lucide-calendar-days size-4 shrink-0" />
    <span v-if="compact" class="font-semibold">{{ compactLabel }}</span>
    <template v-else>
      <span class="font-semibold">{{ label.title }}</span>
      <span :class="isToday ? 'text-white/85' : 'text-n-slate-11'">
        {{ label.subtitle }}
      </span>
    </template>
  </button>
</template>
