<script setup>
// OUTSIDER: a primeira foto do produto em miniatura, no lugar do ícone de caixa (busca do orçamento, itens já escolhidos
// e lista da aba Produtos), com quantas fotos ele tem. Clicar abre o carrossel. Enquanto carrega (ou se a miniatura não
// abrir) fica o ícone de fotos, ainda clicável.
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { thumbnailUrl } from './photoCache';

const props = defineProps({
  company: { type: String, required: true },
  code: { type: Number, required: true },
  count: { type: Number, required: true },
  // classes de tamanho (size-12, size-10...)
  size: { type: String, default: 'size-14' },
});

const emit = defineEmits(['open']);

const { t } = useI18n();
const url = ref('');

watch(
  () => [props.company, props.code],
  ([company, code]) => {
    url.value = '';
    thumbnailUrl(company, code)
      .then(value => {
        url.value = value;
      })
      .catch(() => {});
  },
  { immediate: true }
);
</script>

<template>
  <button
    type="button"
    class="relative !p-0 overflow-hidden rounded-lg shrink-0 group bg-n-alpha-2 outline outline-2 -outline-offset-2 outline-n-teal-9 hover:outline-n-teal-10"
    :class="size"
    :title="t('OUTSIDER_ERP.PRODUCTS.PHOTOS.BUTTON_COUNT', { count })"
    :aria-label="t('OUTSIDER_ERP.PRODUCTS.PHOTOS.BUTTON_COUNT', { count })"
    @click.stop="emit('open')"
  >
    <img
      v-if="url"
      :src="url"
      alt=""
      class="absolute inset-0 object-cover w-full h-full max-w-none transition-transform group-hover:scale-110"
    />
    <Icon
      v-else
      icon="i-lucide-images"
      class="absolute inset-0 m-auto size-5 text-n-teal-11"
    />
    <span
      class="absolute inset-0 items-center justify-center hidden group-hover:flex bg-n-slate-12/40"
    >
      <Icon icon="i-lucide-zoom-in" class="size-5 text-n-slate-1" />
    </span>
    <span
      class="absolute bottom-0 right-0 flex items-center gap-0.5 px-1 text-[10px] font-semibold leading-4 text-white rounded-tl-md bg-n-teal-9"
    >
      <Icon icon="i-lucide-camera" class="size-2.5" />
      {{ count }}
    </span>
  </button>
</template>
