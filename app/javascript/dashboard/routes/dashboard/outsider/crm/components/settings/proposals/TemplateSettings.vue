<script setup>
// OUTSIDER: modelos de proposta da conta (Entregas 16 e 17), em cartões com a miniatura da primeira folha,
// como a lista de e-mails da Brevo. "Editar" abre o editor em tela cheia; "Novo modelo" cria em branco
// ou copiando outro e já abre o editor. Modelo que alguma proposta usa não é apagado (o servidor recusa e
// sugere desativar).
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConfirmDelete from '../../ConfirmDelete.vue';
import TemplateStudio from './TemplateStudio.vue';
import TemplateThumb from './TemplateThumb.vue';
import NewTemplateDialog from './NewTemplateDialog.vue';
import { settingsError } from './proposalSettings';

const { t } = useI18n();

const templates = ref([]);
const editingId = ref(null);
const isLoading = ref(true);
const failed = ref(false);
const newDialogRef = ref(null);
const confirmRef = ref(null);

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

const editing = computed(() =>
  templates.value.find(template => template.id === editingId.value)
);

const onCreated = template => {
  templates.value = [...templates.value, template];
  editingId.value = template.id;
};

const askDelete = template => {
  confirmRef.value?.open(
    t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DELETE_TITLE'),
    t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DELETE_TEXT', {
      name: template.name,
    }),
    async () => {
      await CrmAPI.deleteProposalTemplate(template.id);
      templates.value = templates.value.filter(item => item.id !== template.id);
    }
  );
};

const kindLabel = template =>
  t(
    `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.KINDS.${template.kind.toUpperCase()}`
  );

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
    <div class="grid gap-4 grid-cols-[repeat(auto-fill,minmax(16rem,1fr))]">
      <article
        v-for="template in sorted"
        :key="template.id"
        class="flex flex-col overflow-hidden rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
        :data-template-card="template.id"
      >
        <button
          type="button"
          class="flex justify-center pt-4 overflow-hidden bg-n-alpha-1 hover:bg-n-alpha-2"
          :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.EDIT')"
          @click="editingId = template.id"
        >
          <TemplateThumb
            :template="template"
            :width="208"
            class="shadow-md rounded-t-sm"
          />
        </button>
        <div class="flex items-start gap-2 p-3 border-t border-n-weak">
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ template.name }}
            </span>
            <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
              <span
                class="rounded-full size-2"
                :class="template.active ? 'bg-n-teal-9' : 'bg-n-slate-8'"
              />
              {{
                template.active
                  ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.ACTIVE')
                  : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.INACTIVE')
              }}
              {{ ` · ${kindLabel(template)}` }}
            </span>
          </div>
          <Button
            v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DUPLICATE')"
            type="button"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-copy-plus"
            :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DUPLICATE')"
            @click="newDialogRef?.open(template)"
          />
          <Button
            v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DELETE')"
            type="button"
            size="xs"
            variant="ghost"
            color="ruby"
            icon="i-lucide-trash-2"
            :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DELETE')"
            @click="askDelete(template)"
          />
          <Button
            type="button"
            size="xs"
            variant="outline"
            color="slate"
            :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.EDIT')"
            data-template-edit
            @click="editingId = template.id"
          />
        </div>
      </article>
      <button
        type="button"
        class="flex flex-col items-center justify-center gap-2 p-6 text-sm rounded-xl min-h-[14rem] text-n-slate-11 outline outline-1 -outline-offset-1 outline-dashed outline-n-weak hover:text-n-slate-12 hover:bg-n-alpha-1"
        data-new-template-button
        @click="newDialogRef?.open()"
      >
        <span class="i-lucide-plus size-6" />
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.BUTTON') }}
      </button>
    </div>
    <TemplateStudio
      v-if="editing"
      :key="editing.id"
      :template="editing"
      @updated="replace"
      @close="editingId = null"
    />
    <NewTemplateDialog
      ref="newDialogRef"
      :templates="sorted"
      @created="onCreated"
    />
    <ConfirmDelete ref="confirmRef" />
  </section>
</template>
