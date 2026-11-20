<script setup>
// OUTSIDER: rodapé da tabela da seção ERP: "1–50 de 4.253", páginas (com reticências) e quantos por página.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  total: { type: Number, default: 0 },
  options: { type: Array, default: () => [25, 50, 100] },
});

const page = defineModel('page', { type: Number, default: 1 });
const per = defineModel('per', { type: Number, default: 50 });

const { t } = useI18n();
const pages = computed(() => Math.max(1, Math.ceil(props.total / per.value)));
const first = computed(() =>
  props.total ? (page.value - 1) * per.value + 1 : 0
);
const last = computed(() => Math.min(props.total, page.value * per.value));
const number = value => Number(value).toLocaleString('pt-BR');

// 1 … 4 5 6 … 86
const buttons = computed(() => {
  const total = pages.value;
  const current = page.value;
  const wanted = new Set([1, total, current - 1, current, current + 1]);
  const list = [...wanted].filter(item => item >= 1 && item <= total).sort((a, b) => a - b);
  return list.flatMap((item, index) =>
    index && item - list[index - 1] > 1 ? [`gap-${item}`, item] : [item]
  );
});

const go = value => {
  page.value = Math.min(Math.max(1, value), pages.value);
};

const setPer = value => {
  per.value = Number(value);
  page.value = 1;
};
</script>

<template>
  <div
    class="flex flex-wrap items-center justify-between gap-2 px-5 py-2.5 text-xs border-t border-n-weak text-n-slate-11"
  >
    <span class="tabular-nums">
      {{
        t('OUTSIDER_ERP.RECORDS.RANGE', {
          first: number(first),
          last: number(last),
          total: number(total),
        })
      }}
    </span>
    <div class="flex items-center gap-1">
      <button
        type="button"
        class="grid rounded-md size-7 place-content-center hover:bg-n-alpha-2 disabled:opacity-40"
        :disabled="page <= 1"
        :aria-label="t('OUTSIDER_ERP.LIST.PREV')"
        @click="go(page - 1)"
      >
        <Icon icon="i-lucide-chevron-left" class="size-4" />
      </button>
      <template v-for="item in buttons" :key="item">
        <span v-if="typeof item === 'string'" class="px-1 text-n-slate-9">…</span>
        <button
          v-else
          type="button"
          class="h-7 px-2 rounded-md min-w-7 tabular-nums"
          :class="
            item === page
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium outline outline-1 -outline-offset-1 outline-n-weak'
              : 'hover:bg-n-alpha-1'
          "
          @click="go(item)"
        >
          {{ number(item) }}
        </button>
      </template>
      <button
        type="button"
        class="grid rounded-md size-7 place-content-center hover:bg-n-alpha-2 disabled:opacity-40"
        :disabled="page >= pages"
        :aria-label="t('OUTSIDER_ERP.LIST.NEXT')"
        @click="go(page + 1)"
      >
        <Icon icon="i-lucide-chevron-right" class="size-4" />
      </button>
    </div>
    <label class="flex items-center gap-2">
      <select
        :value="per"
        class="!mb-0 !w-auto h-7 pl-2 !pr-7 py-0 text-xs rounded-md reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6"
        @change="setPer($event.target.value)"
      >
        <option v-for="value in options" :key="value" :value="value">
          {{ value }}
        </option>
      </select>
      {{ t('OUTSIDER_ERP.RECORDS.PER_PAGE') }}
    </label>
  </div>
</template>
