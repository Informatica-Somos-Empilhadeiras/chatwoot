<script setup>
// OUTSIDER: painel do bloco Decisão: olha um valor (resposta de API, linha de planilha, resposta do cliente)
// e segue pela primeira regra que bater; nenhuma, segue por Senão.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import TemplateField from './TemplateField.vue';
import BlockTester from './BlockTester.vue';
import {
  DECISION_OPERATORS,
  NO_VALUE_OPERATORS,
  ruleId,
} from './integrationTypes';

const props = defineProps({
  node: { type: Object, required: true },
});

const { t } = useI18n();
const data = computed(() => props.node.data);
const MAX_RULES = 10;

const addRule = () => {
  data.value.rules.push({
    id: ruleId(),
    label: '',
    operator: 'equals',
    value: '',
  });
};
const move = (index, offset) => {
  const list = data.value.rules;
  const target = index + offset;
  if (target < 0 || target >= list.length) return;
  const [item] = list.splice(index, 1);
  list.splice(target, 0, item);
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <TemplateField
      v-model="data.subject"
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DECISION.SUBJECT')"
      placeholder="{{status_pedido}}"
      :hint="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DECISION.SUBJECT_HINT')"
      :maxlength="500"
    />
    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DECISION.RULES') }}
      </span>
      <span class="text-xs text-n-slate-11">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DECISION.RULES_HINT') }}
      </span>
      <div
        v-for="(rule, index) in data.rules"
        :key="rule.id"
        class="flex flex-col gap-1.5 p-2 border rounded-lg border-n-weak"
      >
        <div class="flex items-center gap-1">
          <span class="w-5 text-xs text-center text-n-slate-10">{{
            index + 1
          }}</span>
          <select
            v-model="rule.operator"
            class="flex-1 min-w-0 !mb-0 !h-8 !py-0 !text-xs"
          >
            <option
              v-for="operator in DECISION_OPERATORS"
              :key="operator"
              :value="operator"
            >
              {{ t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.OPERATORS.${operator}`) }}
            </option>
          </select>
          <Button
            icon="i-lucide-arrow-up"
            xs
            ghost
            slate
            :disabled="index === 0"
            @click="move(index, -1)"
          />
          <Button
            icon="i-lucide-arrow-down"
            xs
            ghost
            slate
            :disabled="index === data.rules.length - 1"
            @click="move(index, 1)"
          />
          <Button
            icon="i-lucide-trash-2"
            xs
            ghost
            ruby
            @click="data.rules.splice(index, 1)"
          />
        </div>
        <input
          v-if="!NO_VALUE_OPERATORS.includes(rule.operator)"
          v-model="rule.value"
          type="text"
          maxlength="500"
          class="!mb-0 !h-8 !w-[calc(100%_-_1.5rem)] !text-xs ltr:!ml-6 rtl:!mr-6"
          :placeholder="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DECISION.VALUE')"
        />
        <input
          v-model="rule.label"
          type="text"
          maxlength="40"
          class="!mb-0 !h-8 !w-[calc(100%_-_1.5rem)] !text-xs ltr:!ml-6 rtl:!mr-6"
          :placeholder="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DECISION.LABEL')"
        />
      </div>
      <Button
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DECISION.ADD_RULE')"
        icon="i-lucide-plus"
        xs
        faded
        class="self-start"
        :disabled="data.rules.length >= MAX_RULES"
        @click="addRule"
      />
      <span class="text-xs text-n-slate-10">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DECISION.OTHERWISE_HINT') }}
      </span>
    </div>
    <BlockTester :node="node" />
  </div>
</template>
