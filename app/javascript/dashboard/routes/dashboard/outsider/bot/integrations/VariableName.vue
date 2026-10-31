<script setup>
// OUTSIDER: nome da variável onde o bloco guarda o resultado (mesma limpeza do servidor ao sair do campo).
import { useI18n } from 'vue-i18n';
import { variableName } from './template';

const props = defineProps({
  modelValue: { type: String, default: '' },
  fallback: { type: String, required: true },
  label: { type: String, default: '' },
  hint: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
// as chaves em volta do campo (o template do Vue não aceita "}}" dentro de {{ }})
const OPEN = '{{';
const CLOSE = '}}';

const tidy = () =>
  emit('update:modelValue', variableName(props.modelValue, props.fallback));
</script>

<template>
  <label class="flex flex-col gap-1">
    <span class="text-sm font-medium text-n-slate-12">
      {{ label || t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.VARIABLE') }}
    </span>
    <div class="flex items-center">
      <span class="px-2 font-mono text-xs text-n-slate-10">{{ OPEN }}</span>
      <input
        type="text"
        :value="modelValue"
        maxlength="30"
        spellcheck="false"
        class="flex-1 min-w-0 !mb-0 !h-8 font-mono !text-xs"
        @input="emit('update:modelValue', $event.target.value)"
        @blur="tidy"
      />
      <span class="px-2 font-mono text-xs text-n-slate-10">{{ CLOSE }}</span>
    </div>
    <span v-if="hint" class="text-xs text-n-slate-10">{{ hint }}</span>
  </label>
</template>
