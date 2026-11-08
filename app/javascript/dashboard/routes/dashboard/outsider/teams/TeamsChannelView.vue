<script setup>
// OUTSIDER: um canal do Teams aberto no modo Publicações. Cada publicação vira um cartão com as respostas
// embaixo, como no Teams. "Responder" responde dentro da publicação; sem resposta escolhida, sai uma
// publicação nova. O modo Conversa (em sequência, como no WhatsApp) fica no TeamsChatView.
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
import { listTime, timeOf } from './helpers';

const props = defineProps({
  thread: { type: Object, required: true },
  canWrite: { type: Boolean, default: false },
});
const emit = defineEmits(['back', 'changeView']);

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const scroller = ref(null);
const composer = ref(null);
const replyTo = ref(null);
const isSending = ref(false);

const nearBottom = () => {
  const el = scroller.value;
  return !el || el.scrollHeight - el.scrollTop - el.clientHeight < 200;
};
const toBottom = () =>
  nextTick(() => {
    if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight;
  });

const upsert = (list, message) => {
  const index = list.findIndex(item => item.id === message.id);
  if (index >= 0) list.splice(index, 1, { ...list[index], ...message });
  else list.push(message);
};

const { items, more, isLoading, isLoadingOlder, loadOlder, send, retry } =
  useTeamsThread(props.thread, {
    onLoaded: toBottom,
    onIncoming: message => {
      const stick = nearBottom();
      if (message.reply_to_graph_id) {
        const post = items.value.find(
          item => item.graph_id === message.reply_to_graph_id
        );
        if (post) upsert((post.replies ||= []), message);
      } else {
        upsert(items.value, { replies: [], ...message });
      }
      if (stick) toBottom();
    },
  });

const posts = computed(() => items.value);

const olderKeepingPlace = async () => {
  const el = scroller.value;
  const before = el?.scrollHeight || 0;
  await loadOlder();
  nextTick(() => {
    if (el) el.scrollTop = el.scrollHeight - before;
  });
};

const answer = post => {
  replyTo.value = post;
  composer.value?.focus();
};

const loadMembers = async () => {
  const { data } = await TeamsGraphAPI.members(props.thread.id);
  return data.payload;
};

const onSend = async ({ content, files }) => {
  isSending.value = true;
  const target = replyTo.value;
  const message = await send({ content, files, replyTo: target?.graph_id });
  isSending.value = false;
  if (!message) return;
  if (target) upsert((target.replies ||= []), message);
  else upsert(items.value, { replies: [], ...message });
  toBottom();
};
</script>

<template>
  <div class="flex flex-col flex-1 min-w-0">
    <TeamsThreadHeader
      :thread="thread"
      view-mode="publicacoes"
      @back="emit('back')"
      @change-view="mode => emit('changeView', mode)"
    />
    <div
      ref="scroller"
      class="flex flex-col flex-1 min-h-0 gap-3.5 px-3 py-4 overflow-y-auto md:px-7 tms-bg"
    >
      <div v-if="isLoading" class="flex justify-center py-10">
        <Spinner :size="20" />
      </div>
      <button
        v-else-if="more"
        type="button"
        class="self-center px-3 py-1 text-xs border rounded-full bg-n-surface-1 text-n-slate-11 border-n-weak"
        :disabled="isLoadingOlder"
        @click="olderKeepingPlace"
      >
        {{ t('OUTSIDER_TEAMS_AREA.LOAD_OLDER_POSTS') }}
      </button>
      <p
        v-if="!isLoading && !posts.length"
        class="py-10 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_TEAMS_AREA.NO_POSTS') }}
      </p>

      <article
        v-for="post in posts"
        :key="post.id"
        class="overflow-hidden border shadow-sm shrink-0 rounded-2xl bg-n-surface-1 border-n-weak"
        :class="replyTo?.id === post.id ? 'tms-outline' : ''"
        data-testid="teams-post"
      >
        <div class="flex gap-3 px-4 pt-3 pb-2.5">
          <Avatar :name="post.sender_name || '?'" :size="36" rounded-full />
          <div class="flex-1 min-w-0">
            <div class="text-xs text-n-slate-11">
              <b class="mr-1.5 text-sm font-semibold text-n-slate-12">
                {{ post.mine ? t('OUTSIDER_TEAMS_AREA.YOU') : post.sender_name }}
              </b>
              {{ listTime(post.sent_at, t) }} {{ timeOf(post.sent_at) }}
            </div>
            <span
              v-if="post.mentions_me"
              class="inline-flex items-center gap-1 px-1.5 mt-1 text-[11px] font-semibold rounded-md tms-soft"
            >
              @ {{ t('OUTSIDER_TEAMS_AREA.MENTIONED_YOU') }}
            </span>
            <h3
              v-if="post.subject"
              class="mt-0.5 mb-0.5 text-[15px] font-bold text-n-slate-12"
            >
              {{ post.subject }}
            </h3>
            <i v-if="post.deleted" class="text-sm text-n-slate-10">
              {{ t('OUTSIDER_TEAMS_AREA.DELETED') }}
            </i>
            <p
              v-else-if="post.content"
              class="mb-0 text-sm leading-relaxed break-words whitespace-pre-wrap text-n-slate-12"
            >
              {{ post.content }}
            </p>
            <TeamsAttachments v-if="!post.deleted" :message="post" />
            <p
              v-if="post.status !== 'sent'"
              class="flex items-center gap-1 mt-1 mb-0 text-[11px]"
              :class="post.status === 'failed' ? 'text-n-ruby-11' : 'text-n-slate-10'"
            >
              {{
                post.status === 'failed'
                  ? t('OUTSIDER_TEAMS_AREA.FAILED')
                  : t('OUTSIDER_TEAMS_AREA.SENDING')
              }}
              <button
                v-if="post.status === 'failed'"
                type="button"
                class="font-semibold underline"
                @click="retry(post)"
              >
                {{ t('OUTSIDER_TEAMS_AREA.RETRY') }}
              </button>
            </p>
          </div>
        </div>

        <div
          v-if="post.replies?.length"
          class="flex flex-col gap-2.5 py-2.5 pr-4 border-t pl-[60px] border-n-weak bg-n-alpha-1"
        >
          <div
            v-for="reply in post.replies"
            :key="reply.id"
            class="flex gap-2.5 text-sm"
          >
            <Avatar :name="reply.sender_name || '?'" :size="26" rounded-full />
            <div class="flex-1 min-w-0">
              <span class="font-semibold text-n-slate-12">
                {{ reply.mine ? t('OUTSIDER_TEAMS_AREA.YOU') : reply.sender_name }}
              </span>
              <span class="ml-1.5 text-xs text-n-slate-10">
                {{ timeOf(reply.sent_at) }}
              </span>
              <span
                v-if="reply.mentions_me"
                class="ml-1.5 px-1.5 text-[11px] font-semibold rounded-md tms-soft"
              >
                @ {{ t('OUTSIDER_TEAMS_AREA.MENTIONED_YOU') }}
              </span>
              <i v-if="reply.deleted" class="block text-n-slate-10">
                {{ t('OUTSIDER_TEAMS_AREA.DELETED') }}
              </i>
              <div
                v-else
                class="leading-relaxed break-words whitespace-pre-wrap text-n-slate-12"
              >
                {{ reply.content }}
                <TeamsAttachments :message="reply" />
              </div>
              <span
                v-if="reply.status !== 'sent'"
                class="text-[11px]"
                :class="reply.status === 'failed' ? 'text-n-ruby-11' : 'text-n-slate-10'"
              >
                {{
                  reply.status === 'failed'
                    ? t('OUTSIDER_TEAMS_AREA.FAILED')
                    : t('OUTSIDER_TEAMS_AREA.SENDING')
                }}
                <button
                  v-if="reply.status === 'failed'"
                  type="button"
                  class="font-semibold underline"
                  @click="retry(reply)"
                >
                  {{ t('OUTSIDER_TEAMS_AREA.RETRY') }}
                </button>
              </span>
            </div>
          </div>
        </div>

        <footer
          v-if="post.graph_id && canWrite"
          class="flex items-center gap-4 py-2 pr-4 text-sm font-semibold border-t pl-[60px] border-n-weak tms-text"
        >
          <button
            type="button"
            class="flex items-center gap-1.5 hover:underline"
            @click="answer(post)"
          >
            <Icon icon="i-lucide-reply" class="size-4" />
            {{ t('OUTSIDER_TEAMS_AREA.REPLY') }}
          </button>
        </footer>
      </article>
    </div>
    <TeamsComposer
      ref="composer"
      :sender-name="currentUser?.name || ''"
      :replying-to="replyTo"
      :placeholder="
        replyTo
          ? t('OUTSIDER_TEAMS_AREA.WRITE_REPLY')
          : t('OUTSIDER_TEAMS_AREA.WRITE_POST')
      "
      :disabled="!canWrite"
      :is-sending="isSending"
      show-new-post
      :load-members="loadMembers"
      @cancel-reply="replyTo = null"
      @send="onSend"
    />
  </div>
</template>
