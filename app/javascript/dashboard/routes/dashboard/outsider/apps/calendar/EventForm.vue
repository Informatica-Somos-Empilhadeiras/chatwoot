<script setup>
// OUTSIDER: "Marcar reunião" / "Novo evento" da Agenda dos Aplicativos: assunto, dia, horário (ou o dia inteiro),
// convidados (das suas conversas ou por e-mail), observações e se é reunião online. Vai direto para a agenda da pessoa
// na Microsoft (ou no Google); nada fica no Chatwoot. Local exato (Google Maps): escolhido no mapa, vai com as
// coordenadas e o link do Maps, e o evento mostra o Street View.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PlaceView from 'dashboard/components-next/outsider/maps/PlaceView.vue';
import SendLocationDialog from 'dashboard/components/widgets/WootWriter/outsider/SendLocationDialog.vue';
import { errorText } from '../appsErrors';
import { dayKey, timeKey } from './calendarDates';

const props = defineProps({
  api: { type: Object, required: true },
  // dia sugerido (AAAA-MM-DD) e hora (HH:MM) de onde a pessoa clicou
  day: { type: String, default: '' },
  hour: { type: String, default: '' },
  onlineLabel: { type: String, required: true },
  // OUTSIDER: agendas onde dá para marcar (a principal e as compartilhadas com edição) e a lembrada
  calendars: { type: Array, default: () => [] },
  calendarId: { type: String, default: 'primary' },
});

const emit = defineEmits(['close', 'saved']);
const { t } = useI18n();

const timeZone =
  Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Sao_Paulo';

const start = (() => {
  if (props.day) return new Date(`${props.day}T${props.hour || '09:00'}:00`);
  const now = new Date();
  now.setMinutes(now.getMinutes() < 30 ? 30 : 60, 0, 0);
  return now;
})();
const end = new Date(start);
end.setMinutes(end.getMinutes() + 30);

const form = ref({
  subject: '',
  date: dayKey(start),
  start: timeKey(start),
  end: timeKey(end),
  allDay: false,
  online: true,
  attendees: [],
  body: '',
  location: '',
});
const isSaving = ref(false);
const calendar = ref(props.calendarId);
const place = ref(null);
const pickRef = ref(null);
const onPlacePicked = picked => {
  place.value = picked;
  if (!form.value.location.trim())
    form.value.location = [picked.name, picked.address]
      .filter(Boolean)
      .filter((value, index, list) => list.indexOf(value) === index)
      .join(' - ')
      .slice(0, 250);
};
const people = ref(null);
const personQuery = ref('');

props.api
  .people()
  .then(({ data }) => {
    people.value = (data.payload || []).filter(person => person.email);
  })
  .catch(() => {
    people.value = [];
  });

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
const removePerson = email => {
  form.value.attendees = form.value.attendees.filter(
    item => item.email !== email
  );
};

const nextDay = day => {
  const date = new Date(`${day}T00:00:00`);
  date.setDate(date.getDate() + 1);
  return dayKey(date);
};

const save = async () => {
  const f = form.value;
  if (!f.subject.trim() || !f.date) return;
  isSaving.value = true;
  try {
    const { data } = await props.api.create({
      subject: f.subject.trim(),
      all_day: f.allDay,
      start: f.allDay ? `${f.date}T00:00:00` : `${f.date}T${f.start}:00`,
      end: f.allDay ? `${nextDay(f.date)}T00:00:00` : `${f.date}T${f.end}:00`,
      time_zone: timeZone,
      online: f.online && !f.allDay,
      attendees: f.attendees.map(item => item.email),
      body: f.body,
      location: f.location,
      place: place.value || undefined,
      calendar_id: calendar.value,
    });
    emit('saved', { calendar_id: calendar.value, ...data });
    useAlert(t('OUTSIDER_APPS.CAL.CREATED'));
  } catch (e) {
    useAlert(errorText(e, t));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-[9998] flex items-end justify-center bg-n-alpha-black1 backdrop-blur-[2px] md:items-center"
    @click.self="emit('close')"
  >
    <form
      class="flex flex-col w-full max-w-lg gap-3 p-5 shadow-xl bg-n-surface-1 rounded-t-2xl md:rounded-2xl"
      data-apps-event-form
      @submit.prevent="save"
    >
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ t('OUTSIDER_APPS.CAL.NEW') }}
      </h3>
      <input
        v-model="form.subject"
        type="text"
        class="!mb-0 text-sm"
        :placeholder="t('OUTSIDER_APPS.CAL.SUBJECT')"
        maxlength="250"
        required
      />
      <label
        v-if="calendars.length > 1"
        class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
      >
        {{ t('OUTSIDER_APPS.CAL.CALENDAR_FIELD') }}
        <select
          v-model="calendar"
          class="!mb-0 text-sm"
          data-apps-event-calendar
        >
          <option v-for="item in calendars" :key="item.id" :value="item.id">
            {{ item.name }}
          </option>
        </select>
      </label>
      <div
        class="grid gap-2"
        :class="form.allDay ? 'grid-cols-1' : 'grid-cols-3'"
      >
        <input v-model="form.date" type="date" class="!mb-0 text-sm" required />
        <template v-if="!form.allDay">
          <input
            v-model="form.start"
            type="time"
            class="!mb-0 text-sm"
            required
          />
          <input
            v-model="form.end"
            type="time"
            class="!mb-0 text-sm"
            required
          />
        </template>
      </div>
      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input v-model="form.allDay" type="checkbox" class="!m-0" />
        {{ t('OUTSIDER_APPS.CAL.ALL_DAY') }}
      </label>
      <input
        v-model="form.location"
        type="text"
        class="!mb-0 text-sm"
        :placeholder="t('OUTSIDER_APPS.CAL.LOCATION')"
        maxlength="250"
      />
      <div v-if="place" class="flex flex-col gap-1.5" data-apps-event-place>
        <PlaceView
          :latitude="place.latitude"
          :longitude="place.longitude"
          :height="150"
          :links="false"
        />
        <div class="flex items-center gap-2 text-xs text-n-slate-11">
          <Icon icon="i-lucide-map-pin" class="size-3.5 text-n-teal-11" />
          <span class="flex-1 min-w-0 truncate">{{ place.name }}</span>
          <button type="button" class="!p-0 underline" @click="pickRef?.open()">
            {{ t('OUTSIDER_MAPS.SCHEDULE.CHANGE') }}
          </button>
          <button type="button" class="!p-0 underline" @click="place = null">
            {{ t('OUTSIDER_MAPS.SCHEDULE.REMOVE') }}
          </button>
        </div>
      </div>
      <button
        v-else
        type="button"
        class="flex items-center gap-2 !px-3 !py-2 text-sm text-left border border-dashed rounded-lg border-n-slate-7 text-n-slate-11 hover:bg-n-alpha-1"
        data-apps-event-place-pick
        @click="pickRef?.open()"
      >
        <Icon icon="i-lucide-map-pin" class="size-4 text-n-teal-11" />
        {{ t('OUTSIDER_MAPS.SCHEDULE.PICK') }}
      </button>
      <div class="relative">
        <div v-if="form.attendees.length" class="flex flex-wrap gap-1 mb-1">
          <span
            v-for="person in form.attendees"
            :key="person.email"
            class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full oa-soft"
          >
            {{ person.name }}
            <button type="button" @click="removePerson(person.email)">
              <Icon icon="i-lucide-x" class="size-3" />
            </button>
          </span>
        </div>
        <input
          v-model="personQuery"
          type="text"
          class="!mb-0 text-sm"
          :placeholder="t(api.invite || 'OUTSIDER_APPS.CAL.INVITE')"
          @keydown.enter.prevent="
            suggestions.length ? addPerson(suggestions[0]) : addEmail()
          "
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
            <Avatar
              :name="person.name"
              :src="person.photo || ''"
              :size="22"
              rounded-full
            />
            <span class="truncate">{{ person.name }}</span>
            <span class="ml-auto text-xs truncate text-n-slate-10">{{
              person.email
            }}</span>
          </li>
        </ul>
      </div>
      <textarea
        v-model="form.body"
        rows="2"
        class="!mb-0 text-sm"
        :placeholder="t('OUTSIDER_APPS.CAL.NOTES')"
      />
      <label
        v-if="!form.allDay"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <input v-model="form.online" type="checkbox" class="!m-0" />
        {{ onlineLabel }}
      </label>
      <div class="flex justify-end gap-2 mt-1">
        <button type="button" class="oa-ghost" @click="emit('close')">
          {{ t('OUTSIDER_APPS.CLOSE') }}
        </button>
        <button
          type="submit"
          class="oa-btn"
          :disabled="isSaving || !form.subject.trim()"
        >
          <Spinner v-if="isSaving" :size="14" />
          {{ t('OUTSIDER_APPS.CAL.SAVE') }}
        </button>
      </div>
    </form>
    <SendLocationDialog ref="pickRef" mode="pick" @picked="onPlacePicked" />
  </div>
</template>
