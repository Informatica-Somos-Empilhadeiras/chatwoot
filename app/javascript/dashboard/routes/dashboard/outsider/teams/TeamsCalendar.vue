<script setup>
// OUTSIDER: agenda da pessoa (Outlook/Teams) na área Teams: a semana em lista por dia, com os eventos, o link
// "Entrar na reunião" e "Marcar reunião" (assunto, dia, horário, convidados das suas conversas ou por e-mail,
// reunião do Teams ou não). Tudo vem da Microsoft na hora; nada fica no Chatwoot. Pede as permissões novas (v2).
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import { teamsState } from './teamsStore';
import { errorText } from './helpers';

const emit = defineEmits(['back']);
const { t } = useI18n();

const timeZone =
  Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Sao_Paulo';
const pad = n => String(n).padStart(2, '0');
const localIso = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:00`;
const dayOf = iso => String(iso).slice(0, 10);
const timeOf = iso => String(iso).slice(11, 16);
const startOfWeek = date => {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); // segunda
  return d;
};

const weekStart = ref(startOfWeek(new Date()));
const events = ref([]);
const isLoading = ref(true);
const error = ref('');
const showForm = ref(false);
const isSaving = ref(false);
const people = ref(null);
const personQuery = ref('');
const form = ref(null);

const weekEnd = computed(() => {
  const d = new Date(weekStart.value);
  d.setDate(d.getDate() + 7);
  return d;
});
const weekLabel = computed(() => {
  const end = new Date(weekEnd.value);
  end.setDate(end.getDate() - 1);
  const fmt = d => d.toLocaleDateString('pt-BR', { day: 'numeric', month: 'short' });
  return `${fmt(weekStart.value)} – ${fmt(end)}`;
});

const days = computed(() => {
  const list = [];
  const today = dayOf(localIso(new Date()));
  for (let i = 0; i < 7; i += 1) {
    const d = new Date(weekStart.value);
    d.setDate(d.getDate() + i);
    const key = dayOf(localIso(d));
    list.push({
      key,
      today: key === today,
      weekday: d.toLocaleDateString('pt-BR', { weekday: 'long' }).replace(/^\w/, c => c.toUpperCase()),
      date: d.toLocaleDateString('pt-BR', { day: 'numeric', month: 'long' }),
      items: events.value.filter(event => dayOf(event.start) === key && !event.cancelled),
    });
  }
  return list;
});

const load = async () => {
  isLoading.value = true;
  error.value = '';
  try {
    const { data } = await TeamsGraphAPI.calendar({
      from: weekStart.value.toISOString(),
      to: weekEnd.value.toISOString(),
      timeZone,
    });
    events.value = data.payload;
  } catch (e) {
    error.value = e?.response?.data?.error === 'scope_outdated' ? 'scope' : errorText(e, t);
  } finally {
    isLoading.value = false;
  }
};

const move = step => {
  const d = new Date(weekStart.value);
  d.setDate(d.getDate() + step * 7);
  weekStart.value = d;
  load();
};
const thisWeek = () => {
  weekStart.value = startOfWeek(new Date());
  load();
};

const openForm = (day = null) => {
  const base = day ? new Date(`${day}T09:00:00`) : new Date();
  if (!day) base.setMinutes(base.getMinutes() < 30 ? 30 : 60, 0, 0);
  const end = new Date(base);
  end.setMinutes(end.getMinutes() + 30);
  form.value = {
    subject: '',
    date: dayOf(localIso(base)),
    start: timeOf(localIso(base)),
    end: timeOf(localIso(end)),
    online: true,
    attendees: [],
    email: '',
    body: '',
  };
  personQuery.value = '';
  showForm.value = true;
  if (!people.value) {
    TeamsGraphAPI.people()
      .then(({ data }) => {
        people.value = data.payload.filter(person => person.email);
      })
      .catch(() => {
        people.value = [];
      });
  }
};

const suggestions = computed(() => {
  const q = personQuery.value.trim().toLowerCase();
  if (!q || !people.value) return [];
  return people.value
    .filter(
      person =>
        !form.value.attendees.some(item => item.email === person.email) &&
        `${person.name} ${person.email}`.toLowerCase().includes(q)
    )
    .slice(0, 6);
});

const addPerson = person => {
  form.value.attendees.push({ name: person.name, email: person.email });
  personQuery.value = '';
};
const addEmail = () => {
  const email = personQuery.value.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return;
  if (!form.value.attendees.some(item => item.email === email))
    form.value.attendees.push({ name: email, email });
  personQuery.value = '';
};

const save = async () => {
  const f = form.value;
  if (!f.subject.trim() || !f.date || !f.start || !f.end) return;
  isSaving.value = true;
  try {
    const { data } = await TeamsGraphAPI.createEvent({
      subject: f.subject.trim(),
      start: `${f.date}T${f.start}:00`,
      end: `${f.date}T${f.end}:00`,
      time_zone: timeZone,
      online: f.online,
      attendees: f.attendees.map(item => item.email),
      body: f.body,
    });
    events.value = [...events.value, data].sort((a, b) => a.start.localeCompare(b.start));
    showForm.value = false;
    useAlert(t('OUTSIDER_TEAMS_AREA.CALENDAR.CREATED'));
  } catch (e) {
    useAlert(errorText(e, t));
  } finally {
    isSaving.value = false;
  }
};

const remove = async event => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t(event.mine ? 'OUTSIDER_TEAMS_AREA.CALENDAR.CONFIRM_CANCEL' : 'OUTSIDER_TEAMS_AREA.CALENDAR.CONFIRM_REMOVE'))) return;
  try {
    await TeamsGraphAPI.deleteEvent(event.id);
    events.value = events.value.filter(item => item.id !== event.id);
  } catch (e) {
    useAlert(errorText(e, t));
  }
};

const responseText = event =>
  ({
    accepted: t('OUTSIDER_TEAMS_AREA.CALENDAR.ACCEPTED'),
    tentativelyAccepted: t('OUTSIDER_TEAMS_AREA.CALENDAR.TENTATIVE'),
    declined: t('OUTSIDER_TEAMS_AREA.CALENDAR.DECLINED'),
  })[event.response] || '';

onMounted(load);
</script>

<template>
  <div class="flex flex-col flex-1 min-w-0 tms-bg">
    <header
      class="flex flex-wrap items-center gap-2 px-4 py-3 border-b md:px-5 border-n-weak bg-n-surface-1"
    >
      <button
        type="button"
        class="md:hidden text-n-slate-11"
        :aria-label="t('OUTSIDER_TEAMS_AREA.BACK')"
        @click="emit('back')"
      >
        <Icon icon="i-lucide-chevron-left" class="size-6" />
      </button>
      <span class="flex items-center justify-center size-10 rounded-xl tms-soft shrink-0">
        <Icon icon="i-lucide-calendar-days" class="size-5" />
      </span>
      <div class="flex-1 min-w-0">
        <h2 class="mb-0 text-base font-semibold truncate text-n-slate-12">
          {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.TITLE') }}
        </h2>
        <p class="mb-0 text-xs text-n-slate-11">{{ weekLabel }}</p>
      </div>
      <span class="flex items-center gap-1">
        <button type="button" class="grid rounded-lg size-8 place-items-center hover:bg-n-alpha-2 text-n-slate-11" @click="move(-1)">
          <Icon icon="i-lucide-chevron-left" class="size-5" />
        </button>
        <button type="button" class="px-2.5 h-8 text-xs font-semibold rounded-lg hover:bg-n-alpha-2 text-n-slate-12" @click="thisWeek">
          {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.THIS_WEEK') }}
        </button>
        <button type="button" class="grid rounded-lg size-8 place-items-center hover:bg-n-alpha-2 text-n-slate-11" @click="move(1)">
          <Icon icon="i-lucide-chevron-right" class="size-5" />
        </button>
      </span>
      <button
        type="button"
        class="flex items-center gap-1.5 px-3 h-9 text-sm font-semibold rounded-xl tms-accent-bg disabled:opacity-40"
        :disabled="error === 'scope' || teamsState.status !== 'active'"
        data-teams-new-event
        @click="openForm()"
      >
        <Icon icon="i-lucide-plus" class="size-4" />
        {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.NEW') }}
      </button>
    </header>

    <div class="flex-1 min-h-0 px-4 py-4 overflow-y-auto md:px-6">
      <div v-if="isLoading" class="flex justify-center py-10"><Spinner :size="20" /></div>
      <div
        v-else-if="error === 'scope'"
        class="flex flex-col items-center gap-2 p-6 text-sm text-center rounded-2xl bg-n-amber-3 text-n-amber-11"
      >
        <Icon icon="i-lucide-key-round" class="size-6" />
        {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.NEEDS_SCOPE') }}
      </div>
      <p v-else-if="error" class="py-6 text-sm text-center text-n-ruby-11">{{ error }}</p>
      <template v-else>
        <section
          v-for="day in days"
          :key="day.key"
          class="flex gap-4 py-3 border-b border-n-weak last:border-b-0"
          :data-teams-day="day.key"
        >
          <div class="w-[88px] shrink-0 text-xs text-n-slate-11">
            <b class="block text-sm" :class="day.today ? 'tms-text' : 'text-n-slate-12'">{{ day.weekday }}</b>
            {{ day.date }}
            <button
              type="button"
              class="flex items-center gap-1 mt-1 text-[11px] tms-text hover:underline"
              @click="openForm(day.key)"
            >
              <Icon icon="i-lucide-plus" class="size-3" />
              {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.ADD') }}
            </button>
          </div>
          <div class="flex flex-col flex-1 min-w-0 gap-2">
            <p v-if="!day.items.length" class="mb-0 text-xs text-n-slate-10">
              {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.FREE') }}
            </p>
            <article
              v-for="event in day.items"
              :key="event.id"
              class="flex gap-3 px-3.5 py-2.5 border shadow-sm rounded-xl bg-n-surface-1 border-n-weak group"
              data-teams-event
            >
              <div class="w-[72px] shrink-0 text-xs text-n-slate-11">
                <template v-if="event.all_day">{{ t('OUTSIDER_TEAMS_AREA.CALENDAR.ALL_DAY') }}</template>
                <template v-else>
                  <b class="block text-sm text-n-slate-12">{{ timeOf(event.start) }}</b>
                  {{ timeOf(event.end) }}
                </template>
              </div>
              <div class="flex-1 min-w-0">
                <h3 class="flex items-center gap-1.5 mb-0 text-sm font-semibold truncate text-n-slate-12">
                  <Icon v-if="event.online" icon="i-lucide-video" class="size-4 tms-text shrink-0" />
                  {{ event.subject || t('OUTSIDER_TEAMS_AREA.CALENDAR.NO_SUBJECT') }}
                </h3>
                <p class="mb-0 text-xs truncate text-n-slate-11">
                  {{ [event.organizer, event.location, responseText(event)].filter(Boolean).join(' · ') }}
                </p>
                <div v-if="event.attendees.length" class="flex items-center gap-1 mt-1.5">
                  <Avatar
                    v-for="person in event.attendees.slice(0, 6)"
                    :key="person.email"
                    :name="person.name || person.email"
                    :size="20"
                    rounded-full
                    :title="person.name || person.email"
                  />
                  <span v-if="event.attendees.length > 6" class="text-[11px] text-n-slate-11">
                    +{{ event.attendees.length - 6 }}
                  </span>
                </div>
              </div>
              <div class="flex items-start gap-1 shrink-0">
                <a
                  v-if="event.join_url"
                  :href="event.join_url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="px-2.5 h-8 inline-flex items-center text-xs font-semibold rounded-lg tms-accent-bg"
                >
                  {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.JOIN') }}
                </a>
                <a
                  v-if="event.web_link"
                  :href="event.web_link"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="grid rounded-lg size-8 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
                  :title="t('OUTSIDER_TEAMS_AREA.CALENDAR.OPEN')"
                >
                  <Icon icon="i-lucide-external-link" class="size-4" />
                </a>
                <button
                  type="button"
                  class="grid rounded-lg size-8 place-items-center text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-ruby-11"
                  :title="t(event.mine ? 'OUTSIDER_TEAMS_AREA.CALENDAR.CANCEL' : 'OUTSIDER_TEAMS_AREA.CALENDAR.REMOVE')"
                  @click="remove(event)"
                >
                  <Icon icon="i-lucide-trash-2" class="size-4" />
                </button>
              </div>
            </article>
          </div>
        </section>
      </template>
    </div>

    <!-- marcar reunião -->
    <div
      v-if="showForm"
      class="absolute inset-0 z-40 flex items-end justify-center bg-black/30 md:items-center"
      @click.self="showForm = false"
    >
      <form
        class="w-full max-w-lg p-5 bg-n-surface-1 rounded-t-2xl md:rounded-2xl shadow-xl flex flex-col gap-3"
        data-teams-event-form
        @submit.prevent="save"
      >
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.NEW') }}
        </h3>
        <input
          v-model="form.subject"
          type="text"
          class="!mb-0 text-sm"
          :placeholder="t('OUTSIDER_TEAMS_AREA.CALENDAR.SUBJECT')"
          maxlength="250"
          required
        />
        <div class="grid grid-cols-3 gap-2">
          <input v-model="form.date" type="date" class="!mb-0 text-sm" required />
          <input v-model="form.start" type="time" class="!mb-0 text-sm" required />
          <input v-model="form.end" type="time" class="!mb-0 text-sm" required />
        </div>
        <div class="relative">
          <div class="flex flex-wrap gap-1 mb-1">
            <span
              v-for="person in form.attendees"
              :key="person.email"
              class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full tms-soft"
            >
              {{ person.name }}
              <button type="button" @click="form.attendees = form.attendees.filter(item => item.email !== person.email)">
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </span>
          </div>
          <input
            v-model="personQuery"
            type="text"
            class="!mb-0 text-sm"
            :placeholder="t('OUTSIDER_TEAMS_AREA.CALENDAR.INVITE')"
            @keydown.enter.prevent="suggestions.length ? addPerson(suggestions[0]) : addEmail()"
          />
          <ul
            v-if="suggestions.length"
            class="absolute left-0 right-0 z-10 p-1 mt-1 overflow-hidden border shadow-lg rounded-xl bg-n-surface-1 border-n-weak"
          >
            <li
              v-for="person in suggestions"
              :key="person.email"
              class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-lg cursor-pointer hover:bg-n-alpha-1 text-n-slate-12"
              @mousedown.prevent="addPerson(person)"
            >
              <Avatar :name="person.name" :size="22" rounded-full />
              <span class="truncate">{{ person.name }}</span>
              <span class="ml-auto text-xs truncate text-n-slate-10">{{ person.email }}</span>
            </li>
          </ul>
        </div>
        <textarea
          v-model="form.body"
          rows="2"
          class="!mb-0 text-sm"
          :placeholder="t('OUTSIDER_TEAMS_AREA.CALENDAR.NOTES')"
        />
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="form.online" type="checkbox" class="!m-0" />
          {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.ONLINE') }}
        </label>
        <div class="flex justify-end gap-2 mt-1">
          <button type="button" class="px-3 h-9 text-sm rounded-xl hover:bg-n-alpha-2 text-n-slate-11" @click="showForm = false">
            {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.CLOSE') }}
          </button>
          <button
            type="submit"
            class="flex items-center gap-1.5 px-4 h-9 text-sm font-semibold rounded-xl tms-accent-bg disabled:opacity-40"
            :disabled="isSaving || !form.subject.trim()"
          >
            <Spinner v-if="isSaving" :size="14" />
            {{ t('OUTSIDER_TEAMS_AREA.CALENDAR.SAVE') }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
