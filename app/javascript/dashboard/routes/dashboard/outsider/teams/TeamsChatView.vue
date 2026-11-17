<script setup>
// OUTSIDER: um chat do Teams aberto (1:1, grupo ou chat de reunião) e também o canal no modo Conversa (channelMode):
// tudo em sequência, como no WhatsApp. Balões no roxo do Teams para as mensagens da própria pessoa; nos grupos e no
// canal, o nome de quem escreveu em cima. Separador por dia e "Mensagens novas" desde a última leitura.
// Responder (passar o mouse no balão) cita a mensagem: no chat sai como "responder citando" do Teams; no canal a
// resposta entra na publicação e a citação aparece aqui. "@você" marca quem chamou a pessoa.
// Reações (👍 ❤️ ...) embaixo do balão e botão de reagir; barra de menções no topo para ir de uma citação à outra
// (busca as mensagens mais antigas se a citação ainda não estiver na tela).
// Fotos/vídeos mandados em sequência pela mesma pessoa viram um álbum só (teamsMedia.js), e o visualizador abre com
// todas as fotos/vídeos do chat. "Selecionar" (ou o botão de encaminhar no balão) marca mensagens para encaminhar a
// outros chats/canais (TeamsForwardDialog.vue) ou baixar os arquivos delas num .zip.
import { computed, nextTick, provide, ref, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import TeamsThreadHeader from './TeamsThreadHeader.vue';
import TeamsComposer from './TeamsComposer.vue';
import TeamsAttachments from './TeamsAttachments.vue';
import TeamsReactions from './TeamsReactions.vue';
import TeamsMentionBar from './TeamsMentionBar.vue';
import TeamsForwardDialog from './TeamsForwardDialog.vue';
import { useTeamsThread } from './useTeamsThread';
import {
  downloadZip,
  joinsAlbum,
  startDownload,
  viewerItems,
} from './teamsMedia';
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

// linhas com separador de dia, "Mensagens novas" e o nome/foto só na primeira mensagem de uma sequência;
// fotos/vídeos seguidos da mesma pessoa entram na mesma linha (group), como o álbum do WhatsApp
const rows = computed(() => {
  const out = [];
  let lastDay = null;
  let last = null;
  items.value.forEach(message => {
    const previous = out[out.length - 1];
    if (
      previous?.type === 'message' &&
      dayKey(message.sent_at) === lastDay &&
      message.id !== firstNewId.value &&
      joinsAlbum(previous.group[previous.group.length - 1], message)
    ) {
      previous.group.push(message);
      last = message;
      return;
    }
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
    out.push({
      type: 'message',
      key: message.id,
      message,
      group: [message],
      first: !sameRun,
    });
    last = message;
  });
  return out;
});

const quoteTitle = quote =>
  quote.post
    ? t('OUTSIDER_TEAMS_AREA.QUOTE_POST', { name: quote.sender })
    : quote.sender;

const highlight = (id, extraClass = 'tms-flash') => {
  const el =
    scroller.value?.querySelector(`[data-teams-message="${id}"]`) ||
    scroller.value?.querySelector(`[data-teams-ids~="${id}"]`);
  if (!el) return false;
  el.scrollIntoView({ block: 'center', behavior: 'smooth' });
  el.classList.add(extraClass);
  setTimeout(() => el.classList.remove(extraClass), 1600);
  return true;
};

const jumpTo = quote => {
  const target = items.value.find(
    item => item.id === quote.message_id || item.graph_id === quote.graph_id
  );
  if (target) highlight(target.id);
};

// citação ainda não carregada: busca as mensagens anteriores até ela aparecer (no máximo 20 páginas)
const jumpToMention = async mention => {
  for (let page = 0; page < 20; page += 1) {
    if (items.value.some(item => item.id === mention.id)) break;
    if (!more.value) break;
    // eslint-disable-next-line no-await-in-loop
    await loadOlder();
  }
  await nextTick();
  highlight(mention.id, 'tms-mention-target');
};

const loadedIds = computed(() => items.value.map(item => item.id));

// ---------- selecionar, encaminhar e baixar vários ----------
const selecting = ref(false);
const selected = ref([]);
const forwardIds = ref(null);
const zipping = ref(false);

const canForward = message =>
  !!message?.graph_id && !message.deleted && message.status === 'sent';
const groupIds = row => row.group.filter(canForward).map(message => message.id);
const isSelected = row => {
  const ids = groupIds(row);
  return ids.length > 0 && ids.every(id => selected.value.includes(id));
};
const toggleSelect = row => {
  const ids = groupIds(row);
  if (!ids.length) return;
  selected.value = isSelected(row)
    ? selected.value.filter(id => !ids.includes(id))
    : [...new Set([...selected.value, ...ids])];
};
const startSelect = row => {
  selecting.value = true;
  selected.value = [];
  toggleSelect(row);
};
const cancelSelect = () => {
  selecting.value = false;
  selected.value = [];
};
// no modo seleção, clicar no balão marca/desmarca (e não abre foto, link, citação...)
const onRowClick = (event, row) => {
  if (!selecting.value) return;
  event.preventDefault();
  event.stopPropagation();
  toggleSelect(row);
};

const selectedFiles = computed(() =>
  items.value
    .filter(message => selected.value.includes(message.id))
    .flatMap(message =>
      (message.attachments || [])
        .filter(item => item.download_url)
        .map(item => ({
          message_id: message.id,
          index: item.index,
          url: item.download_url,
        }))
    )
);

const downloadSelected = async () => {
  const list = selectedFiles.value;
  if (!list.length || zipping.value) return;
  if (list.length === 1) {
    startDownload(list[0].url);
    return;
  }
  zipping.value = true;
  try {
    await downloadZip(
      props.thread.id,
      list.map(({ message_id: messageId, index }) => ({
        message_id: messageId,
        index,
      }))
    );
    useAlert(
      t('OUTSIDER_TEAMS_AREA.SELECT.ZIP_STARTED', { count: list.length })
    );
  } catch (error) {
    useAlert(t('OUTSIDER_TEAMS_AREA.ZIP_ERROR'));
  } finally {
    zipping.value = false;
  }
};

const openForward = ids => {
  const list = ids.filter(id =>
    canForward(items.value.find(item => item.id === id))
  );
  if (list.length) forwardIds.value = list;
};
const onForwarded = () => {
  forwardIds.value = null;
  cancelSelect();
};
watch(
  () => props.thread.id,
  () => {
    cancelSelect();
    forwardIds.value = null;
  }
);

// o visualizador de fotos/vídeos (TeamsAttachments) recebe tudo o que está carregado no chat e as ações daqui
provide('teamsMedia', {
  items: computed(() => viewerItems(items.value, t('OUTSIDER_TEAMS_AREA.YOU'))),
  jump: id => highlight(id),
  forward: id => openForward([id]),
});

const onReacted = updated => {
  const index = items.value.findIndex(item => item.id === updated.id);
  if (index >= 0)
    items.value.splice(index, 1, { ...items.value[index], ...updated });
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
    <TeamsMentionBar
      :thread="thread"
      :loaded-ids="loadedIds"
      @jump="jumpToMention"
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
          class="relative flex flex-col w-full transition-colors rounded-lg"
          :class="[
            selecting ? 'ltr:pl-9 rtl:pr-9 cursor-pointer' : '',
            selecting && isSelected(row) ? 'bg-n-alpha-2' : '',
          ]"
          :data-teams-ids="row.group.map(message => message.id).join(' ')"
          @click.capture="onRowClick($event, row)"
        >
          <span
            v-if="selecting"
            class="absolute grid -translate-y-1/2 border-2 rounded-full top-1/2 ltr:left-2 rtl:right-2 size-5 place-items-center"
            :class="
              isSelected(row)
                ? 'tms-accent-bg border-transparent text-white'
                : groupIds(row).length
                  ? 'border-n-slate-8 bg-n-surface-1'
                  : 'border-n-slate-6 opacity-40'
            "
            data-teams-select-box
          >
            <span v-if="isSelected(row)" class="i-lucide-check size-3" />
          </span>
          <div
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
                :src="row.message.sender_photo || ''"
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
              <div
                class="flex items-center gap-1"
                :class="row.message.mine ? 'flex-row-reverse' : ''"
              >
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
                    <b class="block tms-text">{{
                      quoteTitle(row.message.quote)
                    }}</b>
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
                    <span v-if="row.message.content">{{
                      row.message.content
                    }}</span>
                    <TeamsAttachments
                      :message="row.message"
                      :group="row.group.length > 1 ? row.group : null"
                    />
                  </template>
                  <span
                    v-if="row.message.edited_at && !row.message.deleted"
                    class="ml-1 text-[11px] text-n-slate-10"
                  >
                    {{ t('OUTSIDER_TEAMS_AREA.EDITED') }}
                  </span>
                </div>
                <button
                  v-if="
                    canWrite && row.message.graph_id && !row.message.deleted
                  "
                  type="button"
                  class="grid transition-opacity rounded-full opacity-0 size-7 place-items-center shrink-0 text-n-slate-11 hover:bg-n-alpha-2 group-hover:opacity-100 focus:opacity-100"
                  :title="t('OUTSIDER_TEAMS_AREA.REPLY')"
                  data-teams-reply
                  @click="answer(row.message)"
                >
                  <Icon icon="i-lucide-reply" class="size-4" />
                </button>
                <button
                  v-if="!selecting && canForward(row.message)"
                  type="button"
                  class="grid transition-opacity rounded-full opacity-0 size-7 place-items-center shrink-0 text-n-slate-11 hover:bg-n-alpha-2 group-hover:opacity-100 focus:opacity-100"
                  :title="t('OUTSIDER_TEAMS_AREA.FORWARD.BUTTON')"
                  data-teams-forward-one
                  @click="openForward(groupIds(row))"
                >
                  <Icon icon="i-lucide-forward" class="size-4" />
                </button>
                <button
                  v-if="!selecting && canForward(row.message)"
                  type="button"
                  class="grid transition-opacity rounded-full opacity-0 size-7 place-items-center shrink-0 text-n-slate-11 hover:bg-n-alpha-2 group-hover:opacity-100 focus:opacity-100"
                  :title="t('OUTSIDER_TEAMS_AREA.SELECT.BUTTON')"
                  data-teams-select
                  @click="startSelect(row)"
                >
                  <Icon icon="i-lucide-list-checks" class="size-4" />
                </button>
                <TeamsReactions
                  :message="row.message"
                  :can-react="canWrite"
                  :align-end="row.message.mine"
                  only="button"
                  @updated="onReacted"
                />
              </div>
              <TeamsReactions
                :message="row.message"
                :can-react="canWrite"
                :align-end="row.message.mine"
                only="chips"
                @updated="onReacted"
              />
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
        </div>
      </template>
    </div>
    <!-- modo seleção: no lugar da caixa de escrever -->
    <div
      v-if="selecting"
      class="flex flex-wrap items-center gap-2 px-4 py-3 border-t border-n-weak bg-n-surface-1"
      data-teams-selection-bar
    >
      <button
        type="button"
        class="grid rounded-full size-8 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
        :title="t('OUTSIDER_TEAMS_AREA.SELECT.CANCEL')"
        @click="cancelSelect"
      >
        <Icon icon="i-lucide-x" class="size-4" />
      </button>
      <span class="flex-1 text-sm font-medium text-n-slate-12">
        {{
          t(
            'OUTSIDER_TEAMS_AREA.SELECT.COUNT',
            { count: selected.length },
            selected.length
          )
        }}
      </span>
      <button
        type="button"
        class="flex items-center gap-1.5 h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
        :disabled="!selectedFiles.length || zipping"
        data-teams-selection-download
        @click="downloadSelected"
      >
        <Icon
          :icon="zipping ? 'i-lucide-loader-circle' : 'i-lucide-download'"
          class="size-4"
          :class="{ 'animate-spin': zipping }"
        />
        {{
          t(
            'OUTSIDER_TEAMS_AREA.SELECT.DOWNLOAD',
            { count: selectedFiles.length },
            selectedFiles.length
          )
        }}
      </button>
      <button
        type="button"
        class="flex items-center gap-1.5 h-9 px-3 text-sm font-semibold rounded-lg tms-accent-bg disabled:opacity-50"
        :disabled="!selected.length"
        data-teams-selection-forward
        @click="openForward(selected)"
      >
        <Icon icon="i-lucide-forward" class="size-4" />
        {{ t('OUTSIDER_TEAMS_AREA.FORWARD.BUTTON') }}
      </button>
    </div>
    <TeamsForwardDialog
      v-if="forwardIds"
      :thread-id="thread.id"
      :message-ids="forwardIds"
      @close="forwardIds = null"
      @done="onForwarded"
    />
    <TeamsComposer
      v-show="!selecting"
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
