<script setup>
// OUTSIDER: lista "Equipamento" de um item (ex.: Motor Xinchai C490 Diesel). Colar várias linhas na
// caixa de baixo adiciona um item por linha, já sem os marcadores (•, -, *) copiados de PDF.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  FEATURE_MAX_LENGTH,
  MAX_FEATURES,
  moveItem,
  newRowId,
} from './catalog';

const features = defineModel({ type: Array, required: true });

const { t } = useI18n();

const newText = ref('');

const addFromText = () => {
  const lines = newText.value
    .split(/\r?\n/)
    .map(line =>
      line
        .replace(/^[\s•·*–-]+/, '')
        .trim()
        .slice(0, FEATURE_MAX_LENGTH)
    )
    .filter(Boolean)
    .slice(0, MAX_FEATURES - features.value.length);
  if (!lines.length) return;
  features.value = [
    ...features.value,
    ...lines.map(text => ({ uid: newRowId(), text })),
  ];
  newText.value = '';
};

const move = (index, step) => {
  features.value = moveItem(features.value, index, step);
};

const remove = index => {
  features.value = features.value.filter((_, position) => position !== index);
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('OUTSIDER_CRM.CATALOG.FEATURES.TITLE') }}
    </span>
    <p v-if="!features.length" class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_CRM.CATALOG.FEATURES.EMPTY') }}
    </p>
    <div
      v-for="(feature, index) in features"
      :key="feature.uid"
      class="flex items-center gap-2 p-2 rounded-lg bg-n-alpha-1"
    >
      <Input
        v-model="feature.text"
        class="flex-1"
        :maxlength="FEATURE_MAX_LENGTH"
      />
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
          :disabled="index === features.length - 1"
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
    <div v-if="features.length < MAX_FEATURES" class="flex items-start gap-2">
      <textarea
        v-model="newText"
        rows="2"
        class="flex-1 !mb-0 rounded-lg text-sm"
        :placeholder="t('OUTSIDER_CRM.CATALOG.FEATURES.ADD_PLACEHOLDER')"
        @keydown.enter.exact.prevent="addFromText"
      />
      <Button
        type="button"
        icon="i-lucide-plus"
        size="sm"
        variant="faded"
        color="slate"
        :label="t('OUTSIDER_CRM.CATALOG.FEATURES.ADD')"
        :disabled="!newText.trim()"
        @click="addFromText"
      />
    </div>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.CATALOG.FEATURES.HELP') }}
    </p>
  </div>
</template>
