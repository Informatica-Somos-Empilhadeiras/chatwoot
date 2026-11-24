<script setup>
// OUTSIDER: comissão (% sobre o valor faturado) e meta do mês de cada técnico, só para o administrador
// (Outsider::Erp::Settings::Reports). A meta vale pelo nome do técnico; vazia tira a meta dele. Também os tipos de
// atendimento da OS que não somam para o técnico (garantia, entrega técnica, frotas).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ReportsAPI from 'dashboard/api/outsider/reports';
import Button from 'dashboard/components-next/button/Button.vue';
import { erpErrorMessage } from '../../erp/erpStore';
import { formatNumber, parseNumber } from '../../erp/budgets/budgetHelpers';

const emit = defineEmits(['saved']);

const { t } = useI18n();
const label = key => t(`OUTSIDER_REPORTS.TECHNICIANS.CONFIG.${key}`);
const isOpen = ref(false);
const saving = ref(false);
const commission = ref('');
const goals = ref([]);
const excluded = ref([]);
const newExcluded = ref('');

const normalizeType = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toUpperCase()
    .slice(0, 80);

const addExcluded = () => {
  const type = normalizeType(newExcluded.value);
  newExcluded.value = '';
  if (type && !excluded.value.includes(type))
    excluded.value = [...excluded.value, type];
};
const removeExcluded = type => {
  excluded.value = excluded.value.filter(item => item !== type);
};

// data: o relatório aberto (técnicos do período + todas as metas já gravadas, para não perder as de quem não aparece)
const open = data => {
  commission.value = formatNumber(data.comissao_pct);
  excluded.value = [...(data.tipos_fora_da_soma || [])];
  newExcluded.value = '';
  const saved = data.metas || {};
  const names = [
    ...new Set([
      ...(data.tecnicos || []).map(row => row.tecnico),
      ...Object.keys(saved),
    ]),
  ];
  goals.value = names.map(name => ({
    name,
    value: saved[name] ? formatNumber(saved[name]) : '',
  }));
  isOpen.value = true;
};

const save = async () => {
  saving.value = true;
  try {
    await ReportsAPI.saveTechniciansSettings({
      report_commission_pct: parseNumber(commission.value, 0),
      report_goals: Object.fromEntries(
        goals.value.map(goal => [goal.name, parseNumber(goal.value, 0)])
      ),
      report_excluded_types: excluded.value,
    });
    isOpen.value = false;
    emit('saved');
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    saving.value = false;
  }
};

const INPUT =
  '!mb-0 h-9 px-2.5 text-sm text-right rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';

defineExpose({ open });
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[10000] flex items-center justify-center p-4 bg-n-alpha-black1 backdrop-blur-[2px]"
      @click.self="isOpen = false"
      @keydown.esc="isOpen = false"
    >
      <div
        class="flex flex-col w-full max-w-lg max-h-full overflow-hidden shadow-xl rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
      >
        <header class="px-5 py-4 border-b border-n-weak">
          <h2 class="mb-0 text-base font-medium text-n-slate-12">
            {{ label('TITLE') }}
          </h2>
        </header>
        <div class="flex flex-col gap-4 px-5 py-4 overflow-y-auto">
          <label class="flex items-center justify-between gap-3 text-sm">
            <span class="flex flex-col">
              <span class="text-n-slate-12">{{ label('COMMISSION') }}</span>
              <span class="text-xs text-n-slate-10">
                {{ label('COMMISSION_HINT') }}
              </span>
            </span>
            <input
              v-model="commission"
              inputmode="decimal"
              :class="INPUT"
              class="w-24"
            />
          </label>
          <div class="flex flex-col gap-2" data-excluded-types>
            <span class="text-sm text-n-slate-12">{{ label('EXCLUDED') }}</span>
            <span class="text-xs text-n-slate-10">
              {{ label('EXCLUDED_HINT') }}
            </span>
            <div class="flex flex-wrap gap-1.5">
              <span
                v-for="type in excluded"
                :key="type"
                class="flex items-center gap-1 py-1 pl-2 pr-1 text-xs rounded-full bg-n-alpha-2 text-n-slate-12"
              >
                {{ type }}
                <button
                  type="button"
                  class="p-0 rounded-full i-lucide-x size-3.5 text-n-slate-10 hover:text-n-slate-12"
                  @click="removeExcluded(type)"
                />
              </span>
            </div>
            <form class="flex items-center gap-2" @submit.prevent="addExcluded">
              <input
                v-model="newExcluded"
                maxlength="80"
                :class="INPUT"
                class="flex-1 !text-left"
                :placeholder="label('EXCLUDED_PLACEHOLDER')"
              />
              <Button
                type="submit"
                size="sm"
                variant="faded"
                color="slate"
                icon="i-lucide-plus"
                :disabled="!newExcluded.trim()"
                :label="label('EXCLUDED_ADD')"
              />
            </form>
          </div>
          <div class="flex flex-col gap-2">
            <span class="text-sm text-n-slate-12">{{ label('GOALS') }}</span>
            <span class="text-xs text-n-slate-10">{{
              label('GOALS_HINT')
            }}</span>
            <label
              v-for="goal in goals"
              :key="goal.name"
              class="flex items-center justify-between gap-3 text-sm"
            >
              <span class="truncate text-n-slate-11">{{ goal.name }}</span>
              <input
                v-model="goal.value"
                inputmode="decimal"
                :class="INPUT"
                class="w-36"
              />
            </label>
          </div>
        </div>
        <footer class="flex justify-end gap-2 px-5 py-3 border-t border-n-weak">
          <Button
            variant="faded"
            color="slate"
            :label="t('OUTSIDER_ERP.CANCEL')"
            @click="isOpen = false"
          />
          <Button :label="label('SAVE')" :is-loading="saving" @click="save" />
        </footer>
      </div>
    </div>
  </Teleport>
</template>
