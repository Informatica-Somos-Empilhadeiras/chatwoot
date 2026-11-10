<script setup>
// OUTSIDER: o menu do bot desenhado como o cliente vê no WhatsApp: botões embaixo da mensagem ou o
// botão "☰ Ver opções" que abre a lista. Usado no Testar do editor (interactive) e na bolha da
// conversa (só mostra). O WhatsApp mostra 3 botões por mensagem: de 4 a 6 opções, os botões vão em
// duas mensagens seguidas (2 + 2, 3 + 2, 3 + 3), a segunda com o texto "Mais opções".
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { whatsappHtml, NUMBERS } from './simulator';
import { MAX_BUTTONS } from './nodeTypes';

const props = defineProps({
  text: { type: String, default: '' },
  title: { type: String, default: '' },
  footer: { type: String, default: '' },
  menuStyle: { type: String, default: 'list' },
  buttonLabel: { type: String, default: '' },
  options: { type: Array, default: () => [] },
  interactive: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  chosenId: { type: String, default: '' },
});

const emit = defineEmits(['choose']);

const BUTTONS_PER_MESSAGE = 3;

const { t } = useI18n();
const listOpen = ref(false);

const style = computed(() => {
  if (!props.options.length) return 'text';
  if (props.menuStyle === 'buttons' && props.options.length > MAX_BUTTONS)
    return 'list';
  return props.menuStyle;
});

// os botões de cada mensagem, divididos por igual como o servidor faz (Outsider::Bot::Sender)
const buttonGroups = computed(() => {
  const messages = Math.ceil(props.options.length / BUTTONS_PER_MESSAGE);
  const size = Math.ceil(props.options.length / messages);
  return Array.from({ length: messages }, (_, index) =>
    props.options.slice(index * size, (index + 1) * size)
  );
});

const numbered = computed(() =>
  props.options
    .map(
      (option, index) =>
        `${NUMBERS[index] || `${index + 1}.`} ${option.label}${option.description ? ` — ${option.description}` : ''}`
    )
    .join('\n')
);

const choose = option => {
  if (!props.interactive || props.disabled) return;
  listOpen.value = false;
  emit('choose', option);
};
</script>

<template>
  <div class="flex flex-col gap-1 w-full max-w-[17rem]">
    <div
      class="flex flex-col gap-1 px-3 py-2 text-sm rounded-xl rounded-tl-sm bg-n-solid-1 text-n-slate-12 shadow-sm"
    >
      <!-- eslint-disable vue/no-v-html -->
      <span v-if="title" class="font-semibold" v-html="whatsappHtml(title)" />
      <span v-if="text" class="break-words" v-html="whatsappHtml(text)" />
      <span
        v-if="style === 'text' && options.length"
        class="break-words"
        v-html="whatsappHtml(numbered)"
      />
      <!-- eslint-enable vue/no-v-html -->
      <span v-if="footer" class="text-xs text-n-slate-10">{{ footer }}</span>
      <button
        v-if="style === 'list'"
        type="button"
        class="flex items-center justify-center gap-1.5 pt-2 mt-1 text-sm font-medium border-t border-n-weak text-n-blue-11"
        :class="
          interactive && !disabled ? 'hover:opacity-80' : 'cursor-default'
        "
        @click="interactive && !disabled && (listOpen = !listOpen)"
      >
        <Icon icon="i-lucide-list" class="size-4" />
        {{ buttonLabel || t('OUTSIDER_TOOLS.BOT.PREVIEW.LIST_BUTTON') }}
      </button>
    </div>
    <template v-if="style === 'buttons'">
      <template v-for="(group, index) in buttonGroups" :key="index">
        <span
          v-if="index"
          class="px-3 py-2 mt-1 text-sm rounded-xl rounded-tl-sm bg-n-solid-1 text-n-slate-12 shadow-sm"
        >
          {{ t('OUTSIDER_TOOLS.BOT.PREVIEW.MORE_OPTIONS') }}
        </span>
        <button
          v-for="option in group"
          :key="option.id"
          type="button"
          class="flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-medium rounded-xl bg-n-solid-1 text-n-blue-11 shadow-sm"
          :class="[
            interactive && !disabled ? 'hover:opacity-80' : 'cursor-default',
            chosenId === option.id ? 'ring-1 ring-n-blue-9' : '',
          ]"
          @click="choose(option)"
        >
          <Icon icon="i-lucide-reply" class="size-3.5" />
          {{ option.label }}
        </button>
      </template>
    </template>
    <div
      v-if="style === 'list' && (listOpen || (!interactive && chosenId))"
      class="flex flex-col overflow-hidden text-sm border rounded-xl bg-n-solid-1 border-n-weak shadow-md"
    >
      <span
        class="px-3 py-2 text-xs font-medium text-center border-b border-n-weak text-n-slate-11"
      >
        {{ buttonLabel || t('OUTSIDER_TOOLS.BOT.PREVIEW.LIST_BUTTON') }}
      </span>
      <button
        v-for="option in options"
        :key="option.id"
        type="button"
        class="flex items-center gap-2 px-3 py-2 text-left border-b last:border-b-0 border-n-weak/60"
        :class="interactive ? 'hover:bg-n-alpha-1' : 'cursor-default'"
        @click="choose(option)"
      >
        <span class="flex flex-col flex-1 min-w-0">
          <span class="text-n-slate-12">{{ option.label }}</span>
          <span v-if="option.description" class="text-xs text-n-slate-10">
            {{ option.description }}
          </span>
        </span>
        <span
          class="rounded-full size-4 shrink-0 border-2"
          :class="
            chosenId === option.id
              ? 'border-n-teal-9 bg-n-teal-9'
              : 'border-n-slate-7'
          "
        />
      </button>
    </div>
  </div>
</template>
