<script setup>
// OUTSIDER: opções de condição de pagamento que o editor de propostas oferece (Entrega 19). A lista começa
// com A VISTA, 30% + 06X NO BOLETO e CARTÃO DE CRÉDITO; o administrador acrescenta, muda a ordem e apaga.
// Mudar a lista não muda as propostas já feitas: a opção escolhida vira texto na condição da proposta.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import { moveItem, newRowId } from '../../catalog/catalog';
import { settingsError } from './proposalSettings';

const props = defineProps({
  settings: { type: Object, required: true },
});

const emit = defineEmits(['updated']);

const MAX_OPTIONS = 30;
const OPTION_LIMIT = 200;

const { t } = useI18n();

const fromSettings = () =>
  (props.settings.payment_options || []).map(text => ({
    uid: newRowId(),
    text,
  }));

const options = ref(fromSettings());
const newOption = ref('');
const isSaving = ref(false);

watch(
  () => props.settings.payment_options,
  () => {
    options.value = fromSettings();
  }
);

const texts = computed(() =>
  options.value.map(option => option.text.trim()).filter(Boolean)
);

const isDirty = computed(
  () =>
    JSON.stringify(texts.value) !==
    JSON.stringify(props.settings.payment_options || [])
);

const add = () => {
  const text = newOption.value.trim();
  if (!text || options.value.length >= MAX_OPTIONS) return;
  options.value = [...options.value, { uid: newRowId(), text }];
  newOption.value = '';
};

const remove = uid => {
  options.value = options.value.filter(option => option.uid !== uid);
};

const move = (index, step) => {
  options.value = moveItem(options.value, index, step);
};

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateProposalGeneral({
      payment_options: texts.value,
    });
    emit('updated', data);
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PAYMENT.SAVED'));
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="save">
    <p class="mb-0 text-sm text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PAYMENT.DESCRIPTION') }}
    </p>
    <ul class="flex flex-col gap-2 mb-0 list-none">
      <li
        v-for="(option, index) in options"
        :key="option.uid"
        class="flex items-center gap-2"
      >
        <input
          v-model="option.text"
          type="text"
          :maxlength="OPTION_LIMIT"
          class="flex-1 !mb-0 !text-sm rounded-lg"
        />
        <Button
          type="button"
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-arrow-up"
          :disabled="index === 0"
          @click="move(index, -1)"
        />
        <Button
          type="button"
          size="xs"
          variant="ghost"
          color="slate"
          icon="i-lucide-arrow-down"
          :disabled="index === options.length - 1"
          @click="move(index, 1)"
        />
        <Button
          type="button"
          size="xs"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          @click="remove(option.uid)"
        />
      </li>
    </ul>
    <p
      v-if="!options.length"
      class="p-4 mb-0 text-sm text-center rounded-xl text-n-slate-11 bg-n-alpha-1"
    >
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PAYMENT.EMPTY') }}
    </p>
    <div class="flex items-center gap-2">
      <input
        v-model="newOption"
        type="text"
        :maxlength="OPTION_LIMIT"
        :placeholder="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PAYMENT.PLACEHOLDER')"
        class="flex-1 !mb-0 !text-sm rounded-lg"
        @keydown.enter.prevent="add"
      />
      <Button
        type="button"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-plus"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.PAYMENT.ADD')"
        :disabled="!newOption.trim() || options.length >= MAX_OPTIONS"
        @click="add"
      />
    </div>
    <div class="flex justify-end">
      <Button
        type="submit"
        size="sm"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="!isDirty"
      />
    </div>
  </form>
</template>
