<script setup>
// OUTSIDER: caixa de escrever da área Teams. Avisa que a mensagem sai no Teams em nome da pessoa e mostra a
// mensagem citada (responder). Enter manda; Shift+Enter quebra a linha; até 5 anexos (vão para o OneDrive ou
// para os arquivos do canal, como no Teams). "@" abre a lista de pessoas do chat ou do canal para mencionar.
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeamsLogo from './TeamsLogo.vue';

const props = defineProps({
  placeholder: { type: String, default: '' },
  senderName: { type: String, default: '' },
  replyingTo: { type: Object, default: null },
  disabled: { type: Boolean, default: false },
  isSending: { type: Boolean, default: false },
  showNewPost: { type: Boolean, default: false },
  // () => Promise<[{ id, name }]>: quem dá para @mencionar (carregado no primeiro "@")
  loadMembers: { type: Function, default: null },
});

const emit = defineEmits(['send', 'cancelReply']);

const MAX_FILES = 5;
const MAX_SIZE = 25 * 1024 * 1024;

const { t } = useI18n();
const text = ref('');
const files = ref([]);
const input = ref(null);
const fileInput = ref(null);

// ---------- @menção ----------
const members = ref(null);
const mention = ref(null); // { start, query }
const mentionIndex = ref(0);

const fold = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();

const suggestions = computed(() => {
  if (!mention.value || !members.value) return [];
  const query = fold(mention.value.query);
  return members.value
    .filter(person => {
      const name = fold(person.name);
      return (
        name.startsWith(query) ||
        name.split(/\s+/).some(part => part.startsWith(query))
      );
    })
    .slice(0, 6);
});

const ensureMembers = async () => {
  if (members.value || !props.loadMembers) return;
  members.value = [];
  try {
    members.value = (await props.loadMembers()) || [];
  } catch {
    members.value = [];
  }
};

// "@" no começo ou depois de espaço, sem espaço duplo até o cursor
const findMention = () => {
  const el = input.value;
  if (!el || !props.loadMembers) return null;
  const before = text.value.slice(0, el.selectionStart);
  const match = before.match(/(^|\s)@([^\s@]*(?: [^\s@]+)?)$/);
  if (!match) return null;
  return { start: before.length - match[2].length - 1, query: match[2] };
};

const checkMention = () => {
  mention.value = findMention();
  mentionIndex.value = 0;
  if (mention.value) ensureMembers();
};

const pickMention = person => {
  const el = input.value;
  if (!mention.value || !el) return;
  const { start } = mention.value;
  const end = el.selectionStart;
  const chosen = `@${person.name} `;
  text.value = text.value.slice(0, start) + chosen + text.value.slice(end);
  mention.value = null;
  nextTick(() => {
    const caret = start + chosen.length;
    el.focus();
    el.setSelectionRange(caret, caret);
    resize();
  });
};

const quoteText = computed(() => {
  const message = props.replyingTo;
  if (!message) return '';
  if (message.subject && message.content)
    return `${message.subject} · ${message.content}`;
  return (
    message.subject ||
    message.content ||
    (message.attachments || []).map(item => item.name).join(', ')
  );
});

const canSend = computed(
  () =>
    !props.disabled &&
    !props.isSending &&
    (text.value.trim() || files.value.length)
);

const resize = () => {
  const el = input.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 180)}px`;
};

const focus = () => nextTick(() => input.value?.focus());

const pick = event => {
  const chosen = Array.from(event.target.files || []);
  event.target.value = '';
  if (chosen.some(file => file.size > MAX_SIZE)) {
    useAlert(t('OUTSIDER_TEAMS_AREA.ERRORS.FILE_TOO_BIG'));
  }
  files.value = [
    ...files.value,
    ...chosen.filter(file => file.size <= MAX_SIZE),
  ].slice(0, MAX_FILES);
};

const send = () => {
  if (!canSend.value) return;
  mention.value = null;
  emit('send', { content: text.value.trim(), files: files.value });
  text.value = '';
  files.value = [];
  nextTick(resize);
};

const onInput = () => {
  resize();
  checkMention();
};

const onKeydown = event => {
  if (suggestions.value.length) {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const step = event.key === 'ArrowDown' ? 1 : -1;
      const size = suggestions.value.length;
      mentionIndex.value = (mentionIndex.value + step + size) % size;
      return;
    }
    if ((event.key === 'Enter' || event.key === 'Tab') && !event.shiftKey) {
      event.preventDefault();
      pickMention(suggestions.value[mentionIndex.value]);
      return;
    }
  }
  if (event.key === 'Escape' && mention.value) {
    event.preventDefault();
    mention.value = null;
    return;
  }
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    send();
  }
};

defineExpose({ focus });
</script>

<template>
  <div
    class="mx-4 mb-3.5 mt-2 border rounded-2xl border-n-weak bg-n-surface-1 px-3.5 py-2.5"
  >
    <div
      v-if="replyingTo"
      class="flex items-start gap-2 px-2.5 py-1.5 mb-1.5 text-xs border-l-[3px] rounded-md bg-n-alpha-1 text-n-slate-11"
      style="border-color: var(--tms-accent)"
      data-teams-quote
    >
      <Icon icon="i-lucide-reply" class="size-3.5 mt-0.5 shrink-0" />
      <span class="flex-1 min-w-0">
        <span class="block truncate">
          {{ t('OUTSIDER_TEAMS_AREA.REPLYING_TO') }}
          <b class="tms-text">
            {{
              replyingTo.mine
                ? t('OUTSIDER_TEAMS_AREA.YOU')
                : replyingTo.sender_name
            }}
          </b>
        </span>
        <span v-if="quoteText" class="block truncate">{{ quoteText }}</span>
      </span>
      <button
        type="button"
        class="text-n-slate-10 hover:text-n-slate-12"
        :title="t('OUTSIDER_TEAMS_AREA.CANCEL_REPLY')"
        @click="emit('cancelReply')"
      >
        <Icon icon="i-lucide-x" class="size-4" />
      </button>
    </div>
    <div
      v-else
      class="flex items-center gap-1.5 px-2.5 py-1 mb-1.5 text-xs rounded-lg w-max max-w-full tms-soft"
    >
      <TeamsLogo :size="13" />
      <span class="truncate">
        {{
          showNewPost
            ? t('OUTSIDER_TEAMS_AREA.NEW_POST_AS', { name: senderName })
            : t('OUTSIDER_TEAMS_AREA.SENDS_AS', { name: senderName })
        }}
      </span>
    </div>

    <div class="relative">
      <ul
        v-if="suggestions.length"
        class="absolute left-0 z-10 w-64 p-1 mb-1 overflow-hidden border shadow-lg bottom-full rounded-xl bg-n-surface-1 border-n-weak"
        data-teams-mentions
      >
        <li
          v-for="(person, index) in suggestions"
          :key="person.id"
          class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-lg cursor-pointer text-n-slate-12"
          :class="index === mentionIndex ? 'tms-soft' : 'hover:bg-n-alpha-1'"
          @mousedown.prevent="pickMention(person)"
          @mouseenter="mentionIndex = index"
        >
          <Avatar :name="person.name" :size="22" rounded-full />
          <span class="truncate">{{ person.name }}</span>
        </li>
      </ul>
    <textarea
      ref="input"
      v-model="text"
      rows="1"
      class="!m-0 !p-0 !py-1.5 !border-0 !bg-transparent !shadow-none !min-h-0 !h-auto !outline-0 !rounded-none w-full text-sm text-n-slate-12 resize-none"
      :placeholder="disabled ? t('OUTSIDER_TEAMS_AREA.READ_ONLY') : placeholder"
      :disabled="disabled"
      @input="onInput"
      @keydown="onKeydown"
      @click="checkMention"
      @blur="mention = null"
    />
    </div>

    <div v-if="files.length" class="flex flex-wrap gap-1.5 mb-1.5">
      <span
        v-for="(file, index) in files"
        :key="`${file.name}-${index}`"
        class="flex items-center gap-1.5 px-2 py-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-12"
      >
        <Icon icon="i-lucide-paperclip" class="size-3" />
        <span class="max-w-[160px] truncate">{{ file.name }}</span>
        <button type="button" @click="files.splice(index, 1)">
          <Icon icon="i-lucide-x" class="size-3" />
        </button>
      </span>
    </div>

    <div class="flex items-center gap-3 text-n-slate-11">
      <button
        type="button"
        class="hover:text-n-slate-12 disabled:opacity-40"
        :disabled="disabled || files.length >= 5"
        :title="t('OUTSIDER_TEAMS_AREA.ATTACH')"
        @click="fileInput?.click()"
      >
        <Icon icon="i-lucide-paperclip" class="size-5" />
      </button>
      <input
        ref="fileInput"
        type="file"
        multiple
        class="hidden"
        @change="pick"
      />
      <slot name="tools" />
      <button
        type="button"
        class="flex items-center justify-center ml-auto rounded-full size-10 tms-accent-bg disabled:opacity-40"
        :disabled="!canSend"
        :title="t('OUTSIDER_TEAMS_AREA.SEND')"
        data-testid="teams-send"
        @click="send"
      >
        <Icon icon="i-lucide-send-horizontal" class="size-[18px]" />
      </button>
    </div>
  </div>
</template>
