<script setup>
// OUTSIDER: editor de "Nota interna CRM" no lugar da caixa de resposta. A nota vai para a linha
// do tempo do negócio escolhido: não vira mensagem do Chatwoot e o cliente nunca vê. Continua
// neste modo até a pessoa voltar para a resposta (assim ninguém manda ao cliente achando que é nota).
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { bumpActivity, crmState, summaryKey } from '../crmStore';
import { errorMessage, isHandedOff } from '../helpers';

const props = defineProps({
  chat: { type: Object, required: true },
});

const { t } = useI18n();

const textarea = ref(null);
const body = ref('');
const isSaving = ref(false);
const opportunityId = ref(null);

const summary = computed(
  () =>
    crmState.summaries[summaryKey(props.chat.meta?.sender?.id, props.chat.id)]
);
// negócio que saiu para outra unidade não recebe nota: a conversa segue no da unidade de destino
const opportunities = computed(() =>
  (summary.value?.opportunities || []).filter(item => !isHandedOff(item))
);
const selected = computed(() =>
  opportunities.value.find(item => item.id === opportunityId.value)
);

const pickDefault = () => {
  if (selected.value) return;
  opportunityId.value =
    summary.value?.primary_id || opportunities.value[0]?.id || null;
};

const close = () => {
  crmState.noteMode = false;
};

const save = async () => {
  const text = body.value.trim();
  if (!text || !selected.value || isSaving.value) return;
  isSaving.value = true;
  try {
    await CrmAPI.createNote(selected.value.id, text, props.chat.id);
    bumpActivity(selected.value.id);
    body.value = '';
    useAlert(t('OUTSIDER_CRM.NOTE.SAVED', { code: selected.value.code }));
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

// Enter salva, Shift+Enter quebra a linha, Esc volta para a resposta
const onKeydown = event => {
  if (event.key === 'Escape') {
    close();
  } else if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    save();
  }
};

watch(opportunities, pickDefault);
onMounted(() => {
  pickDefault();
  textarea.value?.focus();
});
</script>

<template>
  <div
    class="flex flex-col gap-2 p-3 mx-2 mb-2 rounded-xl bg-n-violet-2 outline outline-1 -outline-offset-1 outline-n-violet-6"
  >
    <div class="flex flex-wrap items-center gap-2">
      <span
        class="inline-flex items-center gap-1 h-7 px-2.5 text-sm font-medium rounded-full text-white bg-n-violet-9"
      >
        <Icon icon="i-lucide-sticky-note" class="size-3.5" />
        {{ t('OUTSIDER_CRM.NOTE.TITLE') }}
      </span>
      <span class="inline-flex items-center gap-1 text-xs text-n-violet-11">
        <Icon icon="i-lucide-lock" class="size-3" />
        {{ t('OUTSIDER_CRM.NOTE.PRIVATE_HINT') }}
      </span>
      <div class="flex-1" />
      <select
        v-if="opportunities.length > 1"
        v-model="opportunityId"
        class="!mb-0 h-7 max-w-64 px-2 py-0 text-xs rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
        :title="t('OUTSIDER_CRM.NOTE.DEAL')"
      >
        <option
          v-for="opportunity in opportunities"
          :key="opportunity.id"
          :value="opportunity.id"
        >
          {{ opportunity.code }} · {{ opportunity.title }}
        </option>
      </select>
      <span v-else-if="selected" class="text-xs truncate text-n-slate-11">
        {{ selected.code }} · {{ selected.title }}
      </span>
      <Button
        type="button"
        size="xs"
        variant="ghost"
        color="slate"
        icon="i-lucide-x"
        :label="t('OUTSIDER_CRM.NOTE.BACK')"
        @click="close"
      />
    </div>
    <textarea
      ref="textarea"
      v-model="body"
      rows="3"
      maxlength="20000"
      class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-none reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-violet-5 focus:outline-n-violet-8"
      :placeholder="t('OUTSIDER_CRM.NOTE.PLACEHOLDER')"
      @keydown="onKeydown"
    />
    <div class="flex items-center justify-between gap-2">
      <span class="text-xs text-n-slate-10">
        {{ t('OUTSIDER_CRM.NOTE.KEYS') }}
      </span>
      <Button
        type="button"
        size="sm"
        icon="i-lucide-sticky-note"
        class="!bg-n-violet-9 hover:!bg-n-violet-10"
        :label="t('OUTSIDER_CRM.NOTE.SAVE')"
        :is-loading="isSaving"
        :disabled="!body.trim() || !selected"
        @click="save"
      />
    </div>
  </div>
</template>
