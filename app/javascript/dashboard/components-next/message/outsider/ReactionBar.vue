<script setup>
// OUTSIDER: reações no pé da bolha, como no WhatsApp (Entrega 21). Mostra os emojis mais usados e quantas
// pessoas reagiram; o clique abre quem reagiu, com uma aba por emoji (nos grupos, nome e número de cada
// participante). A reação da empresa aparece como "Você" e, quando dá, clicar nela tira a reação.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import {
  formatWhatsappPhone,
  reactionSummary,
} from 'dashboard/helper/outsider/whatsappMessage';

const props = defineProps({
  reactions: { type: Array, required: true },
  align: { type: String, default: 'start' },
  canRemove: { type: Boolean, default: false },
});

const emit = defineEmits(['remove']);

const { t } = useI18n();
const isOpen = ref(false);
const tab = ref('');

const summary = computed(() => reactionSummary(props.reactions));

const people = computed(() =>
  props.reactions
    .filter(reaction => !tab.value || reaction.emoji === tab.value)
    .sort((a, b) => b.isMe - a.isMe || b.createdAt - a.createdAt)
);

const nameOf = reaction => {
  if (reaction.isMe) return t('OUTSIDER_WHATSAPP.REACTIONS.YOU');
  return (
    reaction.name ||
    formatWhatsappPhone(reaction.phone) ||
    t('OUTSIDER_WHATSAPP.REACTIONS.SOMEONE')
  );
};

const detailOf = reaction => {
  if (reaction.isMe) {
    return props.canRemove
      ? t('OUTSIDER_WHATSAPP.REACTIONS.TAP_TO_REMOVE')
      : '';
  }
  return reaction.name ? formatWhatsappPhone(reaction.phone) : '';
};

// na metade de baixo da tela, a lista abre para cima (a caixa de resposta cobriria)
const opensUp = ref(false);

const toggle = event => {
  tab.value = '';
  opensUp.value =
    event.currentTarget.getBoundingClientRect().top > window.innerHeight / 2;
  isOpen.value = !isOpen.value;
};

const remove = reaction => {
  if (!reaction.isMe || !props.canRemove) return;
  isOpen.value = false;
  emit('remove');
};

const tabClass = active =>
  active
    ? 'border-n-teal-9 text-n-slate-12'
    : 'border-transparent text-n-slate-11 hover:text-n-slate-12';
</script>

<template>
  <OnClickOutside
    class="relative z-10 flex -mt-2.5 mx-2"
    :class="align === 'end' ? 'justify-end' : 'justify-start'"
    @trigger="isOpen = false"
  >
    <button
      type="button"
      class="flex items-center gap-0.5 px-1.5 py-0.5 text-sm rounded-full shadow-sm bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak hover:bg-n-alpha-2"
      :title="t('OUTSIDER_WHATSAPP.REACTIONS.WHO')"
      data-reaction-bar
      @click.stop="toggle($event)"
    >
      <span v-for="item in summary.slice(0, 3)" :key="item.emoji">
        {{ item.emoji }}
      </span>
      <span
        v-if="reactions.length > 1"
        class="text-xs tabular-nums ltr:ml-0.5 rtl:mr-0.5 text-n-slate-11"
      >
        {{ reactions.length }}
      </span>
    </button>

    <div
      v-if="isOpen"
      class="absolute flex flex-col overflow-hidden shadow-xl w-72 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
      :class="[
        align === 'end' ? 'ltr:right-0 rtl:left-0' : 'ltr:left-0 rtl:right-0',
        opensUp ? 'bottom-full mb-1' : 'top-full mt-1',
      ]"
      data-reaction-people
    >
      <div class="flex gap-1 px-2 overflow-x-auto border-b border-n-weak">
        <button
          type="button"
          class="px-2 py-2 text-sm border-b-2 shrink-0"
          :class="tabClass(!tab)"
          @click.stop="tab = ''"
        >
          {{
            t('OUTSIDER_WHATSAPP.REACTIONS.ALL', { count: reactions.length })
          }}
        </button>
        <button
          v-for="item in summary"
          :key="item.emoji"
          type="button"
          class="px-2 py-2 text-sm border-b-2 shrink-0"
          :class="tabClass(tab === item.emoji)"
          @click.stop="tab = item.emoji"
        >
          {{ item.emoji }}
          <span class="text-xs tabular-nums">{{ item.count }}</span>
        </button>
      </div>
      <ul class="flex flex-col py-1 mb-0 overflow-y-auto max-h-64">
        <li v-for="reaction in people" :key="reaction.key">
          <button
            type="button"
            class="flex items-center w-full gap-3 px-3 py-2 text-start"
            :class="
              reaction.isMe && canRemove
                ? 'hover:bg-n-alpha-1 cursor-pointer'
                : 'cursor-default'
            "
            @click.stop="remove(reaction)"
          >
            <Avatar
              :name="nameOf(reaction)"
              :src="reaction.thumbnail || ''"
              :size="32"
              rounded-full
            />
            <span class="flex flex-col flex-1 min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ nameOf(reaction) }}
              </span>
              <span
                v-if="detailOf(reaction)"
                class="text-xs truncate text-n-slate-11"
              >
                {{ detailOf(reaction) }}
              </span>
            </span>
            <span class="text-xl">{{ reaction.emoji }}</span>
          </button>
        </li>
      </ul>
    </div>
  </OnClickOutside>
</template>
