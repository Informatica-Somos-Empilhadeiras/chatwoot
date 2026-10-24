<script setup>
// OUTSIDER: botões ao lado da bolha, como no WhatsApp Web (Entrega 21): reagir com um emoji e encaminhar.
// Aparecem com o mouse sobre a bolha (do lado de fora dela); a escolha de emoji fica aberta até escolher
// ou clicar fora. O emoji que a empresa já usou fica marcado e clicar nele de novo tira a reação.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';
import { QUICK_REACTIONS } from 'dashboard/helper/outsider/whatsappMessage';

defineProps({
  side: { type: String, default: 'right' },
  canReact: { type: Boolean, default: false },
  canForward: { type: Boolean, default: false },
  myReaction: { type: String, default: '' },
});

const emit = defineEmits(['react', 'forward']);

const { t } = useI18n();
const isPicking = ref(false);

const pick = emoji => {
  isPicking.value = false;
  emit('react', emoji);
};

const buttonClass =
  'grid transition-colors rounded-full shadow-sm size-6 place-content-center bg-n-solid-1 text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-weak hover:text-n-slate-12 hover:bg-n-alpha-2';
</script>

<template>
  <!-- contents: os botões e a escolha de emoji se posicionam pela bolha (BubbleMenuFrame) -->
  <OnClickOutside
    v-if="canReact || canForward"
    class="contents"
    @trigger="isPicking = false"
  >
    <div
      class="absolute z-20 flex-col gap-1 -translate-y-1/2 top-1/2"
      :class="[
        side === 'left'
          ? 'ltr:right-full ltr:pr-1.5 rtl:left-full rtl:pl-1.5'
          : 'ltr:left-full ltr:pl-1.5 rtl:right-full rtl:pr-1.5',
        isPicking ? 'flex' : 'hidden group-hover:flex',
      ]"
    >
      <button
        v-if="canReact"
        type="button"
        :class="buttonClass"
        :title="t('OUTSIDER_WHATSAPP.REACTIONS.REACT')"
        :aria-expanded="isPicking"
        data-react-button
        @click.stop="isPicking = !isPicking"
      >
        <span class="i-lucide-smile-plus size-3.5" />
      </button>
      <button
        v-if="canForward"
        type="button"
        :class="buttonClass"
        :title="t('OUTSIDER_WHATSAPP.FORWARD.BUTTON')"
        data-forward-button
        @click.stop="emit('forward')"
      >
        <span class="i-lucide-forward size-3.5" />
      </button>
    </div>
    <!-- acima da bolha, a partir da borda do lado da conversa (a bolha da empresa fica à direita) -->
    <div
      v-if="isPicking"
      class="absolute z-30 flex items-center gap-0.5 p-1 rounded-full shadow-lg bottom-full mb-1.5 bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
      :class="
        side === 'left' ? 'ltr:right-0 rtl:left-0' : 'ltr:left-0 rtl:right-0'
      "
      data-reaction-picker
    >
      <button
        v-for="emoji in QUICK_REACTIONS"
        :key="emoji"
        type="button"
        class="grid text-xl transition-transform rounded-full size-9 place-content-center hover:scale-125 hover:bg-n-alpha-2"
        :class="{ 'bg-n-alpha-3': emoji === myReaction }"
        :title="
          emoji === myReaction ? t('OUTSIDER_WHATSAPP.REACTIONS.REMOVE') : ''
        "
        @click.stop="pick(emoji === myReaction ? '' : emoji)"
      >
        {{ emoji }}
      </button>
    </div>
  </OnClickOutside>
</template>
