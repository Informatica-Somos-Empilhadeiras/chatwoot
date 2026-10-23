<script setup>
// OUTSIDER: clipe da caixa de resposta com o menu do WhatsApp: Documento, Fotos e vídeos, Contato,
// Localização e Resposta rápida. Documento e fotos usam o envio de arquivos original do Chatwoot
// (o ComposerBar.vue abre o seletor dele); contato e localização só aparecem nas caixas da Evolution.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside, onKeyStroke } from '@vueuse/core';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SendContactDialog from './SendContactDialog.vue';
import SendLocationDialog from './SendLocationDialog.vue';

const props = defineProps({
  conversationId: { type: Number, default: null },
  canAttach: { type: Boolean, default: false },
  canShareWhatsapp: { type: Boolean, default: false },
  canQuickReply: { type: Boolean, default: false },
});

const emit = defineEmits(['pickFiles', 'quickReply']);

const { t } = useI18n();

const rootRef = ref(null);
const isOpen = ref(false);
const contactDialog = ref(null);
const locationDialog = ref(null);

const groups = computed(() => {
  const share = [];
  if (props.canAttach) {
    share.push(
      {
        key: 'document',
        icon: 'i-ph-file-text-fill',
        color: 'text-[#7F66FF]',
        label: t('OUTSIDER_WHATSAPP.COMPOSER.MENU.DOCUMENT'),
        action: () => emit('pickFiles', 'any'),
      },
      {
        key: 'media',
        icon: 'i-ph-images-fill',
        color: 'text-[#007BFC]',
        label: t('OUTSIDER_WHATSAPP.COMPOSER.MENU.MEDIA'),
        action: () => emit('pickFiles', 'media'),
      }
    );
  }
  if (props.canShareWhatsapp && props.conversationId) {
    share.push(
      {
        key: 'contact',
        icon: 'i-ph-user-fill',
        color: 'text-[#009DE2]',
        label: t('OUTSIDER_WHATSAPP.COMPOSER.MENU.CONTACT'),
        action: () => contactDialog.value?.open(),
      },
      {
        key: 'location',
        icon: 'i-ph-map-pin-fill',
        color: 'text-[#00A884]',
        label: t('OUTSIDER_WHATSAPP.COMPOSER.MENU.LOCATION'),
        action: () => locationDialog.value?.open(),
      }
    );
  }
  const extra = props.canQuickReply
    ? [
        {
          key: 'quick-reply',
          icon: 'i-ph-lightning-fill',
          color: 'text-[#FFB938]',
          label: t('OUTSIDER_WHATSAPP.COMPOSER.MENU.QUICK_REPLY'),
          action: () => emit('quickReply'),
        },
      ]
    : [];
  return [share, extra].filter(group => group.length);
});

const choose = item => {
  isOpen.value = false;
  item.action();
};

onClickOutside(rootRef, () => {
  isOpen.value = false;
});
onKeyStroke('Escape', () => {
  isOpen.value = false;
});
</script>

<template>
  <div v-if="groups.length" ref="rootRef" class="relative">
    <button
      v-tooltip.top-start="t('OUTSIDER_WHATSAPP.COMPOSER.ATTACH')"
      type="button"
      class="grid transition-colors rounded-full size-9 place-content-center text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
      :class="{ 'bg-n-alpha-2 text-n-slate-12 ring-1 ring-n-strong': isOpen }"
      :aria-label="t('OUTSIDER_WHATSAPP.COMPOSER.ATTACH')"
      :aria-expanded="isOpen"
      data-composer-attach
      @click="isOpen = !isOpen"
    >
      <Icon icon="i-ph-paperclip" class="size-5" />
    </button>
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="translate-y-1 opacity-0"
      leave-active-class="transition duration-100 ease-in"
      leave-to-class="translate-y-1 opacity-0"
    >
      <div
        v-if="isOpen"
        class="absolute z-50 py-2 border shadow-lg ltr:left-0 rtl:right-0 bottom-full mb-2 min-w-[13rem] rounded-2xl bg-n-solid-2 border-n-weak"
        role="menu"
        data-composer-attach-menu
      >
        <template v-for="(group, index) in groups" :key="index">
          <div v-if="index" class="mx-3 my-1 border-t border-n-weak" />
          <button
            v-for="item in group"
            :key="item.key"
            type="button"
            role="menuitem"
            class="flex items-center w-full gap-3 px-4 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
            :data-composer-item="item.key"
            @click="choose(item)"
          >
            <Icon :icon="item.icon" class="size-5 shrink-0" :class="item.color" />
            {{ item.label }}
          </button>
        </template>
      </div>
    </Transition>
    <SendContactDialog
      v-if="canShareWhatsapp"
      ref="contactDialog"
      :conversation-id="conversationId"
    />
    <SendLocationDialog
      v-if="canShareWhatsapp"
      ref="locationDialog"
      :conversation-id="conversationId"
    />
  </div>
</template>
