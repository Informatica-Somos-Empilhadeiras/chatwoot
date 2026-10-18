<script setup>
// OUTSIDER: calendário para ir até uma data da conversa (ver ConversationSearchPanel.vue).
// Os dias com mensagens ficam marcados (quanto mais mensagens, mais forte).
// Clicar no dia já leva até ele; a hora é opcional.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { fetchMessageDays } from 'dashboard/composables/outsider/useConversationHistory';
import {
  dateFromKey,
  dateKeyOf,
  formatDate,
  monthGrid,
  shiftMonth,
} from 'dashboard/helper/outsider/conversationHistory';

const props = defineProps({
  conversationId: { type: Number, required: true },
  month: { type: String, default: null }, // "AAAA-MM" para abrir
  selectedKey: { type: String, default: null },
  time: { type: String, default: '' },
});

const emit = defineEmits(['select', 'jumpStart', 'jumpLatest']);

const { t, locale } = useI18n();

const todayKey = dateKeyOf(new Date());
const visibleMonth = ref(
  props.month || props.selectedKey?.slice(0, 7) || todayKey.slice(0, 7)
);
const chosenTime = ref(props.time);
const days = ref({});

onMounted(async () => {
  try {
    days.value = await fetchMessageDays(props.conversationId);
  } catch (error) {
    // sem as marcações o calendário continua funcionando
  }
});

const firstMonth = computed(() => {
  const keys = Object.keys(days.value).sort();
  return keys.length ? keys[0].slice(0, 7) : null;
});

const canGoBack = computed(
  () => !firstMonth.value || visibleMonth.value > firstMonth.value
);
const canGoForward = computed(() => visibleMonth.value < todayKey.slice(0, 7));

const monthTitle = computed(() => {
  const title = formatDate(
    dateFromKey(`${visibleMonth.value}-01`),
    locale.value,
    { month: 'long', year: 'numeric' }
  );
  return title.charAt(0).toUpperCase() + title.slice(1);
});

// iniciais dos dias da semana, começando no domingo
const weekdays = computed(() =>
  [4, 5, 6, 7, 8, 9, 10].map(day =>
    formatDate(new Date(1970, 0, day), locale.value, { weekday: 'narrow' })
  )
);

const weeks = computed(() => monthGrid(visibleMonth.value));

const monthCount = computed(() =>
  Object.entries(days.value)
    .filter(([key]) => key.startsWith(visibleMonth.value))
    .reduce((sum, [, count]) => sum + count, 0)
);

const countLabel = count =>
  count === 1
    ? t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.MESSAGES_ONE')
    : t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.MESSAGES_OTHER', { count });

const dayTitle = cell => {
  const count = days.value[cell.key];
  const date = formatDate(dateFromKey(cell.key), locale.value, {
    dateStyle: 'full',
  });
  return count
    ? `${date} · ${countLabel(count)}`
    : `${date} · ${t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.NO_MESSAGES')}`;
};

const dayClass = cell => {
  if (cell.key > todayKey) return 'text-n-slate-8 cursor-not-allowed';
  const count = days.value[cell.key] || 0;
  const classes = [cell.inMonth ? '' : 'opacity-40'];
  if (cell.key === props.selectedKey) {
    classes.push('bg-n-teal-9 text-white font-semibold');
  } else if (count > 30) {
    classes.push('bg-n-teal-7 text-n-slate-12 font-semibold hover:bg-n-teal-8');
  } else if (count > 8) {
    classes.push('bg-n-teal-5 text-n-slate-12 font-semibold hover:bg-n-teal-6');
  } else if (count > 0) {
    classes.push('bg-n-teal-3 text-n-slate-12 font-medium hover:bg-n-teal-4');
  } else {
    classes.push('text-n-slate-10 hover:bg-n-alpha-2');
  }
  if (cell.key === todayKey && cell.key !== props.selectedKey) {
    classes.push('ring-2 ring-inset ring-n-teal-9');
  }
  return classes;
};

const pickDay = cell => {
  if (cell.key > todayKey) return;
  emit('select', { dateKey: cell.key, time: chosenTime.value });
};

const goToTime = () => {
  emit('select', { dateKey: props.selectedKey, time: chosenTime.value });
};
</script>

<template>
  <div
    class="w-[22rem] p-3 rounded-xl shadow-xl bg-n-solid-1 ring-1 ring-n-strong"
  >
    <div class="flex items-center justify-between mb-2">
      <button
        type="button"
        class="flex items-center justify-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-30 disabled:cursor-not-allowed"
        :disabled="!canGoBack"
        :title="t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.PREVIOUS_MONTH')"
        @click="visibleMonth = shiftMonth(visibleMonth, -1)"
      >
        <span class="i-lucide-chevron-left size-5" />
      </button>
      <div class="text-center">
        <p class="m-0 text-sm font-semibold text-n-slate-12">
          {{ monthTitle }}
        </p>
        <p class="m-0 text-xs text-n-slate-10">
          {{
            monthCount
              ? countLabel(monthCount)
              : t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.NO_MESSAGES')
          }}
        </p>
      </div>
      <button
        type="button"
        class="flex items-center justify-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-30 disabled:cursor-not-allowed"
        :disabled="!canGoForward"
        :title="t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.NEXT_MONTH')"
        @click="visibleMonth = shiftMonth(visibleMonth, 1)"
      >
        <span class="i-lucide-chevron-right size-5" />
      </button>
    </div>

    <div class="grid grid-cols-7 gap-1 mb-1">
      <span
        v-for="(weekday, index) in weekdays"
        :key="index"
        class="text-xs font-medium text-center uppercase text-n-slate-10"
      >
        {{ weekday }}
      </span>
    </div>
    <div
      v-for="week in weeks"
      :key="week[0].key"
      class="grid grid-cols-7 gap-1"
    >
      <button
        v-for="cell in week"
        :key="cell.key"
        type="button"
        class="flex items-center justify-center mb-1 text-sm rounded-lg h-9"
        :class="dayClass(cell)"
        :title="dayTitle(cell)"
        :disabled="cell.key > todayKey"
        @click="pickDay(cell)"
      >
        {{ cell.day }}
      </button>
    </div>

    <div class="flex items-center gap-2 pt-3 mt-2 border-t border-n-weak">
      <label
        class="flex items-center flex-1 gap-2 text-sm text-n-slate-11"
        for="outsider-history-time"
      >
        <span class="i-lucide-clock size-4 shrink-0" />
        {{ t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.TIME') }}
      </label>
      <input
        id="outsider-history-time"
        v-model="chosenTime"
        type="time"
        class="reset-base !mb-0 h-8 w-28 px-2 text-sm rounded-lg bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak"
      />
      <button
        v-if="selectedKey && chosenTime"
        type="button"
        class="h-8 px-3 text-sm font-medium text-white rounded-lg bg-n-teal-9 hover:bg-n-teal-10"
        @click="goToTime"
      >
        {{ t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.GO') }}
      </button>
    </div>
    <p class="mt-2 mb-0 text-xs text-n-slate-10">
      {{ t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.HINT') }}
    </p>

    <div class="grid grid-cols-2 gap-2 mt-3">
      <button
        type="button"
        class="flex items-center justify-center gap-1.5 h-9 text-sm font-medium whitespace-nowrap rounded-lg ring-1 ring-n-weak text-n-slate-12 hover:bg-n-alpha-2"
        @click="emit('jumpStart')"
      >
        <span class="i-lucide-arrow-up-to-line size-4" />
        {{ t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.START') }}
      </button>
      <button
        type="button"
        class="flex items-center justify-center gap-1.5 h-9 text-sm font-medium whitespace-nowrap rounded-lg ring-1 ring-n-weak text-n-slate-12 hover:bg-n-alpha-2"
        @click="emit('jumpLatest')"
      >
        <span class="i-lucide-arrow-down-to-line size-4" />
        {{ t('CONVERSATION.OUTSIDER_HISTORY.CALENDAR.LATEST') }}
      </button>
    </div>
  </div>
</template>
