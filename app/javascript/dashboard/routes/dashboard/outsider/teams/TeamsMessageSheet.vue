<script setup>
// OUTSIDER: menu de uma mensagem no celular/tablet (segurar o dedo no balão), no lugar dos botões que no computador
// aparecem ao passar o mouse: reagir (as seis do Teams), responder, copiar o texto, encaminhar e selecionar várias.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import { errorText } from './helpers';

const props = defineProps({
  message: { type: Object, required: true },
  canWrite: { type: Boolean, default: false },
  canForward: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'reply', 'forward', 'select', 'reacted']);

const QUICK = ['👍', '❤️', '😆', '😮', '😢', '😡'];

const { t } = useI18n();
const busy = ref(false);
// o dedo que segurou ainda gera um toque ao soltar: o menu só aceita toques depois de um instante
const ready = ref(false);
onMounted(() => setTimeout(() => (ready.value = true), 400));

const sent = computed(
  () =>
    !!props.message.graph_id &&
    !props.message.deleted &&
    props.message.status === 'sent'
);
const canReact = computed(() => props.canWrite && sent.value);
const mineReaction = emoji =>
  (props.message.reactions || []).some(
    item => item.emoji === emoji && item.mine
  );

const react = async emoji => {
  if (busy.value) return;
  busy.value = true;
  try {
    const { data } = await TeamsGraphAPI.react(
      props.message.thread_id,
      props.message.id,
      emoji,
      !mineReaction(emoji)
    );
    emit('reacted', data);
    emit('close');
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    busy.value = false;
  }
};

const copy = async () => {
  await copyTextToClipboard(props.message.content || '');
  useAlert(t('OUTSIDER_TEAMS_AREA.SHEET.COPIED'));
  emit('close');
};

const actions = computed(() =>
  [
    props.canWrite &&
      sent.value && {
        key: 'reply',
        icon: 'i-lucide-reply',
        label: t('OUTSIDER_TEAMS_AREA.REPLY'),
      },
    props.message.content && {
      key: 'copy',
      icon: 'i-lucide-copy',
      label: t('OUTSIDER_TEAMS_AREA.SHEET.COPY'),
    },
    props.canForward && {
      key: 'forward',
      icon: 'i-lucide-forward',
      label: t('OUTSIDER_TEAMS_AREA.FORWARD.BUTTON'),
    },
    props.canForward && {
      key: 'select',
      icon: 'i-lucide-list-checks',
      label: t('OUTSIDER_TEAMS_AREA.SELECT.BUTTON'),
    },
  ].filter(Boolean)
);

const run = key => {
  if (key === 'copy') {
    copy();
    return;
  }
  emit(key);
  emit('close');
};
</script>

<template>
  <Teleport to="body">
    <div
      class="tms fixed inset-0 z-[60] flex flex-col justify-end"
      :class="ready ? '' : 'pointer-events-none'"
    >
      <div
        class="absolute inset-0 bg-n-alpha-black2"
        :aria-label="t('OUTSIDER_TEAMS_AREA.SHEET.CLOSE')"
        @click="emit('close')"
      />
      <div
        class="relative w-full max-w-lg mx-auto rounded-t-3xl bg-n-solid-1 shadow-2xl pb-[max(0.75rem,env(safe-area-inset-bottom))]"
        data-teams-message-sheet
      >
        <span class="block w-10 h-1 mx-auto mt-2.5 rounded-full bg-n-slate-6" />
        <p
          v-if="message.content"
          class="px-5 pt-3 mb-0 text-sm line-clamp-2 text-n-slate-11"
        >
          {{ message.content }}
        </p>
        <div
          v-if="canReact"
          class="flex items-center justify-between gap-1 px-4 pt-3 pb-1"
        >
          <button
            v-for="emoji in QUICK"
            :key="emoji"
            type="button"
            class="grid text-2xl rounded-full size-12 place-items-center bg-n-alpha-1 active:scale-110"
            :class="mineReaction(emoji) ? 'tms-soft tms-outline' : ''"
            :disabled="busy"
            @click="react(emoji)"
          >
            {{ emoji }}
          </button>
        </div>
        <ul class="px-2 pt-2 mb-0">
          <li v-for="action in actions" :key="action.key">
            <button
              type="button"
              class="flex items-center w-full gap-4 px-4 text-base rounded-xl h-[52px] text-n-slate-12 active:bg-n-alpha-2"
              :data-teams-sheet-action="action.key"
              @click="run(action.key)"
            >
              <Icon :icon="action.icon" class="size-5 text-n-slate-11" />
              {{ action.label }}
            </button>
          </li>
        </ul>
      </div>
    </div>
  </Teleport>
</template>
