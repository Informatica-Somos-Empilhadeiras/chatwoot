<script setup>
// OUTSIDER: encaminhar mensagens da área Teams para até 5 chats/canais da pessoa (Outsider::Teams::Graph::Forward).
// Lista os chats e canais (com busca), um comentário opcional que vai antes e "Encaminhar". Os arquivos são copiados
// para o destino no servidor; a mensagem aparece lá como "enviando" e muda sozinha quando o Teams confirmar.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import { errorText } from './helpers';

const props = defineProps({
  threadId: { type: Number, required: true },
  messageIds: { type: Array, required: true },
});
const emit = defineEmits(['close', 'done']);

const MAX_TARGETS = 5;
const { t } = useI18n();
const loading = ref(true);
const sending = ref(false);
const threads = ref([]);
const query = ref('');
const chosen = ref([]);
const comment = ref('');

const normalize = text =>
  String(text || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

const label = thread =>
  thread.kind === 'channel'
    ? `${thread.title} · ${thread.team_name || ''}`.replace(/ · $/, '')
    : thread.title || t('OUTSIDER_TEAMS_AREA.UNTITLED');

const visible = computed(() => {
  const words = normalize(query.value).split(/\s+/).filter(Boolean);
  return threads.value
    .filter(thread =>
      words.every(word => normalize(label(thread)).includes(word))
    )
    .slice(0, 80);
});

const toggle = thread => {
  if (chosen.value.includes(thread.id)) {
    chosen.value = chosen.value.filter(id => id !== thread.id);
    return;
  }
  if (chosen.value.length >= MAX_TARGETS) {
    useAlert(t('OUTSIDER_TEAMS_AREA.FORWARD.MAX', { count: MAX_TARGETS }));
    return;
  }
  chosen.value = [...chosen.value, thread.id];
};

const load = async () => {
  try {
    const [chats, channels] = await Promise.all([
      TeamsGraphAPI.threads('chat'),
      TeamsGraphAPI.threads('channel'),
    ]);
    const byDate = (a, b) =>
      String(b.last_message_at || '').localeCompare(
        String(a.last_message_at || '')
      );
    threads.value = [
      ...(chats.data.payload || []),
      ...(channels.data.payload || []),
    ].sort(byDate);
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    loading.value = false;
  }
};

const send = async () => {
  if (!chosen.value.length || sending.value) return;
  sending.value = true;
  try {
    await TeamsGraphAPI.forward(props.threadId, {
      messageIds: props.messageIds,
      targetIds: chosen.value,
      comment: comment.value.trim(),
    });
    useAlert(
      t(
        'OUTSIDER_TEAMS_AREA.FORWARD.DONE',
        { count: chosen.value.length },
        chosen.value.length
      )
    );
    emit('done');
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    sending.value = false;
  }
};

onMounted(load);
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      class="fixed inset-0 z-[9998] grid p-4 place-items-center bg-black/50 tms"
      data-teams-forward
      @click.self="emit('close')"
    >
      <div
        class="flex flex-col w-full max-w-md overflow-hidden border shadow-xl rounded-2xl bg-n-solid-2 border-n-weak max-h-[min(40rem,calc(100dvh-2rem))]"
      >
        <header class="flex items-center gap-2 px-4 pt-4 pb-2">
          <span class="i-lucide-forward size-5 tms-text" />
          <h3 class="flex-1 m-0 text-base font-semibold text-n-slate-12">
            {{
              t(
                'OUTSIDER_TEAMS_AREA.FORWARD.TITLE',
                { count: messageIds.length },
                messageIds.length
              )
            }}
          </h3>
          <button
            type="button"
            class="grid rounded-full size-8 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('OUTSIDER_TEAMS_AREA.FORWARD.CANCEL')"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </header>
        <div class="px-4 pb-2">
          <input
            v-model="query"
            type="search"
            class="w-full h-9 px-3 text-sm rounded-lg outline-none bg-n-alpha-1 text-n-slate-12 focus:ring-1 focus:ring-n-brand"
            :placeholder="t('OUTSIDER_TEAMS_AREA.FORWARD.SEARCH')"
            data-teams-forward-search
          />
          <p class="mt-1.5 mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_TEAMS_AREA.FORWARD.HINT', { count: MAX_TARGETS }) }}
          </p>
        </div>
        <div class="flex-1 min-h-[10rem] overflow-y-auto px-2">
          <div v-if="loading" class="flex justify-center py-8">
            <Spinner :size="20" />
          </div>
          <p
            v-else-if="!visible.length"
            class="py-8 m-0 text-sm text-center text-n-slate-11"
          >
            {{ t('OUTSIDER_TEAMS_AREA.NOTHING_FOUND') }}
          </p>
          <button
            v-for="thread in visible"
            :key="thread.id"
            type="button"
            class="flex items-center w-full gap-3 px-2 py-2 text-start rounded-xl hover:bg-n-alpha-1"
            :class="{ 'bg-n-alpha-1': chosen.includes(thread.id) }"
            :data-teams-forward-target="thread.id"
            @click="toggle(thread)"
          >
            <span
              class="grid border-2 rounded-full size-5 place-items-center shrink-0"
              :class="
                chosen.includes(thread.id)
                  ? 'tms-accent-bg border-transparent text-white'
                  : 'border-n-slate-7'
              "
            >
              <span
                v-if="chosen.includes(thread.id)"
                class="i-lucide-check size-3"
              />
            </span>
            <span
              v-if="thread.kind === 'channel'"
              class="grid rounded-lg size-8 place-items-center shrink-0 tms-soft"
            >
              <span class="i-lucide-hash size-4" />
            </span>
            <Avatar
              v-else
              :name="thread.title || '?'"
              :src="thread.peer_photo || ''"
              :size="32"
              rounded-full
            />
            <span class="flex flex-col min-w-0">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ thread.kind === 'channel' ? thread.title : label(thread) }}
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{
                  thread.kind === 'channel'
                    ? thread.team_name
                    : thread.last_message_preview
                }}
              </span>
            </span>
          </button>
        </div>
        <footer
          class="flex flex-col gap-2 px-4 pt-2 pb-4 border-t border-n-weak"
        >
          <textarea
            v-model="comment"
            rows="2"
            maxlength="5000"
            class="w-full px-3 py-2 text-sm rounded-lg outline-none resize-none bg-n-alpha-1 text-n-slate-12 focus:ring-1 focus:ring-n-brand"
            :placeholder="t('OUTSIDER_TEAMS_AREA.FORWARD.COMMENT')"
          />
          <div class="flex items-center gap-2">
            <span class="flex-1 text-xs text-n-slate-11">
              {{
                t(
                  'OUTSIDER_TEAMS_AREA.FORWARD.CHOSEN',
                  { count: chosen.length },
                  chosen.length
                )
              }}
            </span>
            <button
              type="button"
              class="h-9 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              @click="emit('close')"
            >
              {{ t('OUTSIDER_TEAMS_AREA.FORWARD.CANCEL') }}
            </button>
            <button
              type="button"
              class="flex items-center gap-1.5 h-9 px-4 text-sm font-semibold text-white rounded-lg tms-accent-bg disabled:opacity-50"
              :disabled="!chosen.length || sending"
              data-teams-forward-send
              @click="send"
            >
              <span
                :class="
                  sending
                    ? 'i-lucide-loader-circle animate-spin'
                    : 'i-lucide-send'
                "
                class="size-4"
              />
              {{ t('OUTSIDER_TEAMS_AREA.FORWARD.SEND') }}
            </button>
          </div>
        </footer>
      </div>
    </div>
  </TeleportWithDirection>
</template>
