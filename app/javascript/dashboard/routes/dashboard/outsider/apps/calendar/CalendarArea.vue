<script setup>
// OUTSIDER: Agenda dos Aplicativos (bloco Microsoft; Google na próxima entrega), separada do Teams. Visão por Dia,
// Semana ou Mês (a escolha fica lembrada neste navegador), Hoje e setas para andar, o painel do dia escolhido ao lado
// com os detalhes ("Entrar na reunião", abrir no Outlook, cancelar) e "Marcar reunião". Os eventos vêm da agenda da
// pessoa na hora, só do período na tela; nada fica no Chatwoot.
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AppLogo from '../AppLogo.vue';
import AppsGate from '../AppsGate.vue';
import EventForm from './EventForm.vue';
import PlaceView from 'dashboard/components-next/outsider/maps/PlaceView.vue'; // OUTSIDER (Maps): local do evento
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  savedChoice,
  choicePatch,
  targetOf,
  visibleOf,
  colorClassOf,
} from 'dashboard/helper/outsider/calendarChoice';
import { providerOf, gateOf } from '../providers';
import { errorText } from '../appsErrors';
import {
  rangeOf,
  shift,
  parseLocal,
  coversDay,
  colorOf,
  dayKey,
  timeKey,
  startOfDay,
} from './calendarDates';
import '../apps.css';

const { t } = useI18n();
const route = useRoute();

const VIEW_KEY = 'outsider_apps_calendar_view';
const HOUR = 48; // px por hora na grade de Dia e Semana
const MAX_CHIPS = 3;

const readView = () => {
  try {
    const saved = window.localStorage.getItem(VIEW_KEY);
    return ['day', 'week', 'month'].includes(saved) ? saved : 'week';
  } catch {
    return 'week';
  }
};

const providerKey = computed(() => route.params.provider || 'microsoft');
const info = computed(() => providerOf(providerKey.value));
const cal = computed(() => info.value.calendar);
const gate = computed(() => gateOf(providerKey.value, cal.value.feature));

const view = ref(
  ['day', 'week', 'month'].includes(route.query.view)
    ? route.query.view
    : readView()
);
const anchor = ref(new Date());
const selectedDay = ref(startOfDay(new Date()));
const selectedEventId = ref(null);
const events = ref([]);
const isLoading = ref(false);
const error = ref('');
const form = ref(null); // { day, hour }
const gridRef = ref(null);

const timeZone =
  Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Sao_Paulo';

// ---------- agendas (a principal e as compartilhadas com a pessoa) ----------
const { uiSettings, updateUISettings } = useUISettings();
const calendars = ref([]);
const calendarsComplete = ref(true);
const choice = computed(() => savedChoice(uiSettings.value, providerKey.value));
const visibleIds = computed(() =>
  calendars.value.length
    ? visibleOf(calendars.value, choice.value.visible)
    : ['primary']
);
const editableCalendars = computed(() =>
  calendars.value.filter(item => item.can_edit)
);
const targetId = computed(() => targetOf(calendars.value, choice.value.target));
const remember = patch =>
  updateUISettings(choicePatch(uiSettings.value, providerKey.value, patch));
const toggleCalendar = id => {
  const list = visibleIds.value.includes(id)
    ? visibleIds.value.filter(item => item !== id)
    : [...visibleIds.value, id];
  if (list.length) remember({ visible: list });
};
const calendarName = id => calendars.value.find(item => item.id === id)?.name;
const eventKey = event => `${event.calendar_id || 'primary'}:${event.id}`;
// com mais de uma agenda na tela, a cor é a da agenda; com uma só, cada evento tem a sua
const eventColor = event =>
  visibleIds.value.length > 1
    ? colorClassOf(calendars.value, event.calendar_id)
    : colorOf(event);
const loadCalendars = async () => {
  if (gate.value !== 'ready' || !cal.value.calendars) return;
  try {
    const { data } = await cal.value.calendars();
    calendars.value = data.payload || [];
    calendarsComplete.value = data.complete !== false;
  } catch {
    calendars.value = [];
  }
};
const todayKey = computed(() => dayKey(new Date()));
const range = computed(() => rangeOf(view.value, anchor.value));

const title = computed(() => {
  const a = anchor.value;
  if (view.value === 'month')
    return a
      .toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })
      .replace(/^\w/, c => c.toUpperCase());
  if (view.value === 'day')
    return a
      .toLocaleDateString('pt-BR', {
        weekday: 'long',
        day: 'numeric',
        month: 'long',
      })
      .replace(/^\w/, c => c.toUpperCase());
  const { days } = range.value;
  const fmt = d =>
    d.toLocaleDateString('pt-BR', { day: 'numeric', month: 'short' });
  return `${fmt(days[0])} – ${fmt(days[6])}`;
});

const visible = computed(() => events.value.filter(event => !event.cancelled));
const eventsOn = day =>
  visible.value
    .filter(event => coversDay(event, day))
    .sort((a, b) => String(a.start).localeCompare(String(b.start)));

// ---------- mês ----------
const monthDays = computed(() =>
  range.value.days.map(day => {
    const list = eventsOn(day);
    return {
      key: dayKey(day),
      date: day,
      number: day.getDate(),
      outside: day.getMonth() !== anchor.value.getMonth(),
      items: list.slice(0, MAX_CHIPS),
      more: Math.max(list.length - MAX_CHIPS, 0),
    };
  })
);

// ---------- dia e semana (grade de horas) ----------
const hours = Array.from({ length: 24 }, (_, i) => i);
const minutesOf = date => date.getHours() * 60 + date.getMinutes();

// eventos com hora num dia, lado a lado quando se encontram
const layoutDay = day => {
  const dayStart = startOfDay(day);
  const items = eventsOn(day)
    .filter(event => !event.all_day)
    .map(event => {
      const start = parseLocal(event.start);
      const end = parseLocal(event.end);
      const top = start < dayStart ? 0 : minutesOf(start);
      const bottom =
        end >= new Date(dayStart.getTime() + 86400000) ? 1440 : minutesOf(end);
      return { event, top, bottom: Math.max(bottom, top + 20) };
    })
    .sort((a, b) => a.top - b.top || b.bottom - a.bottom);
  const placed = [];
  let cluster = [];
  let clusterEnd = -1;
  const closeCluster = () => {
    const lanes = Math.max(...cluster.map(item => item.lane + 1), 1);
    cluster.forEach(item => {
      item.lanes = lanes;
    });
    cluster = [];
  };
  items.forEach(item => {
    if (item.top >= clusterEnd && cluster.length) closeCluster();
    const used = cluster
      .filter(other => other.bottom > item.top)
      .map(o => o.lane);
    let lane = 0;
    while (used.includes(lane)) lane += 1;
    const entry = { ...item, lane, lanes: 1 };
    cluster.push(entry);
    placed.push(entry);
    clusterEnd = Math.max(clusterEnd, item.bottom);
  });
  if (cluster.length) closeCluster();
  return placed.map(item => ({
    ...item,
    // até 45 min: assunto e horário numa linha só, para caber no bloco baixo
    short: item.bottom - item.top < 45,
    style: {
      top: `${(item.top / 60) * HOUR}px`,
      height: `${((item.bottom - item.top) / 60) * HOUR - 2}px`,
      left: `calc(${(item.lane / item.lanes) * 100}% + 2px)`,
      width: `calc(${100 / item.lanes}% - 4px)`,
    },
  }));
};

const gridDays = computed(() =>
  view.value === 'month'
    ? []
    : range.value.days.map(day => ({
        key: dayKey(day),
        date: day,
        label: day
          .toLocaleDateString('pt-BR', { weekday: 'short' })
          .replace('.', '')
          .toUpperCase(),
        number: day.getDate(),
        allDay: eventsOn(day).filter(event => event.all_day),
        timed: layoutDay(day),
      }))
);

const nowTop = computed(() => (minutesOf(new Date()) / 60) * HOUR);

// ---------- painel do dia ----------
const dayEvents = computed(() => eventsOn(selectedDay.value));
const dayTitle = computed(() =>
  selectedDay.value
    .toLocaleDateString('pt-BR', {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
    })
    .replace(/^\w/, c => c.toUpperCase())
);

const timeRange = event => {
  if (event.all_day) return t('OUTSIDER_APPS.CAL.ALL_DAY');
  return `${timeKey(parseLocal(event.start))} – ${timeKey(parseLocal(event.end))}`;
};

const responseText = event =>
  ({
    accepted: t('OUTSIDER_APPS.CAL.ACCEPTED'),
    tentativelyAccepted: t('OUTSIDER_APPS.CAL.TENTATIVE'),
    declined: t('OUTSIDER_APPS.CAL.DECLINED'),
  })[event.response] || '';

// ---------- carregar ----------
let ticket = 0;
const load = async () => {
  if (gate.value !== 'ready') return;
  ticket += 1;
  const mine = ticket;
  isLoading.value = true;
  error.value = '';
  try {
    const { from, to } = range.value;
    const { data } = await cal.value.events({
      from: from.toISOString(),
      to: to.toISOString(),
      timeZone,
      calendarIds: visibleIds.value,
    });
    if (mine !== ticket) return;
    events.value = data.payload || [];
  } catch (e) {
    if (mine !== ticket) return;
    error.value =
      e?.response?.data?.error === 'scope_outdated' ? 'scope' : errorText(e, t);
  } finally {
    if (mine === ticket) isLoading.value = false;
  }
};

const scrollToMorning = async () => {
  await nextTick();
  if (gridRef.value && view.value !== 'month')
    gridRef.value.scrollTop = HOUR * 7 - 8;
};

const setView = value => {
  view.value = value;
  try {
    window.localStorage.setItem(VIEW_KEY, value);
  } catch {
    // sem armazenamento no navegador: só não lembra a escolha
  }
  anchor.value = new Date(selectedDay.value);
};

const move = step => {
  anchor.value = shift(view.value, anchor.value, step);
  if (view.value !== 'month') selectedDay.value = startOfDay(anchor.value);
};
const today = () => {
  anchor.value = new Date();
  selectedDay.value = startOfDay(new Date());
};

const pickDay = (day, event = null) => {
  selectedDay.value = startOfDay(day);
  selectedEventId.value = event ? eventKey(event) : null;
};

const openDay = day => {
  pickDay(day);
  anchor.value = new Date(day);
  view.value = 'day';
};

const newEvent = (day = null, hour = '') => {
  form.value = { day: day ? dayKey(day) : '', hour };
};
const onSaved = event => {
  form.value = null;
  if (event.calendar_id && event.calendar_id !== choice.value.target)
    remember({ target: event.calendar_id });
  events.value = [...events.value, event];
  pickDay(parseLocal(event.start), event);
};

const remove = async event => {
  // eslint-disable-next-line no-alert
  const ok = window.confirm(
    t(
      event.mine
        ? 'OUTSIDER_APPS.CAL.CONFIRM_CANCEL'
        : 'OUTSIDER_APPS.CAL.CONFIRM_REMOVE'
    )
  );
  if (!ok) return;
  try {
    await cal.value.remove(event.id, event.calendar_id);
    events.value = events.value.filter(
      item => eventKey(item) !== eventKey(event)
    );
  } catch (e) {
    useAlert(errorText(e, t));
  }
};

watch([range, gate, () => visibleIds.value.join('|')], load);
watch([gate, providerKey], loadCalendars);
// a grade só aparece depois de saber se a conta está conectada: rola para as 7h quando ela surge ou muda de visão
watch([view, gridRef], scrollToMorning);
onMounted(() => {
  load();
  loadCalendars();
});
</script>

<template>
  <section
    class="flex flex-col w-full h-full overflow-hidden oapps bg-n-surface-1"
    data-apps-calendar
  >
    <AppsGate
      v-if="gate !== 'ready'"
      :provider="providerKey"
      :state="gate"
      :logo="cal.logo"
      :app-name="t(cal.name)"
    />
    <template v-else>
      <header
        class="flex flex-wrap items-center gap-2 px-4 py-3 border-b border-n-weak md:px-5"
      >
        <AppLogo :name="cal.logo" :size="30" />
        <div class="min-w-0 mr-auto">
          <h2 class="mb-0 text-lg font-semibold leading-tight text-n-slate-12">
            {{ t(cal.name) }}
          </h2>
          <p class="mb-0 text-xs text-n-slate-11">{{ t(cal.source) }}</p>
        </div>
        <button type="button" class="oa-ghost" @click="today">
          {{ t('OUTSIDER_APPS.CAL.TODAY') }}
        </button>
        <span class="flex items-center gap-1">
          <button
            type="button"
            class="oa-ghost !border-0 !bg-transparent"
            :aria-label="t('OUTSIDER_APPS.CAL.PREVIOUS')"
            @click="move(-1)"
          >
            <Icon icon="i-lucide-chevron-left" class="size-5" />
          </button>
          <b
            class="min-w-[150px] text-center text-sm text-n-slate-12"
            data-apps-calendar-title
          >
            {{ title }}
          </b>
          <button
            type="button"
            class="oa-ghost !border-0 !bg-transparent"
            :aria-label="t('OUTSIDER_APPS.CAL.NEXT')"
            @click="move(1)"
          >
            <Icon icon="i-lucide-chevron-right" class="size-5" />
          </button>
        </span>
        <span class="oa-tabs" role="tablist">
          <button
            v-for="option in ['day', 'week', 'month']"
            :key="option"
            type="button"
            role="tab"
            :class="{ on: view === option }"
            :aria-selected="view === option"
            :data-apps-calendar-view="option"
            @click="setView(option)"
          >
            {{ t(`OUTSIDER_APPS.CAL.VIEW_${option.toUpperCase()}`) }}
          </button>
        </span>
        <button
          type="button"
          class="oa-btn"
          data-apps-new-event
          @click="newEvent(selectedDay)"
        >
          <Icon icon="i-lucide-plus" class="size-4" />
          {{ t('OUTSIDER_APPS.CAL.NEW') }}
        </button>
      </header>

      <div class="flex flex-1 min-h-0">
        <div class="relative flex flex-col flex-1 min-w-0">
          <div
            v-if="isLoading"
            class="absolute z-20 flex items-center gap-2 px-3 py-1 text-xs -translate-x-1/2 rounded-full shadow top-2 left-1/2 bg-n-surface-1 text-n-slate-11"
          >
            <Spinner :size="12" /> {{ t('OUTSIDER_APPS.LOADING') }}
          </div>
          <div
            v-if="error === 'scope'"
            class="m-4 p-4 text-sm text-center rounded-2xl bg-n-amber-3 text-n-amber-11"
          >
            {{ t('OUTSIDER_APPS.GATE.SCOPE_TEXT', { app: t(cal.name) }) }}
          </div>
          <p v-else-if="error" class="py-6 text-sm text-center text-n-ruby-11">
            {{ error }}
          </p>

          <!-- ===== mês ===== -->
          <div
            v-else-if="view === 'month'"
            class="flex flex-col flex-1 min-h-0 p-2 md:p-3"
          >
            <div
              class="grid grid-cols-7 text-[11px] font-semibold tracking-wide text-n-slate-11"
            >
              <span
                v-for="name in [
                  'SEG',
                  'TER',
                  'QUA',
                  'QUI',
                  'SEX',
                  'SÁB',
                  'DOM',
                ]"
                :key="name"
                class="px-2 py-1.5"
              >
                {{ name }}
              </span>
            </div>
            <div
              class="grid flex-1 grid-cols-7 border-t border-l auto-rows-fr border-n-weak"
            >
              <div
                v-for="day in monthDays"
                :key="day.key"
                class="flex flex-col min-w-0 gap-0.5 p-1 border-b border-r cursor-pointer border-n-weak min-h-[84px]"
                :class="{
                  'bg-n-alpha-1': day.outside,
                  'ring-2 ring-inset ring-[var(--oa-accent)]':
                    dayKey(selectedDay) === day.key,
                }"
                :data-apps-day="day.key"
                @click="pickDay(day.date)"
                @dblclick="newEvent(day.date)"
              >
                <span
                  class="grid text-xs rounded-full size-6 place-items-center"
                  :class="[
                    day.key === todayKey
                      ? 'bg-[var(--oa-accent)] text-white font-bold'
                      : day.outside
                        ? 'text-n-slate-9'
                        : 'text-n-slate-12',
                  ]"
                >
                  {{ day.number }}
                </span>
                <button
                  v-for="event in day.items"
                  :key="eventKey(event)"
                  type="button"
                  class="oa-ev"
                  :class="eventColor(event)"
                  :title="`${timeRange(event)} · ${event.subject || ''}`"
                  data-apps-event
                  @click.stop="pickDay(day.date, event)"
                >
                  <template v-if="!event.all_day">
                    {{ timeKey(parseLocal(event.start)) }}
                  </template>
                  {{ event.subject || t('OUTSIDER_APPS.CAL.NO_SUBJECT') }}
                </button>
                <button
                  v-if="day.more"
                  type="button"
                  class="px-1.5 text-[11px] text-left text-n-slate-11 hover:underline"
                  @click.stop="openDay(day.date)"
                >
                  {{ t('OUTSIDER_APPS.CAL.MORE', { count: day.more }) }}
                </button>
              </div>
            </div>
          </div>

          <!-- ===== dia e semana ===== -->
          <template v-else>
            <div class="flex pr-2 border-b border-n-weak">
              <span class="w-14 shrink-0" />
              <div
                v-for="day in gridDays"
                :key="day.key"
                class="flex-1 min-w-0 px-1 py-1.5 text-center cursor-pointer"
                @click="pickDay(day.date)"
              >
                <span class="block text-[11px] font-semibold text-n-slate-11">
                  {{ day.label }}
                </span>
                <span
                  class="inline-grid text-sm rounded-full size-7 place-items-center"
                  :class="
                    day.key === todayKey
                      ? 'bg-[var(--oa-accent)] text-white font-bold'
                      : 'text-n-slate-12'
                  "
                >
                  {{ day.number }}
                </span>
                <div class="flex flex-col gap-0.5 mt-1">
                  <button
                    v-for="event in day.allDay"
                    :key="eventKey(event)"
                    type="button"
                    class="oa-ev"
                    :class="eventColor(event)"
                    data-apps-event
                    @click.stop="pickDay(day.date, event)"
                  >
                    {{ event.subject || t('OUTSIDER_APPS.CAL.NO_SUBJECT') }}
                  </button>
                </div>
              </div>
            </div>
            <div
              ref="gridRef"
              class="relative flex flex-1 min-h-0 overflow-y-auto"
            >
              <div class="w-14 shrink-0">
                <div
                  v-for="hour in hours"
                  :key="hour"
                  class="pr-2 text-[10px] text-right text-n-slate-10"
                  :style="{ height: `${HOUR}px` }"
                >
                  <span v-if="hour" class="relative -top-1.5">
                    {{ `${String(hour).padStart(2, '0')}:00` }}
                  </span>
                </div>
              </div>
              <div
                v-for="day in gridDays"
                :key="day.key"
                class="relative flex-1 min-w-0 border-l border-n-weak"
                :style="{ height: `${HOUR * 24}px` }"
                :data-apps-day="day.key"
              >
                <div
                  v-for="hour in hours"
                  :key="hour"
                  class="border-b border-n-weak/60 hover:bg-n-alpha-1"
                  :style="{ height: `${HOUR}px` }"
                  @dblclick="
                    newEvent(day.date, `${String(hour).padStart(2, '0')}:00`)
                  "
                />
                <div
                  v-if="day.key === todayKey"
                  class="absolute left-0 right-0 z-10 h-0.5 bg-n-ruby-9 pointer-events-none"
                  :style="{ top: `${nowTop}px` }"
                />
                <button
                  v-for="item in day.timed"
                  :key="eventKey(item.event)"
                  type="button"
                  class="absolute z-[5] flex flex-col overflow-hidden oa-ev !whitespace-normal shadow-sm"
                  :class="[
                    eventColor(item.event),
                    {
                      'ring-2 ring-[var(--oa-accent)]':
                        selectedEventId === eventKey(item.event),
                      '!flex-row items-center gap-1 !py-0': item.short,
                    },
                  ]"
                  :style="item.style"
                  data-apps-event
                  @click="pickDay(day.date, item.event)"
                >
                  <b class="truncate">{{
                    item.event.subject || t('OUTSIDER_APPS.CAL.NO_SUBJECT')
                  }}</b>
                  <span class="truncate opacity-80 shrink-0">{{
                    item.short
                      ? timeKey(parseLocal(item.event.start))
                      : timeRange(item.event)
                  }}</span>
                </button>
              </div>
            </div>
          </template>
        </div>

        <!-- ===== painel do dia ===== -->
        <aside
          class="hidden lg:flex flex-col w-[300px] shrink-0 gap-3 p-4 overflow-y-auto border-l border-n-weak"
          data-apps-day-panel
        >
          <!-- OUTSIDER: agendas para ver (a principal e as compartilhadas) -->
          <div
            v-if="calendars.length > 1 || !calendarsComplete"
            class="flex flex-col gap-1 pb-3 border-b border-n-weak"
            data-apps-calendars
          >
            <b class="text-xs tracking-wide uppercase text-n-slate-11">
              {{ t('OUTSIDER_APPS.CAL.CALENDARS') }}
            </b>
            <label
              v-for="item in calendars"
              :key="item.id"
              class="flex items-center gap-2 text-sm cursor-pointer text-n-slate-12"
              :data-apps-calendar-id="item.id"
            >
              <input
                type="checkbox"
                class="!m-0"
                :checked="visibleIds.includes(item.id)"
                @change="toggleCalendar(item.id)"
              />
              <span
                class="w-3 h-3 rounded-sm shrink-0 oa-ev !p-0"
                :class="colorClassOf(calendars, item.id)"
              />
              <span class="flex-1 min-w-0 truncate">{{ item.name }}</span>
              <Icon
                v-if="!item.can_edit"
                v-tooltip.top="t('OUTSIDER_APPS.CAL.READ_ONLY')"
                icon="i-lucide-eye"
                class="size-3.5 text-n-slate-10"
              />
            </label>
            <p
              v-if="!calendarsComplete"
              class="mb-0 text-[11px] text-n-amber-11"
            >
              {{ t('OUTSIDER_APPS.CAL.SHARED_RELOGIN') }}
            </p>
          </div>
          <div class="flex items-center justify-between gap-2">
            <b class="text-sm text-n-slate-12">{{ dayTitle }}</b>
            <button
              type="button"
              class="oa-ghost !h-7 !min-w-7 !px-2"
              :title="t('OUTSIDER_APPS.CAL.NEW')"
              @click="newEvent(selectedDay)"
            >
              <Icon icon="i-lucide-plus" class="size-4" />
            </button>
          </div>
          <p v-if="!dayEvents.length" class="mb-0 text-xs text-n-slate-10">
            {{ t('OUTSIDER_APPS.CAL.FREE') }}
          </p>
          <article
            v-for="event in dayEvents"
            :key="eventKey(event)"
            class="flex flex-col gap-1 p-3 border rounded-xl border-n-weak"
            :class="{
              'ring-2 ring-[var(--oa-accent)]':
                selectedEventId === eventKey(event),
            }"
            data-apps-day-event
          >
            <span
              class="flex items-center gap-1.5 text-xs font-semibold text-n-slate-11"
            >
              {{ timeRange(event) }}
              <span
                v-if="visibleIds.length > 1 && calendarName(event.calendar_id)"
                class="px-1.5 rounded oa-ev !inline !py-0 truncate"
                :class="eventColor(event)"
              >
                {{ calendarName(event.calendar_id) }}
              </span>
            </span>
            <h3
              class="flex items-center gap-1.5 mb-0 text-sm font-semibold text-n-slate-12"
            >
              <Icon
                v-if="event.online"
                icon="i-lucide-video"
                class="size-4 shrink-0 text-[var(--oa-accent)]"
              />
              <span class="min-w-0 break-words">{{
                event.subject || t('OUTSIDER_APPS.CAL.NO_SUBJECT')
              }}</span>
            </h3>
            <p
              v-if="event.location || event.organizer || responseText(event)"
              class="mb-0 text-xs text-n-slate-11"
            >
              {{
                [event.location, event.organizer, responseText(event)]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </p>
            <p
              v-if="event.preview"
              class="mb-0 text-xs text-n-slate-10 line-clamp-3"
            >
              {{ event.preview }}
            </p>
            <!-- local do evento: Street View (com coordenadas) ou o mapa do endereço; só no evento escolhido -->
            <template
              v-if="(event.latitude ?? null) !== null || event.location"
            >
              <PlaceView
                v-if="selectedEventId === eventKey(event)"
                class="mt-1"
                :latitude="event.latitude ?? null"
                :longitude="event.longitude ?? null"
                :query="event.location || ''"
                :height="170"
                data-apps-event-place
              />
              <button
                v-else
                type="button"
                class="flex items-center gap-1 !p-0 text-xs text-[var(--oa-accent)] hover:underline w-fit"
                data-apps-event-place-show
                @click="selectedEventId = eventKey(event)"
              >
                <Icon icon="i-lucide-map-pin" class="size-3.5" />
                {{ t('OUTSIDER_MAPS.SCHEDULE.SEE_PLACE') }}
              </button>
            </template>
            <div
              v-if="event.attendees?.length"
              class="flex items-center gap-1 mt-0.5"
            >
              <Avatar
                v-for="person in event.attendees.slice(0, 6)"
                :key="person.email"
                :name="person.name || person.email"
                :size="20"
                rounded-full
                :title="person.name || person.email"
              />
              <span
                v-if="event.attendees.length > 6"
                class="text-[11px] text-n-slate-11"
              >
                +{{ event.attendees.length - 6 }}
              </span>
            </div>
            <div class="flex flex-wrap items-center gap-1.5 mt-1">
              <a
                v-if="event.join_url"
                :href="event.join_url"
                target="_blank"
                rel="noopener noreferrer"
                class="oa-btn !h-8 !px-3 !text-xs"
              >
                {{ t('OUTSIDER_APPS.CAL.JOIN') }}
              </a>
              <a
                v-if="event.web_link"
                :href="event.web_link"
                target="_blank"
                rel="noopener noreferrer"
                class="oa-ghost !h-8 !text-xs"
              >
                <Icon icon="i-lucide-external-link" class="size-3.5" />
                {{ t('OUTSIDER_APPS.CAL.OPEN') }}
              </a>
              <button
                type="button"
                class="oa-ghost is-danger !h-8 !text-xs"
                :title="
                  t(
                    event.mine
                      ? 'OUTSIDER_APPS.CAL.CANCEL'
                      : 'OUTSIDER_APPS.CAL.REMOVE'
                  )
                "
                @click="remove(event)"
              >
                <Icon icon="i-lucide-trash-2" class="size-3.5" />
              </button>
            </div>
          </article>
          <p class="mt-auto mb-0 text-[11px] text-n-slate-10">
            {{ t('OUTSIDER_APPS.CAL.HINT') }}
          </p>
        </aside>
      </div>
    </template>

    <EventForm
      v-if="form"
      :api="cal"
      :day="form.day"
      :hour="form.hour"
      :online-label="t(cal.onlineLabel)"
      :calendars="editableCalendars"
      :calendar-id="targetId"
      @close="form = null"
      @saved="onSaved"
    />
  </section>
</template>
