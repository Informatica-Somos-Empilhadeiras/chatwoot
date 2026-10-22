<script setup>
// OUTSIDER: linhas de "Principais características" de um item (ex.: Capacidade de carga | 3500 kg).
// Linha marcada como negrito sai em destaque no PDF; linha sem nome é descartada ao salvar.
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { MAX_SPECS, SPEC_MAX_LENGTH, moveItem, newRowId } from './catalog';

const specs = defineModel({ type: Array, required: true });

const { t } = useI18n();

const add = () => {
  specs.value = [
    ...specs.value,
    { uid: newRowId(), label: '', value: '', bold: false },
  ];
};

const move = (index, step) => {
  specs.value = moveItem(specs.value, index, step);
};

const remove = index => {
  specs.value = specs.value.filter((_, position) => position !== index);
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex items-center justify-between gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.CATALOG.SPECS.TITLE') }}
      </span>
      <Button
        type="button"
        icon="i-lucide-plus"
        size="xs"
        variant="ghost"
        :label="t('OUTSIDER_CRM.CATALOG.SPECS.ADD')"
        :disabled="specs.length >= MAX_SPECS"
        @click="add"
      />
    </div>
    <p v-if="!specs.length" class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_CRM.CATALOG.SPECS.EMPTY') }}
    </p>
    <div
      v-for="(spec, index) in specs"
      :key="spec.uid"
      class="flex flex-wrap items-center gap-2 p-2 rounded-lg bg-n-alpha-1"
    >
      <Input
        v-model="spec.label"
        class="flex-1 min-w-[9rem]"
        :maxlength="SPEC_MAX_LENGTH"
        :custom-input-class="{ 'font-semibold': spec.bold }"
        :placeholder="t('OUTSIDER_CRM.CATALOG.SPECS.LABEL_PLACEHOLDER')"
      />
      <Input
        v-model="spec.value"
        class="flex-1 min-w-[7rem]"
        :maxlength="SPEC_MAX_LENGTH"
        :custom-input-class="{ 'font-semibold': spec.bold }"
        :placeholder="t('OUTSIDER_CRM.CATALOG.SPECS.VALUE_PLACEHOLDER')"
      />
      <label
        v-tooltip.top="t('OUTSIDER_CRM.CATALOG.SPECS.BOLD_HELP')"
        class="flex items-center gap-1.5 text-xs cursor-pointer text-n-slate-11"
      >
        <Checkbox v-model="spec.bold" />
        {{ t('OUTSIDER_CRM.CATALOG.SPECS.BOLD') }}
      </label>
      <div class="flex items-center">
        <Button
          v-tooltip.top="t('OUTSIDER_CRM.CATALOG.MOVE_UP')"
          type="button"
          icon="i-lucide-arrow-up"
          size="xs"
          variant="ghost"
          color="slate"
          :disabled="index === 0"
          @click="move(index, -1)"
        />
        <Button
          v-tooltip.top="t('OUTSIDER_CRM.CATALOG.MOVE_DOWN')"
          type="button"
          icon="i-lucide-arrow-down"
          size="xs"
          variant="ghost"
          color="slate"
          :disabled="index === specs.length - 1"
          @click="move(index, 1)"
        />
        <Button
          v-tooltip.top="t('OUTSIDER_CRM.CATALOG.REMOVE')"
          type="button"
          icon="i-lucide-trash-2"
          size="xs"
          variant="ghost"
          color="ruby"
          @click="remove(index)"
        />
      </div>
    </div>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.CATALOG.SPECS.HELP') }}
    </p>
  </div>
</template>
