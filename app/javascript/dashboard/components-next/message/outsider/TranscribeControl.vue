<script setup>
// OUTSIDER: botão "Transcrever" do player de áudio. Faz a transcrição no navegador (helper/outsider/transcriber),
// mostra o andamento (baixando o modelo na primeira vez, depois transcrevendo) e entrega o texto para quem guarda.
// O menu ⌄ escolhe o modelo: rápido (menor) ou preciso (padrão). Fica lembrado neste navegador.
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import Icon from 'next/icon/Icon.vue';
import {
  MODEL_SIZES,
  canTranscribe,
  jobs,
  savedSize,
  saveSize,
  transcribe,
  clearJob,
} from 'dashboard/helper/outsider/transcriber';

const props = defineProps({
  // chave única do áudio (id do anexo) e o endereço do arquivo
  jobKey: { type: String, required: true },
  url: { type: String, required: true },
  // já tem transcrição: o botão vira "de novo"
  hasText: { type: Boolean, default: false },
});
const emit = defineEmits(['done', 'error']);
const { t } = useI18n();

const supported = canTranscribe();
const menuOpen = ref(false);
const menu = ref(null);
const menuButton = ref(null);
const menuStyle = ref({});
const size = ref(savedSize());
onClickOutside(menu, () => {
  menuOpen.value = false;
});

// o menu vai para o body (a bolha corta o que sai dela), abaixo do botão ou acima se não couber
const toggleMenu = () => {
  if (menuOpen.value) {
    menuOpen.value = false;
    return;
  }
  const rect = menuButton.value?.getBoundingClientRect();
  if (rect) {
    const width = 224;
    const left = Math.max(
      8,
      Math.min(rect.right - width, window.innerWidth - width - 8)
    );
    const below = rect.bottom + 4;
    const fits = below + 190 < window.innerHeight;
    menuStyle.value = fits
      ? { top: `${below}px`, left: `${left}px` }
      : { bottom: `${window.innerHeight - rect.top + 4}px`, left: `${left}px` };
  }
  menuOpen.value = true;
};

const job = computed(() => jobs[props.jobKey] || null);
const busy = computed(() =>
  ['fila', 'lendo', 'baixando', 'carregando', 'transcrevendo'].includes(
    job.value?.status
  )
);
const statusText = computed(() => {
  const current = job.value;
  if (!current) return '';
  if (current.status === 'erro') {
    const known = ['too_long', 'download', 'model', 'worker'];
    const code = known.includes(current.error) ? current.error : 'generic';
    return t(`OUTSIDER_WHATSAPP.TRANSCRIBE.ERRORS.${code.toUpperCase()}`);
  }
  if (!busy.value) return '';
  const label = t(
    `OUTSIDER_WHATSAPP.TRANSCRIBE.STATUS.${current.status.toUpperCase()}`
  );
  return current.status === 'fila'
    ? label
    : `${label} ${current.percent || 0}%`;
});

const start = async () => {
  menuOpen.value = false;
  if (busy.value) return;
  try {
    const result = await transcribe({ key: props.jobKey, url: props.url });
    emit('done', result);
  } catch (error) {
    emit('error', error);
  }
};

const pick = value => {
  size.value = value;
  saveSize(value);
  menuOpen.value = false;
};

onBeforeUnmount(() => {
  if (!busy.value) clearJob(props.jobKey);
});
</script>

<template>
  <div
    v-if="supported"
    class="relative flex items-center gap-1 min-w-0"
    data-transcribe
  >
    <span
      v-if="statusText"
      class="text-[11px] truncate max-w-[150px]"
      :class="job?.status === 'erro' ? 'text-n-ruby-11' : 'text-n-slate-11'"
      :title="statusText"
      data-transcribe-status
    >
      {{ statusText }}
    </span>
    <button
      type="button"
      class="flex items-center gap-1 h-5 px-1.5 rounded-full text-[11px] font-medium hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-60"
      :class="busy ? 'text-n-slate-11' : 'text-n-slate-11'"
      :disabled="busy"
      :title="
        hasText
          ? t('OUTSIDER_WHATSAPP.TRANSCRIBE.AGAIN')
          : t('OUTSIDER_WHATSAPP.TRANSCRIBE.BUTTON')
      "
      data-transcribe-button
      @click="start"
    >
      <Icon
        :icon="busy ? 'i-lucide-loader-circle' : 'i-lucide-captions'"
        class="size-3.5"
        :class="{ 'animate-spin': busy }"
      />
      <span v-if="!hasText && !busy">
        {{ t('OUTSIDER_WHATSAPP.TRANSCRIBE.BUTTON') }}
      </span>
    </button>
    <button
      ref="menuButton"
      type="button"
      class="grid rounded-full size-5 place-content-center text-n-slate-11 hover:text-n-slate-12"
      :title="t('OUTSIDER_WHATSAPP.TRANSCRIBE.MODEL')"
      :disabled="busy"
      data-transcribe-menu
      @click="toggleMenu"
    >
      <Icon icon="i-lucide-chevron-down" class="size-3.5" />
    </button>
    <Teleport to="body">
      <div
        v-if="menuOpen"
        ref="menu"
        class="fixed z-[60] w-56 p-1.5 text-xs rounded-lg shadow-lg bg-n-solid-1 border border-n-weak"
        :style="menuStyle"
        data-transcribe-menu-list
      >
        <p class="px-2 py-1 mb-0 font-semibold text-n-slate-11">
          {{ t('OUTSIDER_WHATSAPP.TRANSCRIBE.MODEL') }}
        </p>
        <button
          v-for="option in MODEL_SIZES"
          :key="option"
          type="button"
          class="flex items-start w-full gap-2 px-2 py-1.5 rounded-md text-start hover:bg-n-alpha-1"
          :data-transcribe-size="option"
          @click="pick(option)"
        >
          <Icon
            :icon="size === option ? 'i-lucide-check' : 'i-lucide-dot'"
            class="size-4 shrink-0 text-n-slate-12"
          />
          <span class="flex flex-col">
            <span class="font-medium text-n-slate-12">
              {{
                t(`OUTSIDER_WHATSAPP.TRANSCRIBE.SIZES.${option.toUpperCase()}`)
              }}
            </span>
            <span class="text-n-slate-11">
              {{
                t(
                  `OUTSIDER_WHATSAPP.TRANSCRIBE.SIZES.${option.toUpperCase()}_HINT`
                )
              }}
            </span>
          </span>
        </button>
        <p class="px-2 pt-1 mb-0 text-[11px] text-n-slate-11">
          {{ t('OUTSIDER_WHATSAPP.TRANSCRIBE.PRIVACY') }}
        </p>
      </div>
    </Teleport>
  </div>
</template>
