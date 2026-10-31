<script setup>
// OUTSIDER: lista de pares nome = valor dos blocos do bot (parâmetros, cabeçalhos, campos de formulário).
// O valor aceita {{variáveis}}.
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  keyPlaceholder: { type: String, default: '' },
  valuePlaceholder: { type: String, default: '' },
  max: { type: Number, default: 20 },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const update = (index, field, value) => {
  const list = props.modelValue.map(item => ({ ...item }));
  list[index][field] = value;
  emit('update:modelValue', list);
};
const add = () =>
  emit('update:modelValue', [...props.modelValue, { key: '', value: '' }]);
const remove = index =>
  emit(
    'update:modelValue',
    props.modelValue.filter((_, position) => position !== index)
  );
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <div
      v-for="(item, index) in modelValue"
      :key="index"
      class="flex items-center gap-1"
    >
      <input
        type="text"
        :value="item.key"
        maxlength="100"
        spellcheck="false"
        class="!w-[38%] min-w-0 !mb-0 !h-8 font-mono !text-xs"
        :placeholder="keyPlaceholder"
        @input="update(index, 'key', $event.target.value)"
      />
      <input
        type="text"
        :value="item.value"
        maxlength="2000"
        spellcheck="false"
        class="flex-1 min-w-0 !mb-0 !h-8 font-mono !text-xs"
        :placeholder="valuePlaceholder"
        @input="update(index, 'value', $event.target.value)"
      />
      <Button
        icon="i-lucide-x"
        xs
        ghost
        slate
        type="button"
        @click="remove(index)"
      />
    </div>
    <Button
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.FIELD.ADD_ROW')"
      icon="i-lucide-plus"
      xs
      faded
      slate
      class="self-start"
      type="button"
      :disabled="modelValue.length >= max"
      @click="add"
    />
  </div>
</template>
