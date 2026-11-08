<script setup>
// OUTSIDER: um chat do Teams aberto (1:1, grupo ou chat de reunião) e também o canal no modo Conversa (channelMode):
// tudo em sequência, como no WhatsApp. Balões no roxo do Teams para as mensagens da própria pessoa; nos grupos e no
// canal, o nome de quem escreveu em cima. Separador por dia e "Mensagens novas" desde a última leitura.
// Responder (passar o mouse no balão) cita a mensagem: no chat sai como "responder citando" do Teams; no canal a
// resposta entra na publicação e a citação aparece aqui. "@você" marca quem chamou a pessoa.
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import TeamsThreadHeader from './TeamsThreadHeader.vue';
import TeamsComposer from './TeamsComposer.vue';
import TeamsAttachments from './TeamsAttachments.vue';
import { useTeamsThread } from './useTeamsThread';
import { dayKey, dayLabel, timeOf } from './helpers';

const props = defineProps({
  thread: { type: Object, required: true },
  canWrite: { type: Boolean, default: false },
  channelMode: { type: Boolean, default: false },
});
const emit = defineEmits(['back', 'changeView']);

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const scroller = ref(null);
const composer = ref(null);
const isSending = ref(false);
const quoteTo = ref(null);
// "Mensagens novas" a partir do que chegou depois da última leitura (guardado ao abrir)
const lastReadAt = props.thread.last_read_at
  ? new Date(props.thread.last_read_at)
  : null;

const nearBottom = () => {
  const el = scroller.value;
  return !el || el.scrollHeight - el.scrollTop - el.clientHeight < 160;
};
const toBottom = () =>
  nextTick(() => {
    if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight;
  });

const scrollToNew = () =>
  nextTick(() => {
    const divider = scroller.value?.querySelector('[data-teams-new]');
    if (divider) divider.scrollIntoView({ block: 'center' });
    else toBottom();
  });

const { items, more, isLoading, isLoadingOlder, loadOlder, send, retry } =
  useTeamsThread(props.thread, {
    mode: props.channelMode ? 'flat' : null,
    onLoaded: scrollToNew,
    onIncoming: message => {
      const stick = nearBottom();
      const index = items.value.findIndex(item => item.id === message.id);
      if (index >= 0)
        items.value.splice(index, 1, { ...items.value[index], ...message });
      else items.value.push(message);
      if (stick) toBottom();
    },
  });

const olderKeepingPlace = async () => {
  const el = scroller.value;
  const before = el?.scrollHeight || 0;
  await loadOlder();
  nextTick(() => {
    if (el) el.scrollTop = el.scrollHeight - before;
  });
};

const showNames = computed(
  () => props.channelMode || props.thread.chat_type !== 'oneOnOne'
);

const firstNewId = computed(() => {
  if (!lastReadAt) return null;
  const found = items.value.find(
    item => !item.mine && new Date(item.sent_at) > lastReadAt
  );
  return found?.id || null;
});

// linhas com separador de dia, "Mensagens novas" e o nome/foto só na primeira mensagem de uma sequência
const rows = computed(() => {
  const out = [];
  let lastDay = null;
  let last = null;
  items.value.forEach(message => {
    const day = dayKey(message.sent_at);
    if (day !== lastDay) {
      out.push({
        type: 'day',
        key: `day-${day}`,
        ...dayLabel(message.sent_at, t),
      });
      lastDay = day;
      last = null;
    }
    if (message.id === firstNewId.value) {
      out.push({ type: 'new', key: 'new' });
      last = null;
    }
    const sameRun =
      last &&
      last.mine === message.mine &&
      last.sender_name === message.sender_name &&
      !message.quote &&
      new Date(message.sent_at) - new Date(last.sent_at) < 5 * 60 * 1000;
    out.push({ type: 'message', key: message.id, message, first: !sameRun });
    last = message;
  });
  return out;
});

const quoteTitle = quote =>
  quote.post
    ? t('OUTSIDER_TEAMS_AREA.QUOTE_POST', { name: quote.sender })
    : quote.sender;

const jumpTo = quote => {
  const target = items.value.find(
    item => item.id === quote.message_id || item.graph_id === quote.graph_id
  );
  if (!target) return;
  const el = scroller.value?.querySelector(`[data-teams-message="${target.id}"]`);
  if (!el) return;
  el.scrollIntoView({ block: 'center', behavior: 'smooth' });
  el.classList.add('tms-flash');
  setTimeout(() => el.classList.remove('tms-flash'), 1600);
};

const answer = message => {
  quoteTo.value = message;
  composer.value?.focus();
};

const loadMembers = async () => {
  const { data } = await TeamsGraphAPI.members(props.thread.id);
  return data.payload;
};

const onSend = async ({ content, files }) => {
  isSending.value = true;
  const quote = quoteTo.value;
  quoteTo.value = null;
  const payload = { content, files, quoteId: quote?.id };
  // no canal, a resposta entra na publicação da mensagem citada; sem citação, vira publicação nova
  if (props.channelMode && quote)
    payload.replyTo = quote.reply_to_graph_id || quote.graph_id;
  const message = await send(payload);
  isSending.value = false;
  if (message && !items.value.some(item => item.id === message.id)) {
    items.value.push(message);
    toBottom();
  }
};

const placeholder = computed(() => {
  if (props.channelMode)
    return quoteTo.value
      ? t('OUTSIDER_TEAMS_AREA.WRITE_REPLY')
      : t('OUTSIDER_TEAMS_AREA.WRITE_POST');
  return props.thread.chat_type === 'oneOnOne'
    ? t('OUTSIDER_TEAMS_AREA.WRITE_TO', { name: props.thread.title })
    : t('OUTSIDER_TEAMS_AREA.WRITE_GROUP');
});
</script>

<template>
  <div class="flex flex-col flex-1 min-w-0">
    <TeamsThreadHeader
      :thread="thread"
      :view-mode="channelMode ? 'conversa' : 'publicacoes'"
      @back="emit('back')"
      @change-view="mode => emit('changeView', mode)"
    />
    <div
      ref="scroller"
      class="flex flex-col flex-1 min-h-0 gap-1.5 px-4 py-4 overflow-y-auto md:px-8 tms-bg"
    >
      <div v-if="isLoading" class="flex justify-center py-10">
        <Spinner :size="20" />
      </div>
      <button
        v-else-if="more"
        type="button"
        class="self-center px-3 py-1 mb-2 text-xs border rounded-full bg-n-surface-1 text-n-slate-11 border-n-weak"
        :disabled="isLoadingOlder"
        @click="olderKeepingPlace"
      >
        {{ t('OUTSIDER_TEAMS_AREA.LOAD_OLDER') }}
      </button>
      <p
        v-if="!isLoading && !items.length"
        class="py-10 mb-0 text-sm text-center text-n-slate-11"
      >
        {{
          channelMode
            ? t('OUTSIDER_TEAMS_AREA.NO_POSTS')
            : t('OUTSIDER_TEAMS_AREA.NO_MESSAGES')
        }}
      </p>

      <template v-for="row in rows" :key="row.key">
        <div
          v-if="row.type === 'day'"
          class="flex items-center self-center gap-2 px-3.5 py-1 my-2 text-xs border rounded-full bg-n-surface-1 border-n-weak text-n-slate-11"
        >
          <Icon icon="i-lucide-calendar" class="size-3.5" />
          <b v-if="row.title" class="text-n-slate-12">{{ row.title }}</b>
          {{ row.full }}
        </div>
        <div
          v-else-if="row.type === 'new'"
          class="flex items-center gap-3 my-2 text-xs font-semibold tms-text"
          data-teams-new
        >
          <span class="flex-1 h-px" style="background: var(--tms-accent)" />
          {{ t('OUTSIDER_TEAMS_AREA.NEW_MESSAGES') }}
          <span class="flex-1 h-px" style="background: var(--tms-accent)" />
        </div>
        <div
          v-else
          class="flex gap-2.5 max-w-[80%] md:max-w-[70%] group"
          :class="[
            row.message.mine ? 'self-end flex-row-reverse' : '',
            row.first ? 'mt-2' : '',
          ]"
          :data-teams-message="row.message.id"
        >
          <span v-if="!row.message.mine" class="w-[30px] shrink-0">
            <Avatar
              v-if="row.first"
              :name="row.message.sender_name || '?'"
              :size="30"
              rounded-full
            />
          </span>
          <div class="min-w-0">
            <div
              v-if="row.first"
              class="mb-0.5 text-xs text-n-slate-11"
              :class="row.message.mine ? 'text-right' : ''"
            >
              <b
                v-if="!row.message.mine && showNames"
                class="mr-1.5 font-semibold text-n-slate-12"
              >
                {{ row.message.sender_name }}
              </b>
              {{ timeOf(row.message.sent_at) }}
            </div>
            <div class="flex items-center gap-1" :class="row.message.mine ? 'flex-row-reverse' : ''">
              <div
                class="px-3.5 py-2 text-sm leading-relaxed shadow-sm break-words whitespace-pre-wrap min-w-0"
                :class="[
                  row.message.mine
                    ? 'tms-mine text-n-slate-12 rounded-[14px] rounded-tr-md'
                    : 'bg-n-surface-1 text-n-slate-12 rounded-[14px] rounded-tl-md',
                  row.message.mentions_me ? 'tms-mention' : '',
                ]"
              >
                <span
                  v-if="row.message.mentions_me"
                  class="flex items-center gap-1 px-1.5 mb-1 text-[11px] font-semibold rounded-md w-max tms-soft"
                >
                  @ {{ t('OUTSIDER_TEAMS_AREA.MENTIONED_YOU') }}
                </span>
                <button
                  v-if="row.message.quote"
                  type="button"
                  class="block w-full px-2.5 py-1.5 mb-1.5 text-xs whitespace-normal rounded-lg !border-0 !border-l-[3px] !border-solid bg-n-alpha-1 text-start"
                  style="border-color: var(--tms-accent)"
                  @click="jumpTo(row.message.quote)"
                >
                  <b class="block tms-text">{{ quoteTitle(row.message.quote) }}</b>
                  <span class="line-clamp-2 text-n-slate-11">
                    {{ row.message.quote.text }}
                  </span>
                </button>
                <i v-if="row.message.deleted" class="text-n-slate-10">
                  {{ t('OUTSIDER_TEAMS_AREA.DELETED') }}
                </i>
                <template v-else>
                  <b
                    v-if="channelMode && row.message.subject"
                    class="block mb-0.5 text-[15px]"
                  >
                    {{ row.message.subject }}
                  </b>
                  <span v-if="row.message.content">{{ row.message.content }}</span>
                  <TeamsAttachments :message="row.message" />
                </template>
                <span
                  v-if="row.message.edited_at && !row.message.deleted"
                  class="ml-1 text-[11px] text-n-slate-10"
                >
                  {{ t('OUTSIDER_TEAMS_AREA.EDITED') }}
                </span>
              </div>
              <button
                v-if="canWrite && row.message.graph_id && !row.message.deleted"
                type="button"
                class="grid transition-opacity rounded-full opacity-0 size-7 place-items-center shrink-0 text-n-slate-11 hover:bg-n-alpha-2 group-hover:opacity-100 focus:opacity-100"
                :title="t('OUTSIDER_TEAMS_AREA.REPLY')"
                data-teams-reply
                @click="answer(row.message)"
              >
                <Icon icon="i-lucide-reply" class="size-4" />
              </button>
            </div>
            <div
              v-if="row.message.status !== 'sent'"
              class="flex items-center justify-end gap-1 mt-0.5 text-[11px]"
              :class="
                row.message.status === 'failed'
                  ? 'text-n-ruby-11'
                  : 'text-n-slate-10'
              "
            >
              <template v-if="row.message.status === 'sending'">
                <Icon icon="i-lucide-clock" class="size-3" />
                {{ t('OUTSIDER_TEAMS_AREA.SENDING') }}
              </template>
              <template v-else>
                <Icon icon="i-lucide-circle-alert" class="size-3" />
                {{ t('OUTSIDER_TEAMS_AREA.FAILED') }}
                <button
                  type="button"
                  class="ml-1 font-semibold underline"
                  :title="row.message.error"
                  @click="retry(row.message)"
                >
                  {{ t('OUTSIDER_TEAMS_AREA.RETRY') }}
                </button>
              </template>
            </div>
          </div>
        </div>
      </template>
    </div>
    <TeamsComposer
      ref="composer"
      :sender-name="currentUser?.name || ''"
      :replying-to="quoteTo"
      :placeholder="placeholder"
      :disabled="!canWrite"
      :is-sending="isSending"
      :show-new-post="channelMode"
      :load-members="loadMembers"
      @cancel-reply="quoteTo = null"
      @send="onSend"
    />
  </div>
</template>
