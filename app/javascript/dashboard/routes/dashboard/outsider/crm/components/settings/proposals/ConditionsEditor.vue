<script setup>
// OUTSIDER: condições padrão do modelo (nome e texto), que a proposta nova recebe e pode editar.
// Linhas sem nome e sem texto são descartadas pelo servidor.
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  MAX_CONDITIONS,
  MAX_LABEL,
  MAX_TEXT,
  conditionRow,
} from './proposalSettings';

const rows = defineModel({ type: Array, required: true });

const { t } = useI18n();

const add = () => {
  if (rows.value.length < MAX_CONDITIONS) {
    rows.value = [...rows.value, conditionRow()];
  }
};

const remove = index => {
  rows.value = rows.value.filter((_, position) => position !== index);
};

const move = (index, step) => {
  const target = index + step;
  if (target < 0 || target >= rows.value.length) return;
  const list = [...rows.value];
  [list[index], list[target]] = [list[target], list[index]];
  rows.value = list;
};

const change = (index, key, value) => {
  rows.value = rows.value.map((row, position) =>
    position === index ? { ...row, [key]: value } : row
  );
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <p
      v-if="!rows.length"
      class="p-4 mb-0 text-sm text-center rounded-xl bg-n-solid-2 text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-container"
    >
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.EMPTY') }}
    </p>
    <div
      v-else
      class="overflow-hidden rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
    >
      <div
        v-for="(row, index) in rows"
        :key="row.uid"
        data-fields
        class="flex flex-col gap-2 px-4 py-3 border-b sm:flex-row border-n-weak last:border-0"
      >
        <div class="flex items-start gap-2 sm:w-56 shrink-0">
          <span
            class="w-5 pt-2.5 text-xs text-right tabular-nums text-n-slate-10"
          >
            {{ index + 1 }}
          </span>
          <Input
            :model-value="row.label"
            :maxlength="MAX_LABEL"
            class="flex-1"
            :placeholder="
              t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.LABEL')
            "
            @update:model-value="value => change(index, 'label', value)"
          />
        </div>
        <textarea
          :value="row.text"
          rows="2"
          :maxlength="MAX_TEXT"
          class="flex-1 !mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand placeholder:text-n-slate-10"
          :placeholder="
            t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.TEXT')
          "
          @input="change(index, 'text', $event.target.value)"
        />
        <div class="flex items-start gap-0.5 shrink-0 sm:flex-col">
          <Button
            v-tooltip.left="
              t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.UP')
            "
            type="button"
            icon="i-lucide-arrow-up"
            size="xs"
            variant="ghost"
            color="slate"
            :disabled="index === 0"
            @click="move(index, -1)"
          />
          <Button
            v-tooltip.left="
              t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.DOWN')
            "
            type="button"
            icon="i-lucide-arrow-down"
            size="xs"
            variant="ghost"
            color="slate"
            :disabled="index === rows.length - 1"
            @click="move(index, 1)"
          />
          <Button
            v-tooltip.left="
              t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.REMOVE')
            "
            type="button"
            icon="i-lucide-trash-2"
            size="xs"
            variant="ghost"
            color="ruby"
            @click="remove(index)"
          />
        </div>
      </div>
    </div>
    <div class="flex items-center justify-between gap-2">
      <Button
        type="button"
        icon="i-lucide-plus"
        size="xs"
        variant="ghost"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.ADD')"
        :disabled="rows.length >= MAX_CONDITIONS"
        @click="add"
      />
      <span class="text-xs text-n-slate-10">
        {{
          t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.CONDITIONS.COUNT', {
            count: rows.length,
            max: MAX_CONDITIONS,
          })
        }}
      </span>
    </div>
  </div>
</template>
