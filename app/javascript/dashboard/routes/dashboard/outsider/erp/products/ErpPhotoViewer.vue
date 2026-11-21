<script setup>
// OUTSIDER: as fotos de um produto do ERP uma por vez (carrossel): setas (ou ← →) trocam, as miniaturas embaixo pulam
// direto. "Copiar" põe a imagem na área de transferência (para colar no WhatsApp Web, num e-mail...), "Baixar" salva o
// arquivo e, aberto de um orçamento, "Enviar ao cliente" manda a foto na conversa que já existe com ele (a do chat, ou a
// aberta no WhatsApp; nunca abre conversa nova: Outsider::Erp::PhotoSender).
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { erpErrorMessage } from '../erpStore';
import { budgetErrorMessage } from '../budgets/budgetHelpers';
import { photoUrl, pngBlob } from './photoCache';

const { t } = useI18n();
const rootRef = ref(null);
const isOpen = ref(false);
const loading = ref(false);
const failure = ref('');
const product = ref({ company: '', code: 0, title: '' });
const photos = ref([]);
const index = ref(0);
const urls = ref({});
const broken = ref({});
// para quem mandar: { conversationId, contactId } do orçamento; sem isso não há envio
const target = ref(null);
const sending = ref(false);
const composing = ref(false);
const message = ref('');

const current = computed(() => photos.value[index.value]);
const currentUrl = computed(
  () => current.value && urls.value[current.value.id]
);
const canSend = computed(
  () => !!(target.value?.conversationId || target.value?.contactId)
);

const load = photo => {
  if (urls.value[photo.id] || broken.value[photo.id]) return;
  const { company, code } = product.value;
  photoUrl(company, code, photo.id)
    .then(url => {
      urls.value = { ...urls.value, [photo.id]: url };
    })
    .catch(() => {
      broken.value = { ...broken.value, [photo.id]: true };
    });
};

const go = next => {
  const total = photos.value.length;
  if (!total) return;
  index.value = (next + total) % total;
  composing.value = false;
  load(photos.value[index.value]);
  // as outras vêm logo atrás (as miniaturas mostram todas)
  photos.value.forEach(load);
};

// options: { company, code, title, photos (se já tiver a lista), index, target }
const open = async options => {
  product.value = {
    company: options.company,
    code: options.code,
    title: options.title || '',
  };
  target.value = options.target || null;
  photos.value = options.photos || [];
  urls.value = {};
  broken.value = {};
  failure.value = '';
  composing.value = false;
  message.value = '';
  isOpen.value = true;
  nextTick(() => rootRef.value?.focus());
  if (!options.photos) {
    loading.value = true;
    try {
      const { data } = await ErpAPI.productPhotos(
        options.company,
        options.code
      );
      photos.value = data.fotos || [];
    } catch (error) {
      failure.value = erpErrorMessage(t, error);
    } finally {
      loading.value = false;
    }
  }
  go(options.index || 0);
};

const close = () => {
  isOpen.value = false;
};

const onKey = event => {
  if (event.target.tagName === 'TEXTAREA') return;
  if (event.key === 'ArrowRight') go(index.value + 1);
  if (event.key === 'ArrowLeft') go(index.value - 1);
};

const copy = async () => {
  if (!currentUrl.value) return;
  if (!navigator.clipboard?.write || !window.ClipboardItem) {
    useAlert(t('OUTSIDER_ERP.PRODUCTS.PHOTOS.COPY_UNSUPPORTED'));
    return;
  }
  try {
    // a promessa vai direto no ClipboardItem: o Safari só aceita assim, dentro do clique
    await navigator.clipboard.write([
      new window.ClipboardItem({ 'image/png': pngBlob(currentUrl.value) }),
    ]);
    useAlert(t('OUTSIDER_ERP.PRODUCTS.PHOTOS.COPIED'));
  } catch {
    useAlert(t('OUTSIDER_ERP.PRODUCTS.PHOTOS.COPY_FAILED'));
  }
};

const download = () => {
  if (!currentUrl.value) return;
  const link = document.createElement('a');
  link.href = currentUrl.value;
  link.download = current.value.nome;
  link.click();
};

const send = async () => {
  if (!current.value || sending.value) return;
  sending.value = true;
  try {
    const { company, code } = product.value;
    await ErpAPI.sendProductPhoto(company, code, current.value.id, {
      conversation_id: target.value.conversationId || undefined,
      contact_id: target.value.contactId || undefined,
      message: message.value.trim() || undefined,
    });
    useAlert(t('OUTSIDER_ERP.PRODUCTS.PHOTOS.SENT'));
    composing.value = false;
    message.value = '';
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    sending.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      ref="rootRef"
      tabindex="-1"
      class="fixed inset-0 z-[10001] flex items-center justify-center outline-none sm:p-6 bg-n-alpha-black1 backdrop-blur-[2px]"
      @keydown="onKey"
      @keydown.esc.stop="close"
      @click.self="close"
    >
      <div
        class="grid grid-rows-[auto_minmax(0,1fr)_auto_auto] w-full h-full sm:w-[min(64rem,100%)] sm:h-[min(52rem,100%)] overflow-hidden shadow-xl sm:rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
      >
        <header
          class="flex items-center gap-3 px-4 py-3 border-b border-n-weak"
        >
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_ERP.PRODUCTS.CODE', { code: product.code }) }}
            </span>
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ product.title }}
            </span>
          </div>
          <span
            v-if="photos.length"
            class="px-2.5 py-1 text-sm font-semibold rounded-lg shrink-0 tabular-nums bg-n-alpha-2 text-n-slate-12"
          >
            {{
              t('OUTSIDER_ERP.PRODUCTS.PHOTOS.COUNTER', {
                current: index + 1,
                total: photos.length,
              })
            }}
          </span>
          <Button
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :aria-label="t('OUTSIDER_ERP.CANCEL')"
            @click="close"
          />
        </header>

        <div class="relative min-h-[16rem] bg-n-alpha-1">
          <div
            v-if="loading || (current && !currentUrl && !broken[current.id])"
            class="absolute inset-0 flex items-center justify-center"
          >
            <Spinner class="text-n-slate-10" />
          </div>
          <p
            v-else-if="failure || !photos.length || broken[current.id]"
            class="absolute inset-0 flex items-center justify-center px-6 mb-0 text-sm text-center text-n-slate-11"
          >
            {{
              failure ||
              (photos.length
                ? t('OUTSIDER_ERP.PRODUCTS.PHOTOS.MISSING')
                : t('OUTSIDER_ERP.PRODUCTS.PHOTOS.NONE'))
            }}
          </p>
          <img
            v-else-if="currentUrl"
            :src="currentUrl"
            :alt="current.nome"
            class="absolute inset-0 object-contain m-auto max-w-full max-h-full p-3"
          />
          <template v-if="photos.length > 1">
            <button
              type="button"
              class="absolute flex items-center justify-center -translate-y-1/2 rounded-full shadow-lg left-3 top-1/2 size-11 bg-n-slate-12 text-n-slate-1 opacity-90 hover:opacity-100"
              :aria-label="t('OUTSIDER_ERP.PRODUCTS.PHOTOS.PREVIOUS')"
              @click="go(index - 1)"
            >
              <Icon icon="i-lucide-chevron-left" class="size-6" />
            </button>
            <button
              type="button"
              class="absolute flex items-center justify-center -translate-y-1/2 rounded-full shadow-lg right-3 top-1/2 size-11 bg-n-slate-12 text-n-slate-1 opacity-90 hover:opacity-100"
              :aria-label="t('OUTSIDER_ERP.PRODUCTS.PHOTOS.NEXT')"
              @click="go(index + 1)"
            >
              <Icon icon="i-lucide-chevron-right" class="size-6" />
            </button>
            <div
              class="absolute flex gap-1.5 -translate-x-1/2 bottom-3 left-1/2 px-2.5 py-1.5 rounded-full bg-n-slate-12/80"
            >
              <span
                v-for="(photo, position) in photos"
                :key="photo.id"
                class="rounded-full size-2"
                :class="position === index ? 'bg-n-slate-1' : 'bg-n-slate-1/40'"
              />
            </div>
          </template>
        </div>

        <div
          class="flex gap-2 px-4 py-3 overflow-x-auto border-t border-n-weak"
          :class="{ hidden: photos.length < 2 }"
        >
          <button
            v-for="(photo, position) in photos"
            :key="photo.id"
            type="button"
            class="relative flex items-center justify-center overflow-hidden rounded-lg shrink-0 size-16 bg-n-alpha-2 outline -outline-offset-2"
            :class="
              position === index
                ? 'outline-2 outline-n-brand'
                : 'outline-1 outline-n-weak opacity-70 hover:opacity-100'
            "
            :aria-label="
              t('OUTSIDER_ERP.PRODUCTS.PHOTOS.COUNTER', {
                current: position + 1,
                total: photos.length,
              })
            "
            @click="go(position)"
          >
            <img
              v-if="urls[photo.id]"
              :src="urls[photo.id]"
              alt=""
              class="object-cover w-full h-full"
            />
            <Icon v-else icon="i-lucide-image" class="size-4 text-n-slate-9" />
            <span
              class="absolute bottom-0.5 right-0.5 min-w-[1.125rem] px-1 text-[11px] font-semibold leading-[1.125rem] text-center rounded bg-n-slate-12 text-n-slate-1"
            >
              {{ position + 1 }}
            </span>
          </button>
        </div>

        <div
          v-if="composing"
          class="flex flex-col gap-2 px-4 py-3 border-t border-n-weak"
        >
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_ERP.PRODUCTS.PHOTOS.SEND_HINT') }}
          </span>
          <textarea
            v-model="message"
            rows="2"
            maxlength="4000"
            :placeholder="t('OUTSIDER_ERP.PRODUCTS.PHOTOS.MESSAGE')"
            class="!mb-0 px-2 py-1.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand"
          />
          <div class="flex justify-end gap-2">
            <Button
              variant="faded"
              color="slate"
              :label="t('OUTSIDER_ERP.CANCEL')"
              @click="composing = false"
            />
            <Button
              color="teal"
              icon="i-lucide-send"
              :label="t('OUTSIDER_ERP.PRODUCTS.PHOTOS.SEND_NOW')"
              :is-loading="sending"
              @click="send"
            />
          </div>
        </div>

        <footer
          v-else
          class="flex flex-wrap items-center gap-2 px-4 py-3 border-t border-n-weak"
        >
          <span
            class="flex-1 min-w-0 text-xs truncate text-n-slate-10"
            :title="current?.nome"
          >
            {{ current?.nome }}
          </span>
          <Button
            color="slate"
            icon="i-lucide-copy"
            :label="t('OUTSIDER_ERP.PRODUCTS.PHOTOS.COPY')"
            :disabled="!currentUrl"
            @click="copy"
          />
          <Button
            color="slate"
            icon="i-lucide-download"
            :label="t('OUTSIDER_ERP.BUDGET.PDF.DOWNLOAD')"
            :disabled="!currentUrl"
            @click="download"
          />
          <Button
            v-if="canSend"
            color="teal"
            icon="i-lucide-message-circle"
            :label="t('OUTSIDER_ERP.PRODUCTS.PHOTOS.SEND')"
            :disabled="!currentUrl"
            @click="composing = true"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>
