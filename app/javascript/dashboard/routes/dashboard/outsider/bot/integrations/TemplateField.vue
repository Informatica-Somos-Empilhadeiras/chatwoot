<script setup>
// OUTSIDER: campo de texto dos blocos do bot que aceita {{variáveis}}: o botão {{ }} lista as variáveis do
// fluxo e do contato e coloca a escolhida onde está o cursor.
import { ref, computed, inject } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { VARIABLES } from '../nodeTypes';
import { braces } from './template';

const props = defineProps({
  modelValue: { type: String, default: '' },
  label: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  hint: { type: String, default: '' },
  multiline: { type: Boolean, default: false },
  mono: { type: Boolean, default: false },
  rows: { type: Number, default: 3 },
  maxlength: { type: Number, default: 20000 },
  error: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue', 'blur']);

// exemplos de filtro (passados ao texto como valor: "|" e "{{" não podem ir na tradução)
const FILTER_EXAMPLES =
  '{{cnpj | digitos}} · {{valor | moeda}} · {{data | data}} · {{nome | padrao:cliente}}';

const { t } = useI18n();
const flowVariables = inject('botFlowVariables', ref([]));
const field = ref(null);
const open = ref(false);

const variables = computed(() => [
  ...new Set([...(flowVariables.value || []), ...VARIABLES]),
]);

const insert = variable => {
  const element = field.value;
  const text = props.modelValue || '';
  const start = element?.selectionStart ?? text.length;
  const end = element?.selectionEnd ?? text.length;
  emit(
    'update:modelValue',
    `${text.slice(0, start)}${variable}${text.slice(end)}`
  );
  open.value = false;
  requestAnimationFrame(() => {
    if (!element) return;
    element.focus();
    const caret = start + variable.length;
    element.setSelectionRange(caret, caret);
  });
};
</script>

<template>
  <div class="flex flex-col gap-1">
    <div class="flex items-center justify-between gap-2">
      <span v-if="label" class="text-sm font-medium text-n-slate-12">
        {{ label }}
      </span>
      <div v-on-click-outside="() => (open = false)" class="relative ml-auto">
        <button
          type="button"
          class="px-1.5 py-0.5 text-[11px] font-mono rounded-md bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12"
          :title="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.INSERT_VARIABLE')"
          @click="open = !open"
        >
          {{ braces(' ') }}
        </button>
        <div
          v-if="open"
          class="absolute right-0 z-50 flex flex-col w-64 gap-0.5 p-1.5 mt-1 overflow-y-auto border shadow-lg max-h-72 rounded-xl top-full bg-n-solid-2 border-n-weak"
        >
          <button
            v-for="variable in variables"
            :key="variable"
            type="button"
            class="px-2 py-1 font-mono text-xs text-left truncate rounded-md hover:bg-n-alpha-1 text-n-slate-12"
            @click="insert(variable)"
          >
            {{ variable }}
          </button>
          <p
            class="px-2 pt-1 mb-0 text-[11px] leading-snug border-t text-n-slate-10 border-n-weak"
          >
            {{
              t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.FILTERS_HINT', {
                examples: FILTER_EXAMPLES,
              })
            }}
          </p>
        </div>
      </div>
    </div>
    <textarea
      v-if="multiline"
      ref="field"
      :value="modelValue"
      :rows="rows"
      :maxlength="maxlength"
      :placeholder="placeholder"
      spellcheck="false"
      class="!mb-0 text-sm resize-y min-h-[4rem]"
      :class="[
        mono ? 'font-mono !text-xs leading-relaxed' : '',
        error ? '!outline-n-ruby-8' : '',
      ]"
      @input="emit('update:modelValue', $event.target.value)"
      @blur="emit('blur')"
    />
    <input
      v-else
      ref="field"
      type="text"
      :value="modelValue"
      :maxlength="maxlength"
      :placeholder="placeholder"
      spellcheck="false"
      class="!mb-0 !h-9 text-sm"
      :class="[
        mono ? 'font-mono !text-xs' : '',
        error ? '!outline-n-ruby-8' : '',
      ]"
      @input="emit('update:modelValue', $event.target.value)"
      @blur="emit('blur')"
    />
    <span v-if="error" class="flex items-start gap-1 text-xs text-n-ruby-11">
      <Icon icon="i-lucide-circle-alert" class="size-3.5 mt-px shrink-0" />
      {{ error }}
    </span>
    <span v-else-if="hint" class="text-xs text-n-slate-10">{{ hint }}</span>
  </div>
</template>
