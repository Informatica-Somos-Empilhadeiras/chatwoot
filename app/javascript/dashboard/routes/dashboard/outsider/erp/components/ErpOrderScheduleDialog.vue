<script setup>
// OUTSIDER: agendar uma OS do ERP nas agendas conectadas de quem agenda (Microsoft e/ou Google, Aplicativos) e avisar
// as pessoas: por e-mail (o convite sai do próprio Google/Microsoft) e/ou por WhatsApp (até 5 contatos, o servidor
// limita por hora). mode 'message': só um texto pelo WhatsApp sobre a OS. Abre do painel da OS (seção ERP) e do cartão
// da OS. Quem participa: o contato do cliente e o técnico já vêm; outros pela busca (contatos e colegas) ou digitando o
// e-mail. Cada pessoa tem E-mail e WhatsApp para ligar/desligar. O técnico da OS (lista do cadastro do Mais Prático) e o
// "Enviar para o app do técnico" também ficam aqui, como no agendador do quadro de OS do Mais Prático (gravam só com
// "Gravar no ERP" ligado). Ver Outsider::Erp::OrderScheduler e Outsider::Erp::Orders::Assignment.
// Local exato (Google Maps): vem o local principal do cliente (locais do contato); dá para trocar no mapa, mandar o pin
// do WhatsApp depois do aviso e guardar um local novo no cliente. O evento leva o endereço, as coordenadas e o link.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AppLogo from '../../apps/AppLogo.vue';
import PlaceView from 'dashboard/components-next/outsider/maps/PlaceView.vue';
import SendLocationDialog from 'dashboard/components/widgets/WootWriter/outsider/SendLocationDialog.vue';
import { formatCoordinates } from 'dashboard/helper/outsider/location';
import { budgetErrorMessage } from '../budgets/budgetHelpers';

const emit = defineEmits(['changed']);

const { t } = useI18n();
const isOpen = ref(false);
const mode = ref('schedule');
const target = ref({});
const loading = ref(false);
const failure = ref('');
const saving = ref(false);
const info = ref(null);

const title = ref('');
const date = ref('');
const startTime = ref('08:00');
const endTime = ref('10:00');
const allDay = ref(false);
const location = ref('');
const body = ref('');
const chosen = ref([]);
const people = ref([]);
const inboxId = ref(null);
const message = ref('');
let autoMessage = '';
const technician = ref('');
const sendApp = ref(false);
const place = ref(null);
const savePlace = ref(false);
const sendLocation = ref(false);
const pickRef = ref(null);
const openPlaceId = ref(null);

const query = ref('');
const results = ref({ contacts: [], users: [] });
const searching = ref(false);

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const timeZone = () =>
  Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Sao_Paulo';
const isSchedule = computed(() => mode.value === 'schedule');
const maxWhatsapp = computed(() => info.value?.limits?.whatsapp || 5);

const CALENDAR = {
  microsoft: {
    logo: 'mcalendar',
    label: 'OUTSIDER_ERP.ORDER.SCHEDULE.MICROSOFT',
    route: 'outsider_teams_settings',
  },
  google: {
    logo: 'gcalendar',
    label: 'OUTSIDER_ERP.ORDER.SCHEDULE.GOOGLE',
    route: 'outsider_google_settings',
  },
};

const pad = value => String(value).padStart(2, '0');
const dayOffset = offset => {
  const day = new Date();
  day.setDate(day.getDate() + offset);
  return `${day.getFullYear()}-${pad(day.getMonth() + 1)}-${pad(day.getDate())}`;
};
const brDate = value => {
  const [y, m, d] = String(value || '').split('-');
  return d ? `${d}/${m}/${y}` : '';
};
const scheduleTime = row => {
  const day = brDate(row.start.slice(0, 10));
  if (row.all_day)
    return `${day} · ${t('OUTSIDER_ERP.ORDER.SCHEDULE.ALL_DAY')}`;
  return `${day} ${row.start.slice(11, 16)}–${row.end.slice(11, 16)}`;
};

// o texto do WhatsApp com a data, a hora e o local de agora (o {contato} fica: o servidor põe o nome de cada pessoa);
// só troca enquanto a pessoa não mexeu no texto
const fillMessage = () => {
  if (!info.value || message.value !== autoMessage) return;
  const template = isSchedule.value
    ? info.value.texts.schedule
    : info.value.texts.message;
  const local = location.value.trim();
  let text = template
    .replaceAll('{numero}', String(target.value.code))
    .replaceAll('{data}', brDate(date.value))
    .replaceAll(
      '{hora}',
      allDay.value ? t('OUTSIDER_ERP.ORDER.SCHEDULE.ALL_DAY') : startTime.value
    );
  text = local
    ? text.replaceAll('{local}', local)
    : text.replace(/\n?[^\n]*\{local\}[^\n]*/g, '');
  message.value = text;
  autoMessage = text;
};

const personKey = person =>
  person.contactId ? `c${person.contactId}` : `e${person.email.toLowerCase()}`;

const addPerson = (person, { email = true, whatsapp = true } = {}) => {
  const row = {
    name: person.name || person.email,
    email: person.email || '',
    phone: person.phone_number || person.phone || '',
    contactId: person.contactId || null,
    kind: person.kind || '',
  };
  const key = personKey(row);
  const existing = people.value.find(
    item =>
      personKey(item) === key ||
      (row.email &&
        item.email &&
        item.email.toLowerCase() === row.email.toLowerCase())
  );
  if (existing) {
    if (!existing.contactId && row.contactId) {
      existing.contactId = row.contactId;
      existing.phone = row.phone;
    }
    return existing;
  }
  const whatsappCount = people.value.filter(item => item.viaWhatsapp).length;
  people.value.push({
    ...row,
    viaEmail: isSchedule.value && email && !!row.email,
    viaWhatsapp:
      whatsapp &&
      !!row.contactId &&
      !!row.phone &&
      whatsappCount < maxWhatsapp.value,
  });
  return people.value[people.value.length - 1];
};

const load = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await ErpAPI.orderSchedule({
      company: target.value.company,
      code: target.value.code,
      time_zone: timeZone(),
    });
    info.value = data;
    title.value = data.event.title;
    location.value = data.event.location || '';
    body.value = data.event.body || '';
    // a previsão da OS, se ainda não passou; senão amanhã
    date.value =
      data.event.date && data.event.date >= dayOffset(0)
        ? data.event.date
        : dayOffset(1);
    chosen.value = data.calendars
      .filter(item => item.ready)
      .map(item => item.provider);
    inboxId.value = data.inbox_id || data.inboxes[0]?.id || null;
    technician.value = data.order.tecnico_codigo
      ? String(data.order.tecnico_codigo)
      : '';
    sendApp.value = false;
    place.value = data.places?.[0] || null;
    savePlace.value = false;
    sendLocation.value = !!place.value;
    openPlaceId.value = null;
    data.suggestions.whatsapp.forEach(contact =>
      addPerson({ ...contact, contactId: contact.id, kind: 'contact' })
    );
    // só um texto no WhatsApp: quem não tem WhatsApp (o técnico pelo e-mail) não entra
    data.suggestions.emails
      .filter(row => isSchedule.value && row.kind !== 'client')
      .forEach(row => addPerson(row, { whatsapp: false }));
    autoMessage = '';
    message.value = '';
    fillMessage();
  } catch (error) {
    failure.value = budgetErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

// options: { company, code }; mode: schedule | message
const open = (options, openMode = 'schedule') => {
  target.value = options;
  mode.value = openMode;
  info.value = null;
  people.value = [];
  query.value = '';
  results.value = { contacts: [], users: [] };
  allDay.value = false;
  startTime.value = '08:00';
  endTime.value = '10:00';
  isOpen.value = true;
  load();
};

const close = () => {
  isOpen.value = false;
};

const samePoint = (a, b) =>
  Number(a.latitude).toFixed(6) === Number(b.latitude).toFixed(6) &&
  Number(a.longitude).toFixed(6) === Number(b.longitude).toFixed(6);

// local escolhido no mapa: se ainda não é do cliente, já vem marcado para guardar nele
const onPlacePicked = picked => {
  const known = (info.value?.places || []).find(item =>
    samePoint(item, picked)
  );
  place.value = known || { ...picked, name: picked.name || picked.address };
  savePlace.value = !known && !!info.value?.order?.contact_id;
  sendLocation.value = true;
  if (!location.value.trim() && place.value.address)
    location.value = place.value.address;
};

const placePayload = () =>
  place.value
    ? {
        name: place.value.name,
        address: place.value.address || '',
        latitude: place.value.latitude,
        longitude: place.value.longitude,
      }
    : undefined;

const clientEmails = computed(() =>
  (info.value?.suggestions.emails || []).filter(
    row =>
      row.kind === 'client' &&
      !people.value.some(
        person => person.email.toLowerCase() === row.email.toLowerCase()
      )
  )
);

const search = debounce(async () => {
  const term = query.value.trim();
  if (term.length < 2 || EMAIL.test(term)) {
    results.value = { contacts: [], users: [] };
    return;
  }
  searching.value = true;
  try {
    const { data } = await ErpAPI.orderPeople(term);
    results.value = data;
  } catch {
    results.value = { contacts: [], users: [] };
  } finally {
    searching.value = false;
  }
}, 300);

const clearSearch = () => {
  query.value = '';
  results.value = { contacts: [], users: [] };
};

const pickContact = contact => {
  addPerson({ ...contact, contactId: contact.id, kind: 'contact' });
  clearSearch();
};

const pickUser = user => {
  addPerson({ ...user, kind: 'user' }, { whatsapp: false });
  clearSearch();
};

// e-mail digitado + Enter vira um convidado só por e-mail
const onQueryKey = event => {
  if (event.key !== 'Enter') return;
  event.preventDefault();
  const term = query.value.trim();
  if (EMAIL.test(term) && isSchedule.value) {
    addPerson({ email: term, name: term, kind: 'typed' }, { whatsapp: false });
    clearSearch();
  } else if (results.value.contacts[0]) pickContact(results.value.contacts[0]);
};

const whatsappPeople = computed(() =>
  people.value.filter(person => person.viaWhatsapp)
);
const emailPeople = computed(() =>
  people.value.filter(person => person.viaEmail)
);

const toggleWhatsapp = person => {
  if (!person.contactId || !person.phone) return;
  if (!person.viaWhatsapp && whatsappPeople.value.length >= maxWhatsapp.value) {
    useAlert(
      t('OUTSIDER_ERP.ORDER.SCHEDULE.WHATSAPP_MAX', { max: maxWhatsapp.value })
    );
    return;
  }
  person.viaWhatsapp = !person.viaWhatsapp;
};

const toggleEmail = person => {
  if (person.email) person.viaEmail = !person.viaEmail;
};

const removePerson = index => people.value.splice(index, 1);

const toggleCalendar = provider => {
  const index = chosen.value.indexOf(provider);
  if (index >= 0) chosen.value.splice(index, 1);
  else chosen.value.push(provider);
};

const nextDay = value => {
  const day = new Date(`${value}T12:00:00`);
  day.setDate(day.getDate() + 1);
  return `${day.getFullYear()}-${pad(day.getMonth() + 1)}-${pad(day.getDate())}`;
};

const technicianOptions = computed(() => {
  const list = info.value?.technicians || [];
  const current = info.value?.order;
  // o técnico que já está na OS sempre aparece, mesmo fora da lista
  if (
    current?.tecnico_codigo &&
    !list.some(row => Number(row.codigo) === current.tecnico_codigo)
  )
    return [
      { codigo: current.tecnico_codigo, nome: current.tecnico || '' },
      ...list,
    ];
  return list;
});
const technicianName = name =>
  String(name || '')
    .toLowerCase()
    .replace(/(^|\s)\S/g, letter => letter.toUpperCase());
const canAssign = computed(() => !!info.value?.erp_write);
const onTechnician = () => {
  if (!technician.value) sendApp.value = false;
};

const timesValid = computed(
  () => allDay.value || (startTime.value && endTime.value > startTime.value)
);

const whatsappReady = computed(
  () =>
    !whatsappPeople.value.length ||
    (inboxId.value && message.value.trim().length > 0)
);

const canSave = computed(() => {
  if (!info.value || saving.value) return false;
  if (!isSchedule.value)
    return whatsappPeople.value.length > 0 && whatsappReady.value;
  return (
    chosen.value.length > 0 &&
    title.value.trim() &&
    date.value &&
    timesValid.value &&
    whatsappReady.value
  );
});

const whatsappPayload = () =>
  whatsappPeople.value.length
    ? {
        contact_ids: whatsappPeople.value.map(person => person.contactId),
        inbox_id: inboxId.value,
        message: message.value,
        send_location: isSchedule.value && !!place.value && sendLocation.value,
      }
    : undefined;

const calendarNames = providers =>
  providers.map(provider => t(CALENDAR[provider].label)).join(', ');

// o que aconteceu com o técnico e o app (só as partes pedidas voltam)
const assignmentText = data => {
  const parts = [];
  if (data.technician)
    parts.push(
      data.technician.ok
        ? t('OUTSIDER_ERP.ORDER.SCHEDULE.TECHNICIAN_DONE', {
            name: technicianName(data.technician.name),
          })
        : t('OUTSIDER_ERP.ORDER.SCHEDULE.TECHNICIAN_FAILED')
    );
  if (data.app)
    parts.push(
      data.app.ok
        ? t('OUTSIDER_ERP.ORDER.SCHEDULE.APP_DONE')
        : t('OUTSIDER_ERP.ORDER.SCHEDULE.APP_FAILED')
    );
  return parts.length ? ` ${parts.join(' ')}` : '';
};

const schedule = async () => {
  const { data } = await ErpAPI.createOrderSchedule({
    company: target.value.company,
    code: target.value.code,
    time_zone: timeZone(),
    title: title.value,
    start: `${date.value}T${allDay.value ? '00:00' : startTime.value}`,
    end: allDay.value
      ? `${nextDay(date.value)}T00:00`
      : `${date.value}T${endTime.value}`,
    all_day: allDay.value,
    location: location.value,
    body: body.value,
    calendars: chosen.value,
    attendees: emailPeople.value.map(person => person.email),
    whatsapp: whatsappPayload(),
    place: placePayload(),
    save_place: !!place.value && savePlace.value,
    tecnico: canAssign.value && technician.value ? technician.value : undefined,
    enviar_app: canAssign.value && sendApp.value && !!technician.value,
  });
  const done = data.results.filter(row => row.ok).map(row => row.provider);
  const failed = data.results.filter(row => !row.ok).map(row => row.provider);
  useAlert(
    t('OUTSIDER_ERP.ORDER.SCHEDULE.DONE', { calendars: calendarNames(done) }) +
      (data.whatsapp
        ? ` ${t('OUTSIDER_ERP.ORDER.SCHEDULE.WHATSAPP_DONE', { count: data.whatsapp })}`
        : '') +
      (failed.length
        ? ` ${t('OUTSIDER_ERP.ORDER.SCHEDULE.PARTIAL', { calendars: calendarNames(failed) })}`
        : '') +
      ` ${
        data.substatus?.ok
          ? t('OUTSIDER_ERP.ORDER.SCHEDULE.SUBSTATUS_DONE', {
              value: data.substatus.value,
            })
          : t('OUTSIDER_ERP.ORDER.SCHEDULE.SUBSTATUS_SKIPPED')
      }` +
      assignmentText(data)
  );
  return data;
};

const sendMessage = async () => {
  const { data } = await ErpAPI.orderMessage({
    company: target.value.company,
    code: target.value.code,
    ...whatsappPayload(),
  });
  useAlert(
    t('OUTSIDER_ERP.ORDER.SCHEDULE.WHATSAPP_DONE', { count: data.sent })
  );
};

const errorText = error => {
  const reason = String(error?.response?.data?.reason || '');
  if (reason.startsWith('calendar_failed'))
    return t('OUTSIDER_ERP.BUDGET.REASONS.CALENDAR_FAILED', {
      detail: reason.split(':').slice(1).join(':').slice(0, 120),
    });
  return budgetErrorMessage(t, error);
};

const save = async () => {
  saving.value = true;
  try {
    const result = isSchedule.value ? await schedule() : await sendMessage();
    emit('changed', result);
    close();
  } catch (error) {
    useAlert(errorText(error));
  } finally {
    saving.value = false;
  }
};

const cancelSchedule = async row => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('OUTSIDER_ERP.ORDER.SCHEDULE.CANCEL_CONFIRM'))) return;
  try {
    await ErpAPI.cancelOrderSchedule(row.id);
    info.value.schedules = info.value.schedules.filter(
      item => item.id !== row.id
    );
    useAlert(t('OUTSIDER_ERP.ORDER.SCHEDULE.CANCELLED'));
    emit('changed');
  } catch (error) {
    useAlert(errorText(error));
  }
};

const KIND_LABEL = {
  contact: 'OUTSIDER_ERP.ORDER.SCHEDULE.KIND_CONTACT',
  technician: 'OUTSIDER_ERP.ORDER.SCHEDULE.KIND_TECHNICIAN',
  user: 'OUTSIDER_ERP.ORDER.SCHEDULE.KIND_USER',
  client: 'OUTSIDER_ERP.ORDER.SCHEDULE.KIND_CLIENT',
};

defineExpose({ open, isOpen });

const INPUT =
  '!mb-0 w-full h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
const LABEL =
  'flex flex-col gap-1 text-[11px] font-medium tracking-wide uppercase text-n-slate-10';
const SECTION = 'flex flex-col gap-2.5';
const HEADING = 'mb-0 text-sm font-semibold text-n-slate-12';
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[10000] flex items-stretch justify-center bg-n-alpha-black1 backdrop-blur-[2px] sm:items-center sm:p-6"
      data-erp-schedule
      @keydown.esc="close"
      @click.self="close"
    >
      <div
        class="flex flex-col w-full max-w-3xl overflow-hidden shadow-xl sm:max-h-full sm:rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
      >
        <header
          class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
        >
          <span class="flex flex-col min-w-0">
            <span class="text-sm font-semibold truncate text-n-slate-12">
              {{
                isSchedule
                  ? t('OUTSIDER_ERP.ORDER.SCHEDULE.TITLE', {
                      code: target.code,
                    })
                  : t('OUTSIDER_ERP.ORDER.SCHEDULE.MESSAGE_TITLE', {
                      code: target.code,
                    })
              }}
            </span>
            <span
              v-if="info"
              class="text-xs truncate text-n-slate-10"
              data-erp-schedule-order
            >
              {{
                [
                  info.order.cliente,
                  info.order.atendimento,
                  info.order.equipamento,
                  info.order.tecnico,
                ]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </span>
          <Button
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :aria-label="t('OUTSIDER_ERP.CANCEL')"
            @click="close"
          />
        </header>

        <div v-if="loading" class="flex justify-center flex-1 p-10">
          <Spinner class="text-n-slate-10" />
        </div>
        <p v-else-if="failure" class="p-5 mb-0 text-sm text-n-ruby-11">
          {{ failure }}
          <button type="button" class="underline" @click="load">
            {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
          </button>
        </p>

        <div
          v-else-if="info"
          class="flex flex-col flex-1 min-h-0 gap-5 p-4 overflow-y-auto sm:p-5"
        >
          <!-- agendamentos que já existem -->
          <section
            v-if="isSchedule && info.schedules.length"
            :class="SECTION"
            data-erp-schedule-existing
          >
            <h4 :class="HEADING">
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.EXISTING') }}
            </h4>
            <div
              v-for="row in info.schedules"
              :key="row.id"
              class="flex flex-wrap items-center gap-2 px-3 py-2 text-sm rounded-lg bg-n-alpha-1"
            >
              <Icon
                icon="i-lucide-calendar-check"
                class="size-4 text-n-teal-11"
              />
              <span class="flex-1 min-w-0">
                <span class="font-medium text-n-slate-12">
                  {{ scheduleTime(row) }}
                </span>
                <span class="text-n-slate-11">
                  · {{ row.title }} · {{ row.user }}
                </span>
              </span>
              <a
                v-for="cal in row.calendars"
                :key="cal.provider"
                :href="cal.web_link"
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-1 text-xs text-n-brand hover:underline"
              >
                <AppLogo :name="CALENDAR[cal.provider].logo" :size="14" />
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.OPEN') }}
              </a>
              <button
                v-if="row.place"
                type="button"
                class="flex items-center gap-1 !p-0 text-xs text-n-brand hover:underline"
                data-erp-schedule-place-toggle
                @click="openPlaceId = openPlaceId === row.id ? null : row.id"
              >
                <Icon icon="i-lucide-map-pin" class="size-3.5" />
                {{ t('OUTSIDER_MAPS.SCHEDULE.SEE_PLACE') }}
              </button>
              <button
                v-if="row.mine"
                type="button"
                class="text-xs text-n-ruby-11 hover:underline"
                @click="cancelSchedule(row)"
              >
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.CANCEL') }}
              </button>
              <PlaceView
                v-if="row.place && openPlaceId === row.id"
                class="w-full"
                :latitude="row.place.latitude"
                :longitude="row.place.longitude"
                :height="200"
              />
            </div>
          </section>

          <!-- quando -->
          <section v-if="isSchedule" :class="SECTION">
            <h4 :class="HEADING">
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.WHEN') }}
            </h4>
            <label :class="LABEL">
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.EVENT_TITLE') }}
              <input
                v-model="title"
                maxlength="250"
                :class="INPUT"
                class="normal-case"
                data-erp-schedule-title
              />
            </label>
            <div class="grid grid-cols-2 gap-2 sm:grid-cols-[1.4fr_1fr_1fr]">
              <label :class="LABEL" class="col-span-2 sm:col-span-1">
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.DATE') }}
                <input
                  v-model="date"
                  type="date"
                  :class="INPUT"
                  data-erp-schedule-date
                  @change="fillMessage"
                />
              </label>
              <label :class="LABEL">
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.START') }}
                <input
                  v-model="startTime"
                  type="time"
                  :disabled="allDay"
                  :class="INPUT"
                  class="disabled:opacity-50"
                  @change="fillMessage"
                />
              </label>
              <label :class="LABEL">
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.END') }}
                <input
                  v-model="endTime"
                  type="time"
                  :disabled="allDay"
                  :class="INPUT"
                  class="disabled:opacity-50"
                />
              </label>
            </div>
            <label
              class="flex items-center gap-2 text-sm cursor-pointer text-n-slate-12"
            >
              <input
                v-model="allDay"
                type="checkbox"
                class="!m-0"
                @change="fillMessage"
              />
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.ALL_DAY') }}
            </label>
            <p
              v-if="!timesValid"
              class="mb-0 text-xs text-n-ruby-11"
              data-erp-schedule-time-error
            >
              {{ t('OUTSIDER_ERP.BUDGET.REASONS.INVALID_TIME') }}
            </p>
            <label :class="LABEL">
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.LOCATION') }}
              <input
                v-model="location"
                maxlength="250"
                :class="INPUT"
                class="normal-case"
                @change="fillMessage"
              />
            </label>
            <!-- local exato no mapa (Google Maps) -->
            <div class="flex flex-col gap-1.5" data-erp-schedule-place>
              <span :class="LABEL">
                {{ t('OUTSIDER_MAPS.SCHEDULE.PLACE') }}
              </span>
              <div
                v-if="place"
                class="flex flex-col gap-2 p-2.5 border rounded-lg border-n-weak bg-n-solid-1"
              >
                <PlaceView
                  :latitude="place.latitude"
                  :longitude="place.longitude"
                  :height="190"
                  :links="false"
                />
                <div class="flex items-start justify-between gap-2">
                  <span class="flex flex-col min-w-0">
                    <span class="text-sm font-medium text-n-slate-12">
                      {{ place.name || formatCoordinates(place) }}
                    </span>
                    <span class="text-xs text-n-slate-11">
                      {{
                        place.id
                          ? t('OUTSIDER_MAPS.SCHEDULE.FROM_CLIENT')
                          : place.address || formatCoordinates(place)
                      }}
                    </span>
                  </span>
                  <span class="flex items-center gap-1 shrink-0">
                    <Button
                      size="xs"
                      variant="faded"
                      color="slate"
                      :label="t('OUTSIDER_MAPS.SCHEDULE.CHANGE')"
                      data-erp-schedule-place-change
                      @click="pickRef?.open()"
                    />
                    <Button
                      size="xs"
                      variant="ghost"
                      color="slate"
                      icon="i-lucide-x"
                      :aria-label="t('OUTSIDER_MAPS.SCHEDULE.REMOVE')"
                      @click="place = null"
                    />
                  </span>
                </div>
                <label
                  v-if="!place.id && info.order.contact_id"
                  class="flex items-center gap-2 text-sm cursor-pointer text-n-slate-12"
                >
                  <input
                    v-model="savePlace"
                    type="checkbox"
                    class="!m-0"
                    data-erp-schedule-save-place
                  />
                  {{ t('OUTSIDER_MAPS.SCHEDULE.SAVE_ON_CLIENT') }}
                </label>
              </div>
              <button
                v-else
                type="button"
                class="flex items-center gap-2 !px-3 !py-2.5 text-sm text-left border border-dashed rounded-lg border-n-slate-7 text-n-slate-11 hover:bg-n-alpha-1"
                data-erp-schedule-place-pick
                @click="pickRef?.open()"
              >
                <Icon icon="i-lucide-map-pin" class="size-4 text-n-teal-11" />
                {{ t('OUTSIDER_MAPS.SCHEDULE.PICK') }}
              </button>
            </div>
            <label :class="LABEL">
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.DESCRIPTION') }}
              <textarea
                v-model="body"
                rows="4"
                maxlength="4000"
                class="!mb-0 w-full px-2.5 py-2 text-sm normal-case rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand resize-y"
              />
            </label>
          </section>

          <!-- técnico e app do técnico (como o agendador do quadro do Mais Prático) -->
          <section
            v-if="isSchedule"
            :class="SECTION"
            data-erp-schedule-technician
          >
            <h4 :class="HEADING">
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.TECHNICIAN') }}
            </h4>
            <div class="grid items-end gap-2 sm:grid-cols-[1fr_auto]">
              <label :class="LABEL">
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.TECHNICIAN_LABEL') }}
                <select
                  v-model="technician"
                  :disabled="!canAssign"
                  :class="INPUT"
                  class="normal-case disabled:opacity-50"
                  data-erp-schedule-tecnico
                  @change="onTechnician"
                >
                  <option value="">
                    {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.TECHNICIAN_NONE') }}
                  </option>
                  <option
                    v-for="row in technicianOptions"
                    :key="row.codigo"
                    :value="String(row.codigo)"
                  >
                    {{ technicianName(row.nome) || row.codigo }}
                  </option>
                </select>
              </label>
              <label
                class="flex items-center h-9 gap-2 text-sm cursor-pointer text-n-slate-12"
                :class="{
                  'opacity-50 cursor-not-allowed': !canAssign || !technician,
                }"
              >
                <input
                  v-model="sendApp"
                  type="checkbox"
                  class="!m-0"
                  :disabled="!canAssign || !technician"
                  data-erp-schedule-app
                />
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.SEND_APP') }}
              </label>
            </div>
            <p class="mb-0 text-xs text-n-slate-10">
              {{
                canAssign
                  ? t('OUTSIDER_ERP.ORDER.SCHEDULE.TECHNICIAN_HINT')
                  : t('OUTSIDER_ERP.ORDER.SCHEDULE.TECHNICIAN_OFF')
              }}
            </p>
          </section>

          <!-- agendas -->
          <section v-if="isSchedule" :class="SECTION">
            <h4 :class="HEADING">
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.CALENDARS') }}
            </h4>
            <div class="grid gap-2 sm:grid-cols-2">
              <button
                v-for="cal in info.calendars"
                :key="cal.provider"
                type="button"
                class="flex items-center gap-3 p-3 text-left border rounded-xl disabled:cursor-default"
                :class="
                  chosen.includes(cal.provider)
                    ? 'border-n-brand bg-n-brand/5'
                    : 'border-n-weak bg-n-solid-1'
                "
                :disabled="!cal.ready"
                :data-erp-schedule-calendar="cal.provider"
                @click="toggleCalendar(cal.provider)"
              >
                <AppLogo :name="CALENDAR[cal.provider].logo" :size="28" />
                <span class="flex flex-col flex-1 min-w-0">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ t(CALENDAR[cal.provider].label) }}
                  </span>
                  <span
                    v-if="cal.ready"
                    class="text-xs truncate text-n-slate-10"
                  >
                    {{ cal.email }}
                  </span>
                  <router-link
                    v-else
                    :to="{ name: CALENDAR[cal.provider].route }"
                    class="text-xs text-n-brand hover:underline"
                    @click.stop="close"
                  >
                    {{
                      t(
                        cal.reason === 'not_connected'
                          ? 'OUTSIDER_ERP.ORDER.SCHEDULE.CONNECT'
                          : 'OUTSIDER_ERP.ORDER.SCHEDULE.RECONNECT'
                      )
                    }}
                  </router-link>
                </span>
                <Icon
                  v-if="cal.ready"
                  :icon="
                    chosen.includes(cal.provider)
                      ? 'i-lucide-check-circle-2'
                      : 'i-lucide-circle'
                  "
                  class="size-5"
                  :class="
                    chosen.includes(cal.provider)
                      ? 'text-n-brand'
                      : 'text-n-slate-8'
                  "
                />
              </button>
            </div>
            <p
              v-if="!info.calendars.some(cal => cal.ready)"
              class="p-2 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
            >
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.NO_CALENDAR') }}
            </p>
          </section>

          <!-- quem participa -->
          <section :class="SECTION">
            <h4 :class="HEADING">
              {{
                isSchedule
                  ? t('OUTSIDER_ERP.ORDER.SCHEDULE.PEOPLE')
                  : t('OUTSIDER_ERP.ORDER.SCHEDULE.PEOPLE_WHATSAPP')
              }}
            </h4>
            <div
              v-for="(person, index) in people"
              :key="personKey(person)"
              class="flex flex-wrap items-center gap-2 px-3 py-2 rounded-lg sm:flex-nowrap bg-n-alpha-1"
              data-erp-schedule-person
            >
              <span class="flex flex-col flex-1 min-w-0">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ person.name }}
                  <span
                    v-if="KIND_LABEL[person.kind]"
                    class="ml-1 text-[11px] font-normal text-n-slate-10"
                  >
                    {{ t(KIND_LABEL[person.kind]) }}
                  </span>
                </span>
                <span class="text-xs truncate text-n-slate-10">
                  {{ [person.email, person.phone].filter(Boolean).join(' · ') }}
                </span>
              </span>
              <button
                v-if="isSchedule"
                type="button"
                class="flex items-center gap-1 px-2 py-1 text-xs rounded-full disabled:opacity-40"
                :class="
                  person.viaEmail
                    ? 'bg-n-blue-3 text-n-blue-11'
                    : 'bg-n-alpha-2 text-n-slate-10'
                "
                :disabled="!person.email"
                :title="t('OUTSIDER_ERP.ORDER.SCHEDULE.VIA_EMAIL_HINT')"
                data-erp-schedule-via="email"
                @click="toggleEmail(person)"
              >
                <Icon icon="i-lucide-mail" class="size-3.5" />
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.VIA_EMAIL') }}
              </button>
              <button
                type="button"
                class="flex items-center gap-1 px-2 py-1 text-xs rounded-full disabled:opacity-40"
                :class="
                  person.viaWhatsapp
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-alpha-2 text-n-slate-10'
                "
                :disabled="!person.contactId || !person.phone"
                :title="t('OUTSIDER_ERP.ORDER.SCHEDULE.VIA_WHATSAPP_HINT')"
                data-erp-schedule-via="whatsapp"
                @click="toggleWhatsapp(person)"
              >
                <Icon icon="i-lucide-message-circle" class="size-3.5" />
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.VIA_WHATSAPP') }}
              </button>
              <button
                type="button"
                class="grid rounded-md size-7 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
                :aria-label="t('OUTSIDER_ERP.ORDER.SCHEDULE.REMOVE')"
                @click="removePerson(index)"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>

            <div class="relative">
              <div
                class="flex items-center gap-2 px-2.5 rounded-lg bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-slate-6 focus-within:outline-n-brand"
              >
                <Icon icon="i-lucide-search" class="size-4 text-n-slate-10" />
                <input
                  v-model="query"
                  :placeholder="
                    isSchedule
                      ? t('OUTSIDER_ERP.ORDER.SCHEDULE.SEARCH')
                      : t('OUTSIDER_ERP.ORDER.SCHEDULE.SEARCH_WHATSAPP')
                  "
                  class="!mb-0 flex-1 h-9 text-sm reset-base bg-transparent text-n-slate-12 !outline-none !shadow-none !border-0"
                  data-erp-schedule-search
                  @input="search"
                  @keydown="onQueryKey"
                />
                <Spinner v-if="searching" :size="14" />
              </div>
              <div
                v-if="
                  results.contacts.length ||
                  (isSchedule && results.users.length)
                "
                class="absolute z-10 flex flex-col w-full gap-0.5 p-1 mt-1 overflow-y-auto border shadow-lg max-h-64 rounded-xl border-n-weak bg-n-solid-2"
              >
                <button
                  v-for="row in results.contacts"
                  :key="`c${row.id}`"
                  type="button"
                  class="flex items-center gap-2 px-2 py-1.5 text-left rounded-lg hover:bg-n-alpha-2 disabled:opacity-50"
                  :disabled="!isSchedule && !row.phone_number"
                  data-erp-schedule-result
                  @click="pickContact(row)"
                >
                  <Icon icon="i-lucide-user" class="size-4 text-n-slate-10" />
                  <span class="flex flex-col min-w-0">
                    <span class="text-sm truncate text-n-slate-12">
                      {{ row.name }}
                    </span>
                    <span class="text-xs truncate text-n-slate-10">
                      {{
                        [row.email, row.phone_number, row.company_name]
                          .filter(Boolean)
                          .join(' · ')
                      }}
                    </span>
                  </span>
                </button>
                <template v-if="isSchedule">
                  <button
                    v-for="row in results.users"
                    :key="`u${row.id}`"
                    type="button"
                    class="flex items-center gap-2 px-2 py-1.5 text-left rounded-lg hover:bg-n-alpha-2"
                    @click="pickUser(row)"
                  >
                    <Icon
                      icon="i-lucide-briefcase"
                      class="size-4 text-n-slate-10"
                    />
                    <span class="flex flex-col min-w-0">
                      <span class="text-sm truncate text-n-slate-12">
                        {{ row.name }}
                        <span class="text-[11px] text-n-slate-10">
                          {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.KIND_USER') }}
                        </span>
                      </span>
                      <span class="text-xs truncate text-n-slate-10">
                        {{ row.email }}
                      </span>
                    </span>
                  </button>
                </template>
              </div>
            </div>
            <div
              v-if="isSchedule && clientEmails.length"
              class="flex flex-wrap items-center gap-1.5 text-xs text-n-slate-10"
            >
              {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.CLIENT_EMAILS') }}
              <button
                v-for="row in clientEmails"
                :key="row.email"
                type="button"
                class="px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
                @click="
                  addPerson({ ...row, kind: 'client' }, { whatsapp: false })
                "
              >
                + {{ row.email }}
              </button>
            </div>
            <span class="text-xs text-n-slate-10">
              {{
                isSchedule
                  ? t('OUTSIDER_ERP.ORDER.SCHEDULE.PEOPLE_HINT', {
                      max: maxWhatsapp,
                    })
                  : t('OUTSIDER_ERP.ORDER.SCHEDULE.WHATSAPP_HINT', {
                      max: maxWhatsapp,
                    })
              }}
            </span>
          </section>

          <!-- WhatsApp -->
          <section
            v-if="whatsappPeople.length"
            :class="SECTION"
            data-erp-schedule-whatsapp
          >
            <h4 :class="HEADING">
              {{
                t('OUTSIDER_ERP.ORDER.SCHEDULE.WHATSAPP_TITLE', {
                  count: whatsappPeople.length,
                  max: maxWhatsapp,
                })
              }}
            </h4>
            <label :class="LABEL">
              {{ t('OUTSIDER_ERP.BUDGET.SEND.INBOX') }}
              <span
                v-if="!info.inboxes.length"
                class="text-sm font-normal normal-case text-n-ruby-11"
              >
                {{ t('OUTSIDER_ERP.BUDGET.SEND.NO_INBOX') }}
              </span>
              <select
                v-else
                v-model.number="inboxId"
                :class="INPUT"
                class="normal-case !pr-7 bg-[right_-1.25rem_center]"
              >
                <option
                  v-for="inbox in info.inboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
            </label>
            <label :class="LABEL">
              {{ t('OUTSIDER_ERP.BUDGET.SEND.MESSAGE') }}
              <textarea
                v-model="message"
                rows="4"
                maxlength="4000"
                class="!mb-0 w-full px-2.5 py-2 text-sm normal-case rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand resize-y"
                data-erp-schedule-message
              />
              <span class="text-xs font-normal normal-case text-n-slate-10">
                {{ t('OUTSIDER_ERP.ORDER.SCHEDULE.MESSAGE_HINT') }}
              </span>
            </label>
            <label
              v-if="isSchedule && place"
              class="flex items-start gap-2 text-sm cursor-pointer text-n-slate-12"
            >
              <input
                v-model="sendLocation"
                type="checkbox"
                class="!m-0 mt-0.5"
                data-erp-schedule-send-location
              />
              <span class="flex flex-col">
                {{ t('OUTSIDER_MAPS.SCHEDULE.SEND_LOCATION') }}
                <span class="text-xs text-n-slate-10">
                  {{ t('OUTSIDER_MAPS.SCHEDULE.SEND_LOCATION_HINT') }}
                </span>
              </span>
            </label>
          </section>
        </div>

        <footer
          v-if="info"
          class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-t border-n-weak"
        >
          <span class="text-xs text-n-slate-10">
            {{
              isSchedule
                ? t('OUTSIDER_ERP.ORDER.SCHEDULE.FOOTER', {
                    emails: emailPeople.length,
                    whatsapp: whatsappPeople.length,
                  })
                : t('OUTSIDER_ERP.ORDER.SCHEDULE.FOOTER_MESSAGE', {
                    whatsapp: whatsappPeople.length,
                  })
            }}
          </span>
          <Button
            :label="
              isSchedule
                ? t('OUTSIDER_ERP.ORDER.SCHEDULE.SAVE')
                : t('OUTSIDER_ERP.BUDGET.SEND.SEND_WHATSAPP')
            "
            :icon="
              isSchedule ? 'i-lucide-calendar-plus' : 'i-lucide-message-circle'
            "
            :is-loading="saving"
            :disabled="!canSave"
            data-erp-schedule-save
            @click="save"
          />
        </footer>
      </div>
    </div>
    <SendLocationDialog
      v-if="isOpen && info"
      ref="pickRef"
      mode="pick"
      :places="info.places || []"
      @picked="onPlacePicked"
    />
  </Teleport>
</template>
