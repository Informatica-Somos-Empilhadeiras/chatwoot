<script setup>
// OUTSIDER: reações de uma mensagem da área Teams, como no Teams: as reações embaixo do balão (emoji e quantas
// pessoas; passar o mouse mostra quem reagiu; a sua fica destacada e clicar tira) e o botão de reagir, com as seis
// mais usadas do Teams e "mais emojis". A reação vai para o Teams em nome da pessoa.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import EmojiPicker from 'shared/components/emoji/EmojiPicker.vue';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import { errorText } from './helpers';

const props = defineProps({
  message: { type: Object, required: true },
  canReact: { type: Boolean, default: false },
  // only: 'chips' (só as reações) | 'button' (só o botão de reagir) | '' (os dois)
  only: { type: String, default: '' },
  alignEnd: { type: Boolean, default: false },
});

const emit = defineEmits(['updated']);

const QUICK = ['👍', '❤️', '😆', '😮', '😢', '😡'];

const { t } = useI18n();
const open = ref(false);
const more = ref(false);
// a caixinha abre para o lado que tem espaço na tela
const toRight = ref(false);
const toggleOpen = event => {
  const box = event.currentTarget.getBoundingClientRect();
  toRight.value = box.left > window.innerWidth / 2;
  open.value = !open.value;
  more.value = false;
};
const busy = ref(false);
const root = ref(null);

const reactions = computed(() => props.message.reactions || []);
const enabled = computed(
  () =>
    props.canReact &&
    !!props.message.graph_id &&
    !props.message.deleted &&
    props.message.status === 'sent'
);

onClickOutside(root, () => {
  open.value = false;
  more.value = false;
});

const react = async (emoji, on) => {
  if (!enabled.value || busy.value) return;
  open.value = false;
  more.value = false;
  busy.value = true;
  try {
    const { data } = await TeamsGraphAPI.react(
      props.message.thread_id,
      props.message.id,
      emoji,
      on
    );
    emit('updated', data);
  } catch (error) {
    useAlert(errorText(error, t));
  } finally {
    busy.value = false;
  }
};

const toggle = item => react(item.emoji, !item.mine);
const pick = emoji => {
  const found = reactions.value.find(item => item.emoji === emoji);
  react(emoji, !found?.mine);
};

const who = item => item.names.join(', ');
</script>

<template>
  <span
    ref="root"
    class="relative contents"
    :class="alignEnd ? 'justify-end' : ''"
  >
    <span
      v-if="only !== 'button' && reactions.length"
      class="flex flex-wrap gap-1 mt-1"
      :class="alignEnd ? 'justify-end' : ''"
      data-teams-reactions
    >
      <button
        v-for="item in reactions"
        :key="item.emoji"
        type="button"
        class="flex items-center gap-1 px-1.5 h-6 text-xs border rounded-full bg-n-surface-1"
        :class="
          item.mine ? 'tms-reaction-mine' : 'border-n-weak text-n-slate-11'
        "
        :title="who(item)"
        :disabled="!enabled"
        @click="toggle(item)"
      >
        <span class="text-sm leading-none">{{ item.emoji }}</span>
        <span v-if="item.count > 1" class="font-semibold">{{
          item.count
        }}</span>
      </button>
    </span>
    <span v-if="only !== 'chips' && enabled" class="relative inline-flex">
      <button
        type="button"
        class="grid transition-opacity rounded-full opacity-0 size-7 place-items-center shrink-0 text-n-slate-11 hover:bg-n-alpha-2 group-hover:opacity-100 focus:opacity-100"
        :class="open ? '!opacity-100 bg-n-alpha-2' : ''"
        :title="t('OUTSIDER_TEAMS_AREA.REACT')"
        data-teams-react
        @click="toggleOpen"
      >
        <Icon icon="i-lucide-smile-plus" class="size-4" />
      </button>
      <span
        v-if="open"
        class="absolute z-30 flex items-center gap-0.5 p-1 border shadow-lg bottom-full mb-1 rounded-full bg-n-surface-1 border-n-weak"
        :class="toRight ? 'right-0' : 'left-0'"
        data-teams-quick-reactions
      >
        <button
          v-for="emoji in QUICK"
          :key="emoji"
          type="button"
          class="grid text-xl transition-transform rounded-full size-9 place-items-center hover:scale-125 hover:bg-n-alpha-2"
          @click="pick(emoji)"
        >
          {{ emoji }}
        </button>
        <button
          type="button"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 hover:bg-n-alpha-2"
          :title="t('OUTSIDER_TEAMS_AREA.MORE_EMOJIS')"
          @click="more = !more"
        >
          <Icon icon="i-lucide-plus" class="size-4" />
        </button>
      </span>
      <EmojiPicker
        v-if="open && more"
        class="bottom-full mb-14"
        :class="toRight ? 'right-0' : 'left-0'"
        @select="item => pick(item.emoji)"
      />
    </span>
  </span>
</template>
