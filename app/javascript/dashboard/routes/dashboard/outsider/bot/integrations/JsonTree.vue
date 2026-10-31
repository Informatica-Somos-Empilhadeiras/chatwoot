<script setup>
// OUTSIDER: a resposta de um sistema (JSON) em árvore. Clicar num campo devolve o caminho
// (pedido.itens.0.nome), que o bloco API transforma em variável.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  value: { type: [Object, Array, String, Number, Boolean], default: null },
  path: { type: String, default: '' },
  name: { type: String, default: '' },
  depth: { type: Number, default: 0 },
  pickable: { type: Boolean, default: true },
});

const emit = defineEmits(['pick']);

defineOptions({ name: 'JsonTree' });

const { t } = useI18n();

const MAX_ITEMS = 20;
const isObject = computed(
  () => props.value !== null && typeof props.value === 'object'
);
// abre os dois primeiros níveis e o primeiro item das listas ({ data: [{ ... }] } já aparece aberto)
const open = ref(props.depth < 2 || (props.depth < 4 && props.name === '0'));
const entries = computed(() => {
  if (!isObject.value) return [];
  const list = Array.isArray(props.value)
    ? props.value.map((item, index) => [String(index), item])
    : Object.entries(props.value);
  return list.slice(0, MAX_ITEMS);
});
const hidden = computed(() => {
  if (!isObject.value) return 0;
  const size = Array.isArray(props.value)
    ? props.value.length
    : Object.keys(props.value).length;
  return Math.max(size - MAX_ITEMS, 0);
});
const childPath = key => (props.path ? `${props.path}.${key}` : key);
const preview = computed(() => {
  if (props.value === null) return 'null';
  if (Array.isArray(props.value)) {
    return t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.JSON.ITEMS', {
      count: props.value.length,
    });
  }
  if (isObject.value) return '{…}';
  if (typeof props.value === 'string') return `"${props.value}"`;
  return String(props.value);
});
const valueClass = computed(() => {
  if (typeof props.value === 'string') return 'text-n-teal-11';
  if (typeof props.value === 'number') return 'text-n-blue-11';
  if (typeof props.value === 'boolean' || props.value === null) {
    return 'text-n-amber-11';
  }
  return 'text-n-slate-10';
});
const pick = () => {
  if (props.pickable && props.path) emit('pick', props.path, props.value);
};
</script>

<template>
  <div class="font-mono text-xs leading-5">
    <div class="flex items-start gap-1 min-w-0">
      <button
        v-if="isObject"
        type="button"
        class="w-3 shrink-0 text-n-slate-10"
        @click="open = !open"
      >
        {{ open ? '▾' : '▸' }}
      </button>
      <span v-else class="w-3 shrink-0" />
      <button
        v-if="name"
        type="button"
        class="shrink-0 rounded px-0.5 text-n-slate-12"
        :class="pickable ? 'hover:bg-n-brand/10 hover:text-n-brand' : ''"
        :title="
          pickable
            ? t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.JSON.PICK', { path })
            : ''
        "
        @click="pick"
      >
        {{ name }}:
      </button>
      <span
        class="break-all"
        :class="[
          valueClass,
          !isObject && pickable ? 'cursor-pointer hover:underline' : '',
        ]"
        @click="!isObject && pick()"
      >
        {{ isObject && open ? '' : preview }}
      </span>
    </div>
    <div v-if="isObject && open" class="pl-3 border-l border-n-weak ml-1.5">
      <JsonTree
        v-for="[key, item] in entries"
        :key="key"
        :value="item"
        :name="key"
        :path="childPath(key)"
        :depth="depth + 1"
        :pickable="pickable"
        @pick="(...args) => emit('pick', ...args)"
      />
      <span v-if="hidden" class="pl-4 text-n-slate-10">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.JSON.MORE', { count: hidden }) }}
      </span>
      <span v-if="!entries.length" class="pl-4 text-n-slate-10">
        {{ Array.isArray(value) ? '[ ]' : '{ }' }}
      </span>
    </div>
  </div>
</template>
