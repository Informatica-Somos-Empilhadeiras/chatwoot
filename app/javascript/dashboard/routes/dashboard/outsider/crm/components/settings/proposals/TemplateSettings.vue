<script setup>
// OUTSIDER: modelos de proposta da conta (Venda e Locação padrão). Cada modelo guarda os textos, as
// condições e o papel timbrado que a proposta nova recebe. O editor de posição do papel timbrado fica
// para uma próxima entrega.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TemplateEditor from './TemplateEditor.vue';
import { settingsError } from './proposalSettings';

const { t } = useI18n();

const templates = ref([]);
const activeId = ref(null);
const isLoading = ref(true);
const failed = ref(false);
const dirtyIds = ref([]);

const sorted = computed(() =>
  [...templates.value].sort(
    (a, b) => (a.position ?? 0) - (b.position ?? 0) || a.id - b.id
  )
);

const load = async () => {
  isLoading.value = true;
  failed.value = false;
  try {
    const { data } = await CrmAPI.getProposalTemplates();
    templates.value = data;
    if (!data.some(template => template.id === activeId.value)) {
      activeId.value = sorted.value[0]?.id ?? null;
    }
  } catch (error) {
    failed.value = true;
    useAlert(settingsError(t, error));
  } finally {
    isLoading.value = false;
  }
};

const replace = template => {
  templates.value = templates.value.map(item =>
    item.id === template.id ? template : item
  );
};

const setDirty = (id, dirty) => {
  dirtyIds.value = dirty
    ? [...new Set([...dirtyIds.value, id])]
    : dirtyIds.value.filter(item => item !== id);
};

onMounted(load);
</script>

<template>
  <div v-if="isLoading" class="flex justify-center p-8">
    <Spinner class="text-n-slate-10" />
  </div>
  <div
    v-else-if="failed"
    class="flex flex-col items-center gap-3 p-8 text-sm text-n-slate-11"
  >
    {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LOAD_FAILED') }}
    <Button
      size="sm"
      variant="faded"
      icon="i-lucide-refresh-cw"
      :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.RETRY')"
      @click="load"
    />
  </div>
  <p
    v-else-if="!templates.length"
    class="p-8 mb-0 text-sm text-center text-n-slate-11"
  >
    {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.EMPTY') }}
  </p>
  <section v-else class="flex flex-col gap-4">
    <p class="mb-0 text-sm text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DESCRIPTION') }}
    </p>
    <div class="flex flex-wrap gap-2">
      <button
        v-for="template in sorted"
        :key="template.id"
        type="button"
        class="flex flex-col items-start gap-0.5 px-3 py-2 text-left rounded-xl outline outline-1 -outline-offset-1 min-w-[10rem]"
        :class="
          activeId === template.id
            ? 'outline-n-brand bg-n-alpha-2'
            : 'outline-n-container bg-n-solid-2 hover:bg-n-alpha-1'
        "
        @click="activeId = template.id"
      >
        <span
          class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
        >
          {{ template.name }}
          <span
            v-if="dirtyIds.includes(template.id)"
            v-tooltip.top="
              t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.UNSAVED')
            "
            class="rounded-full size-2 bg-n-amber-9"
          />
        </span>
        <span class="text-xs text-n-slate-11">
          {{
            t(
              `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.KINDS.${template.kind.toUpperCase()}`
            )
          }}
          <template v-if="!template.active">
            · {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.INACTIVE') }}
          </template>
        </span>
      </button>
    </div>
    <!-- v-show mantém o que foi digitado ao trocar de modelo -->
    <TemplateEditor
      v-for="template in sorted"
      v-show="template.id === activeId"
      :key="template.id"
      :template="template"
      @updated="replace"
      @dirty="dirty => setDirty(template.id, dirty)"
    />
  </section>
</template>
