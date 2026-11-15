<script setup>
// OUTSIDER: figurinha do WhatsApp (ver helper/outsider/sticker.js). Sem balão: só a imagem (160px, webp com
// fundo transparente) e a hora numa pílula embaixo, como no WhatsApp. Em grupo, quem mandou em cima. Ao passar
// o mouse (ou sempre, no celular) aparece "Salvar", que leva a figurinha para a coleção do atendente
// (stickerStore.js); se já estava lá, o servidor avisa e nada é duplicado.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BaseBubble from '../bubbles/Base.vue';
import MessageMeta from '../MessageMeta.vue';
import { useMessageContext } from '../provider.js';
import { ORIENTATION } from '../constants';
import { splitSenderHeader } from 'dashboard/helper/outsider/mediaAlbum';
import { stickerUrlOf } from 'dashboard/helper/outsider/sticker';
import {
  saveAttachmentAsSticker,
  stickerErrorText,
  stickerState,
} from 'dashboard/components/widgets/WootWriter/outsider/stickerStore';

const { attachments, content, orientation, shouldGroupWithNext } =
  useMessageContext();
const { t } = useI18n();

const attachment = computed(() => attachments.value[0] || {});
const url = computed(() => stickerUrlOf(attachment.value));
const senderHeader = computed(
  () => splitSenderHeader(content.value || '').header
);
const isRight = computed(() => orientation.value === ORIENTATION.RIGHT);

const failed = ref(false);
// a mensagem pode chegar antes do arquivo (eco da Evolution chega em duas vezes): quando a URL muda, tenta de novo
watch(url, () => {
  failed.value = false;
});
const saving = ref(false);
const alreadySaved = computed(() =>
  stickerState.savedAttachmentIds.includes(attachment.value.id)
);
const canSave = computed(() => !!attachment.value.id && !failed.value);

const save = async () => {
  if (saving.value || !canSave.value) return;
  saving.value = true;
  try {
    const data = await saveAttachmentAsSticker(attachment.value.id);
    useAlert(
      t(
        data?.existed
          ? 'OUTSIDER_WHATSAPP.STICKERS.EXISTED'
          : 'OUTSIDER_WHATSAPP.STICKERS.SAVED'
      )
    );
  } catch (error) {
    useAlert(stickerErrorText(t, error, 'SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <BaseBubble
    hide-meta
    class="!bg-transparent !shadow-none group/sticker"
    data-bubble-name="sticker"
  >
    <p
      v-if="senderHeader"
      class="px-1 pb-1 mb-0 text-xs font-semibold text-n-slate-11"
    >
      {{ `${senderHeader}:` }}
    </p>
    <div class="relative size-40 max-w-full">
      <img
        v-if="url && !failed"
        :src="url"
        alt=""
        class="object-contain select-none size-full skip-context-menu"
        draggable="false"
        data-sticker-image
        @error="failed = true"
      />
      <div
        v-else
        class="grid size-full rounded-xl bg-n-alpha-2 place-content-center text-n-slate-11"
      >
        <span class="i-lucide-sticker size-8" />
      </div>
      <button
        v-if="canSave"
        type="button"
        class="absolute bottom-1 flex items-center gap-1 h-7 px-2.5 text-xs font-medium rounded-full shadow transition bg-n-solid-1/95 text-n-slate-12 hover:bg-n-solid-1 opacity-0 group-hover/sticker:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:opacity-100 disabled:opacity-60"
        :class="isRight ? 'ltr:left-1 rtl:right-1' : 'ltr:right-1 rtl:left-1'"
        :disabled="saving"
        :title="t('OUTSIDER_WHATSAPP.STICKERS.SAVE_HINT')"
        data-sticker-save
        @click.stop="save"
      >
        <span
          class="size-3.5"
          :class="
            saving
              ? 'i-lucide-loader-circle animate-spin'
              : alreadySaved
                ? 'i-lucide-check text-n-teal-11'
                : 'i-lucide-plus'
          "
        />
        {{
          alreadySaved
            ? t('OUTSIDER_WHATSAPP.STICKERS.SAVED_SHORT')
            : t('OUTSIDER_WHATSAPP.STICKERS.SAVE')
        }}
      </button>
    </div>
    <div
      v-if="!shouldGroupWithNext"
      class="flex mt-1"
      :class="isRight ? 'justify-end' : 'justify-start'"
    >
      <MessageMeta
        class="px-2 py-0.5 rounded-full bg-n-alpha-black1 text-n-slate-11"
      />
    </div>
  </BaseBubble>
</template>
