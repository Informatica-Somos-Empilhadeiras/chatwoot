<script setup>
// OUTSIDER: auditoria do negócio: cada alteração do negócio e das tarefas dele (e notas apagadas),
// com quem fez, quando e o valor antes e depois. Vem da tabela audits do Chatwoot.
import { ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  errorMessage,
  formatDate,
  formatDateTime,
  formatMoney,
} from '../helpers';

const props = defineProps({
  opportunity: { type: Object, required: true },
});

const { t, te } = useI18n();

const audits = ref([]);
const isLoading = ref(false);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getAudits(props.opportunity.id);
    audits.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const title = audit =>
  t(
    `OUTSIDER_CRM.AUDIT.ACTIONS.${audit.subject.toUpperCase()}_${audit.action.toUpperCase()}`,
    {
      name: audit.user?.name || t('OUTSIDER_CRM.TIMELINE.SYSTEM'),
      label: audit.subject_label || '',
    }
  );

const fieldLabel = change => {
  if (change.label) return change.label;
  const key = `OUTSIDER_CRM.AUDIT.FIELDS.${change.field.toUpperCase()}`;
  return te(key) ? t(key) : change.field;
};

const format = (audit, change, value) => {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'boolean') {
    return value ? t('OUTSIDER_CRM.AUDIT.YES') : t('OUTSIDER_CRM.AUDIT.NO');
  }
  switch (change.field) {
    case 'value_cents':
      return formatMoney(value);
    case 'expected_close_on':
      return formatDate(value);
    case 'due_at':
    case 'completed_at':
      return formatDateTime(value, t);
    case 'probability':
      return `${value}%`;
    case 'status':
      return t(`OUTSIDER_CRM.STATUS.${String(value).toUpperCase()}`);
    case 'kind':
      return audit.subject === 'task'
        ? t(`OUTSIDER_CRM.TASKS.KINDS.${String(value).toUpperCase()}`)
        : value;
    default:
      return Array.isArray(value) ? value.join(', ') : String(value);
  }
};

watch(() => props.opportunity.id, load);
onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-3">
    <p class="flex items-center gap-1.5 mb-0 text-xs text-n-slate-11">
      <Icon icon="i-lucide-shield-check" class="size-3.5" />
      {{ t('OUTSIDER_CRM.AUDIT.HINT') }}
    </p>
    <div v-if="isLoading" class="flex justify-center p-4 text-n-slate-10">
      <Spinner :size="18" />
    </div>
    <p
      v-else-if="!audits.length"
      class="px-3 py-4 mb-0 text-sm text-center rounded-lg text-n-slate-11 bg-n-alpha-1"
    >
      {{ t('OUTSIDER_CRM.AUDIT.EMPTY') }}
    </p>
    <ul
      v-else
      class="flex flex-col mb-0 list-none divide-y rounded-lg divide-n-weak outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <li
        v-for="audit in audits"
        :key="audit.id"
        class="flex flex-col gap-1.5 px-3 py-2.5"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-x-3">
          <span class="text-sm text-n-slate-12">{{ title(audit) }}</span>
          <span class="text-xs text-n-slate-10">
            {{ formatDateTime(audit.created_at, t) }}
          </span>
        </div>
        <dl
          v-if="audit.changes.length"
          class="grid grid-cols-[minmax(6rem,auto)_1fr] gap-x-3 gap-y-0.5 mb-0 text-xs"
        >
          <template
            v-for="(change, index) in audit.changes"
            :key="`${audit.id}-${index}`"
          >
            <dt class="text-n-slate-11">{{ fieldLabel(change) }}</dt>
            <dd class="mb-0 break-words text-n-slate-12">
              <template v-if="audit.action === 'update'">
                <span class="line-through text-n-slate-10">
                  {{ format(audit, change, change.from) }}
                </span>
                →
              </template>
              {{ format(audit, change, change.to) }}
            </dd>
          </template>
        </dl>
      </li>
    </ul>
  </div>
</template>
