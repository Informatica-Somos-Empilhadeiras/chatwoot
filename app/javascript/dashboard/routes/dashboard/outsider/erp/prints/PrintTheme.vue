<script setup>
// OUTSIDER: aba Identidade do estúdio: as cores do modelo (usadas por todos os blocos: títulos, faixas, cabeçalho das
// tabelas, zebra, caixas e linhas), as fontes dos títulos e do texto (as do próprio PDF), o tamanho base, as margens e a
// numeração das páginas. As paletas prontas trocam todas as cores de uma vez.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { FONT_CSS, THEME_COLORS } from './printsHelpers';

const theme = defineModel('theme', { type: Object, required: true });

const { t } = useI18n();

const PALETTES = {
  somos: {
    primary: '#00663B',
    accent: '#90EB54',
    text: '#1D2733',
    muted: '#6B7686',
    row: '#F3F7F4',
    box: '#EEF6F1',
    line: '#D6DEE3',
  },
  azul: {
    primary: '#1F4E8C',
    accent: '#F2A900',
    text: '#1C2430',
    muted: '#66707F',
    row: '#F2F5FA',
    box: '#EBF1F9',
    line: '#D5DCE6',
  },
  grafite: {
    primary: '#2E3440',
    accent: '#E0592A',
    text: '#22262E',
    muted: '#6C7380',
    row: '#F4F5F7',
    box: '#EEF0F3',
    line: '#D9DDE3',
  },
  vinho: {
    primary: '#7A1F2B',
    accent: '#C9A227',
    text: '#2A1E20',
    muted: '#7A6C6E',
    row: '#F8F3F3',
    box: '#F5ECEC',
    line: '#E2D6D7',
  },
};

const HEX = /^#[0-9a-fA-F]{6}$/;

const set = (key, value) => {
  theme.value = { ...theme.value, [key]: value };
};

const setColor = (name, value) => {
  if (!HEX.test(value)) return;
  set('colors', { ...theme.value.colors, [name]: value.toUpperCase() });
};

const applyPalette = key => set('colors', { ...PALETTES[key] });

const activePalette = computed(() =>
  Object.keys(PALETTES).find(key =>
    THEME_COLORS.every(
      name =>
        (theme.value.colors?.[name] || '').toUpperCase() ===
        PALETTES[key][name].toUpperCase()
    )
  )
);

const FONTS = ['helvetica', 'times', 'courier'];
const SELECT =
  'w-full !mb-0 pl-2.5 !pr-8 py-1.5 text-sm rounded-lg bg-n-alpha-black2 bg-[right_-1.25rem_center] outline outline-1 outline-n-weak focus:outline-n-brand text-n-slate-12';
</script>

<template>
  <div class="flex flex-col gap-5">
    <section class="flex flex-col gap-2">
      <h4
        class="mb-0 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_ERP.PRINTS.THEME.PALETTES') }}
      </h4>
      <div class="grid grid-cols-2 gap-2">
        <button
          v-for="(palette, key) in PALETTES"
          :key="key"
          type="button"
          class="flex flex-col gap-1.5 p-2 text-left rounded-lg outline outline-1 -outline-offset-1"
          :class="
            activePalette === key
              ? 'outline-2 outline-n-brand'
              : 'outline-n-weak hover:outline-n-slate-7'
          "
          @click="applyPalette(key)"
        >
          <span class="flex h-4 overflow-hidden rounded">
            <span
              v-for="name in ['primary', 'accent', 'box', 'line']"
              :key="name"
              class="flex-1"
              :style="{ background: palette[name] }"
            />
          </span>
          <span class="text-xs text-n-slate-12">
            {{ t(`OUTSIDER_ERP.PRINTS.THEME.PALETTE.${key.toUpperCase()}`) }}
          </span>
        </button>
      </div>
    </section>

    <section class="flex flex-col gap-2">
      <h4
        class="mb-0 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_ERP.PRINTS.THEME.COLORS') }}
      </h4>
      <div
        v-for="name in THEME_COLORS"
        :key="name"
        class="flex items-center gap-2"
      >
        <input
          type="color"
          class="w-8 h-8 p-0 bg-transparent border-0 rounded cursor-pointer shrink-0"
          :value="theme.colors?.[name]"
          @input="setColor(name, $event.target.value)"
        />
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-sm text-n-slate-12">
            {{ t(`OUTSIDER_ERP.PRINTS.THEME.COLOR.${name.toUpperCase()}`) }}
          </span>
          <span class="text-[11px] text-n-slate-10 truncate">
            {{ t(`OUTSIDER_ERP.PRINTS.THEME.COLOR_USE.${name.toUpperCase()}`) }}
          </span>
        </div>
        <input
          type="text"
          class="reset-base w-20 px-1.5 py-1 font-mono text-xs uppercase rounded bg-n-alpha-black2 outline outline-1 outline-n-weak text-n-slate-12"
          :value="theme.colors?.[name]"
          maxlength="7"
          @change="setColor(name, $event.target.value)"
        />
      </div>
    </section>

    <section class="flex flex-col gap-3">
      <h4
        class="mb-0 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_ERP.PRINTS.THEME.TYPOGRAPHY') }}
      </h4>
      <label
        v-for="key in ['heading_font', 'body_font']"
        :key="key"
        class="flex flex-col gap-1 mb-0"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t(`OUTSIDER_ERP.PRINTS.THEME.${key.toUpperCase()}`) }}
        </span>
        <select
          :class="SELECT"
          :value="theme[key]"
          :style="{ fontFamily: FONT_CSS[theme[key]] }"
          @change="set(key, $event.target.value)"
        >
          <option
            v-for="font in FONTS"
            :key="font"
            :value="font"
            :style="{ fontFamily: FONT_CSS[font] }"
          >
            {{ t(`OUTSIDER_ERP.PRINTS.THEME.FONT.${font.toUpperCase()}`) }}
          </option>
        </select>
      </label>
      <div class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_ERP.PRINTS.THEME.SIZE') }}
        </span>
        <div class="flex items-center gap-2">
          <input
            type="range"
            min="7"
            max="13"
            class="flex-1 accent-[#00663B]"
            :value="theme.size"
            @input="set('size', Number($event.target.value))"
          />
          <span class="w-10 text-xs text-right tabular-nums text-n-slate-11">
            {{
              t('OUTSIDER_ERP.PRINTS.THEME.SIZE_VALUE', { size: theme.size })
            }}
          </span>
        </div>
      </div>
    </section>

    <section class="flex flex-col gap-3">
      <h4
        class="mb-0 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_ERP.PRINTS.THEME.PAGE') }}
      </h4>
      <div class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_ERP.PRINTS.THEME.MARGIN') }}
        </span>
        <div class="flex p-0.5 rounded-lg bg-n-alpha-2">
          <button
            v-for="margin in ['s', 'm', 'l']"
            :key="margin"
            type="button"
            class="flex-1 h-7 text-xs rounded-md"
            :class="
              theme.margin === margin
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="set('margin', margin)"
          >
            {{ t(`OUTSIDER_ERP.PRINTS.THEME.MARGINS.${margin.toUpperCase()}`) }}
          </button>
        </div>
      </div>
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm text-n-slate-12">
          {{ t('OUTSIDER_ERP.PRINTS.THEME.PAGE_NUMBERS') }}
        </span>
        <Switch
          :model-value="theme.page_numbers"
          @update:model-value="value => set('page_numbers', value)"
        />
      </div>
    </section>
  </div>
</template>
