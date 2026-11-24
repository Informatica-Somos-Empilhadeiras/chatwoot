<script setup>
// OUTSIDER: escrever e-mail nos Aplicativos: Novo, Responder, Responder a todos e Encaminhar. Para/Cc com sugestões
// (pessoas das suas conversas do Teams) ou e-mail digitado, assunto, texto e anexos (clique ou arraste). Na resposta e no
// encaminhar o e-mail original vai citado embaixo, como no Outlook. Sai pela conta da pessoa e fica nos Enviados dela.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AppsAPI from 'dashboard/api/outsider/apps';
import { formatSize } from 'dashboard/components-next/outsider/mediaViewer/mediaHelpers';
import { errorText } from '../appsErrors';
import { providerOf, textKey } from '../providers';
import { peopleText, replySubject } from './mailHelpers';

const props = defineProps({
  provider: { type: String, required: true },
  // 'new' | 'reply' | 'reply_all' | 'forward'
  mode: { type: String, default: 'new' },
  source: { type: Object, default: null },
});

const emit = defineEmits(['close', 'sent']);
const { t } = useI18n();

const MAX_TOTAL = 100 * 1024 * 1024;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const isReply = computed(() => ['reply', 'reply_all'].includes(props.mode));
const to = ref([]);
const cc = ref([]);
const showCc = ref(false);
const subject = ref(
  props.source
    ? replySubject(props.mode, props.source.subject, props.provider)
    : ''
);
const text = ref('');
const files = ref([]);
const isSending = ref(false);
const dragging = ref(false);
const fileInput = ref(null);
const people = ref([]);
const query = ref({ to: '', cc: '' });

providerOf(props.provider)
  .calendar.people()
  .then(({ data }) => {
    people.value = (data.payload || []).filter(person => person.email);
  })
  .catch(() => {});

const title = computed(
  () =>
    ({
      reply: t('OUTSIDER_APPS.MAIL.REPLY'),
      reply_all: t('OUTSIDER_APPS.MAIL.REPLY_ALL'),
      forward: t('OUTSIDER_APPS.MAIL.FORWARD'),
    })[props.mode] || t('OUTSIDER_APPS.MAIL.NEW')
);

// na resposta a Microsoft já põe o remetente (e todos, em Responder a todos); aqui só mostra
const replyTo = computed(() => {
  if (!isReply.value || !props.source) return '';
  const list = [
    props.source.from,
    ...(props.mode === 'reply_all' ? props.source.to || [] : []),
  ];
  return peopleText(list.filter(Boolean));
});

const listOf = field => (field === 'to' ? to : cc);

const suggestions = field => {
  const q = query.value[field].trim().toLowerCase();
  if (!q) return [];
  const chosen = new Set([...to.value, ...cc.value].map(item => item.email));
  return people.value
    .filter(
      person =>
        !chosen.has(person.email) &&
        `${person.name} ${person.email}`.toLowerCase().includes(q)
    )
    .slice(0, 6);
};

const add = (field, person) => {
  listOf(field).value.push({ name: person.name, email: person.email });
  query.value[field] = '';
};
const addTyped = field => {
  const parts = query.value[field].split(/[,;\s]+/).filter(Boolean);
  parts.forEach(email => {
    if (EMAIL.test(email) && !listOf(field).value.some(i => i.email === email))
      listOf(field).value.push({ name: email, email });
  });
  query.value[field] = '';
};
const onKey = (field, event) => {
  if (!['Enter', ',', ';', 'Tab'].includes(event.key)) return;
  if (!query.value[field].trim()) return;
  event.preventDefault();
  const list = suggestions(field);
  if (list.length && !EMAIL.test(query.value[field].trim()))
    add(field, list[0]);
  else addTyped(field);
};
const removeFrom = (field, email) => {
  listOf(field).value = listOf(field).value.filter(i => i.email !== email);
};

const addFiles = list => {
  const total = files.value.reduce((sum, f) => sum + f.size, 0);
  let size = total;
  Array.from(list || []).forEach(file => {
    if (size + file.size > MAX_TOTAL) {
      useAlert(t('OUTSIDER_APPS.MAIL.TOO_BIG'));
      return;
    }
    size += file.size;
    files.value.push(file);
  });
};
const onDrop = event => {
  dragging.value = false;
  addFiles(event.dataTransfer?.files);
};

const canSend = computed(
  () =>
    !isSending.value &&
    (isReply.value || to.value.length || query.value.to.trim()) &&
    (text.value.trim() || files.value.length || props.mode === 'forward')
);

const send = async () => {
  addTyped('to');
  addTyped('cc');
  if (!isReply.value && !to.value.length) {
    useAlert(t('OUTSIDER_APPS.MAIL.NEED_RECIPIENT'));
    return;
  }
  isSending.value = true;
  try {
    await AppsAPI.sendMail(props.provider, {
      mode: props.mode,
      source_id: props.source?.id,
      to: to.value.map(item => item.email),
      cc: cc.value.map(item => item.email),
      subject: subject.value,
      text: text.value,
      files: files.value,
    });
    emit('sent');
  } catch (e) {
    useAlert(errorText(e, t));
  } finally {
    isSending.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-[9998] flex items-end justify-center bg-n-alpha-black1 backdrop-blur-[2px] md:items-center"
    @click.self="emit('close')"
  >
    <form
      class="relative flex flex-col w-full max-w-2xl max-h-[92vh] gap-2.5 p-5 shadow-xl bg-n-surface-1 rounded-t-2xl md:rounded-2xl"
      data-apps-mail-composer
      @submit.prevent="send"
      @dragover.prevent="dragging = true"
      @dragleave.self="dragging = false"
      @drop.prevent="onDrop"
    >
      <div class="flex items-center gap-2">
        <h3 class="flex-1 mb-0 text-base font-semibold text-n-slate-12">
          {{ title }}
        </h3>
        <button
          type="button"
          class="text-n-slate-11"
          :aria-label="t('OUTSIDER_APPS.CLOSE')"
          @click="emit('close')"
        >
          <Icon icon="i-lucide-x" class="size-5" />
        </button>
      </div>

      <p v-if="isReply" class="mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_APPS.MAIL.TO') }}:
        <b class="text-n-slate-12">{{ replyTo }}</b>
      </p>

      <template
        v-for="field in isReply
          ? showCc
            ? ['cc']
            : []
          : showCc
            ? ['to', 'cc']
            : ['to']"
        :key="field"
      >
        <div class="relative">
          <div
            class="flex flex-wrap items-center gap-1 px-2 py-1.5 border rounded-lg border-n-weak"
          >
            <span class="px-1 text-xs text-n-slate-10">
              {{
                field === 'to'
                  ? t('OUTSIDER_APPS.MAIL.TO')
                  : t('OUTSIDER_APPS.MAIL.CC')
              }}
            </span>
            <span
              v-for="person in listOf(field).value"
              :key="person.email"
              class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full oa-soft"
              :title="person.email"
            >
              {{ person.name }}
              <button type="button" @click="removeFrom(field, person.email)">
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </span>
            <input
              v-model="query[field]"
              type="text"
              class="reset-base !m-0 !p-0 !border-0 !bg-transparent !h-7 !shadow-none text-sm flex-1 min-w-[140px] outline-none"
              :placeholder="t('OUTSIDER_APPS.MAIL.RECIPIENT_HINT')"
              :data-apps-mail-field="field"
              @keydown="onKey(field, $event)"
              @blur="addTyped(field)"
            />
            <button
              v-if="field === 'to' && !showCc"
              type="button"
              class="px-1 text-xs text-n-slate-11 hover:underline"
              @click="showCc = true"
            >
              {{ t('OUTSIDER_APPS.MAIL.CC') }}
            </button>
          </div>
          <ul
            v-if="suggestions(field).length"
            class="absolute left-0 right-0 z-10 p-1 mt-1 overflow-hidden border shadow-lg rounded-xl bg-n-surface-1 border-n-weak"
          >
            <li
              v-for="person in suggestions(field)"
              :key="person.email"
              class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-lg cursor-pointer hover:bg-n-alpha-1 text-n-slate-12"
              @mousedown.prevent="add(field, person)"
            >
              <span class="truncate">{{ person.name }}</span>
              <span class="ml-auto text-xs truncate text-n-slate-10">{{
                person.email
              }}</span>
            </li>
          </ul>
        </div>
      </template>
      <button
        v-if="isReply && !showCc"
        type="button"
        class="self-start text-xs text-n-slate-11 hover:underline"
        @click="showCc = true"
      >
        {{ t('OUTSIDER_APPS.MAIL.ADD_CC') }}
      </button>

      <input
        v-if="!isReply"
        v-model="subject"
        type="text"
        class="!mb-0 text-sm"
        :placeholder="t('OUTSIDER_APPS.MAIL.SUBJECT')"
        maxlength="250"
        data-apps-mail-subject-input
      />
      <textarea
        v-model="text"
        rows="9"
        class="!mb-0 text-sm min-h-[160px]"
        :placeholder="t('OUTSIDER_APPS.MAIL.TEXT')"
        data-apps-mail-text
      />
      <p v-if="source" class="mb-0 text-xs text-n-slate-10">
        {{ t(textKey(provider, 'MAIL.QUOTED_NOTE')) }}
      </p>

      <div v-if="files.length" class="flex flex-wrap gap-1.5">
        <span
          v-for="(file, index) in files"
          :key="`${file.name}-${index}`"
          class="flex items-center gap-1.5 px-2 py-1 text-xs border rounded-lg border-n-weak text-n-slate-12"
        >
          <Icon icon="i-lucide-paperclip" class="size-3.5" />
          <span class="max-w-[180px] truncate">{{ file.name }}</span>
          <span class="text-n-slate-10">{{ formatSize(file.size) }}</span>
          <button type="button" @click="files.splice(index, 1)">
            <Icon icon="i-lucide-x" class="size-3" />
          </button>
        </span>
      </div>

      <div class="flex items-center gap-2 mt-1">
        <button type="button" class="oa-ghost" @click="fileInput?.click()">
          <Icon icon="i-lucide-paperclip" class="size-4" />
          {{ t('OUTSIDER_APPS.MAIL.ATTACH') }}
        </button>
        <input
          ref="fileInput"
          type="file"
          multiple
          class="hidden"
          @change="
            addFiles($event.target.files);
            $event.target.value = '';
          "
        />
        <span class="flex-1" />
        <button
          type="submit"
          class="oa-btn"
          :disabled="!canSend"
          data-apps-mail-send
        >
          <Spinner v-if="isSending" :size="14" />
          <Icon v-else icon="i-lucide-send" class="size-4" />
          {{ t('OUTSIDER_APPS.MAIL.SEND') }}
        </button>
      </div>

      <div
        v-if="dragging"
        class="absolute inset-0 grid border-2 border-dashed pointer-events-none place-items-center rounded-2xl bg-n-surface-1/90 border-[var(--oa-accent)] text-sm text-n-slate-12"
      >
        {{ t('OUTSIDER_APPS.MAIL.DROP') }}
      </div>
    </form>
  </div>
</template>
