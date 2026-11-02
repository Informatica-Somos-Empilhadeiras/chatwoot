<script setup>
// OUTSIDER: Telefonia > URA (Entrega 26, só administradores): as URAs da conta com ligar e desligar e os números em
// que cada uma atende. "Nova URA" já cria um começo pronto (boas-vindas, menu, transferir e recado) e abre o editor.
// Cada número fica com uma URA ativa; a URA sem número atende todos os que não têm URA própria.
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { formatPhone } from '../format';
import { errorMessage, formatDateTime } from '../../crm/helpers';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const flows = ref([]);
const options = ref({});
const isLoading = ref(true);
const isCreating = ref(false);
const busy = ref({});

const load = async () => {
  try {
    const { data } = await VoiceAPI.getIvrFlows();
    flows.value = data.payload;
    options.value = data.options;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const openFlow = flow =>
  router.push({
    name: 'outsider_voice_ivr_editor',
    params: { accountId: route.params.accountId, flowId: flow.id },
  });

const create = async () => {
  isCreating.value = true;
  try {
    const { data } = await VoiceAPI.createIvrFlow();
    openFlow(data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isCreating.value = false;
  }
};

// ligar ou desligar direto da lista; o servidor recusa número que já tem outra URA ativa
const toggle = async (flow, active) => {
  busy.value = { ...busy.value, [flow.id]: true };
  try {
    const { data } = await VoiceAPI.updateIvrFlow(flow.id, { active });
    Object.assign(flow, data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    busy.value = { ...busy.value, [flow.id]: false };
  }
};

const remove = async flow => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('OUTSIDER_VOICE.IVR.LIST.DELETE_CONFIRM', { name: flow.name })
    )
  )
    return;
  try {
    await VoiceAPI.deleteIvrFlow(flow.id);
    flows.value = flows.value.filter(item => item.id !== flow.id);
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const numbersOf = flow =>
  flow.numbers.length
    ? flow.numbers.map(number => formatPhone(number)).join(', ')
    : t('OUTSIDER_VOICE.IVR.EDITOR.ALL_NUMBERS');

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="ivr-flows">
    <div
      class="flex flex-wrap items-start justify-between gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <div class="flex flex-col gap-1 max-w-2xl">
        <h3 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_VOICE.IVR.LIST.TITLE') }}
        </h3>
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.IVR.LIST.DESCRIPTION') }}
        </p>
        <p class="flex items-center gap-1.5 mb-0 text-xs text-n-slate-11">
          <Icon icon="i-lucide-audio-lines" class="size-3.5" />
          {{
            options.natural_voice
              ? t('OUTSIDER_VOICE.IVR.LIST.NATURAL_VOICE')
              : t('OUTSIDER_VOICE.IVR.LIST.CENTRAL_VOICE')
          }}
        </p>
      </div>
      <Button
        icon="i-lucide-plus"
        :label="t('OUTSIDER_VOICE.IVR.LIST.NEW')"
        :is-loading="isCreating"
        data-testid="ivr-new"
        @click="create"
      />
    </div>

    <div v-if="isLoading" class="flex justify-center p-6">
      <Spinner class="text-n-slate-10" />
    </div>
    <div
      v-else-if="!flows.length"
      class="flex flex-col items-center gap-2 p-10 text-center rounded-xl bg-n-alpha-1"
    >
      <Icon icon="i-lucide-workflow" class="size-10 text-n-slate-9" />
      <p class="max-w-md mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_VOICE.IVR.LIST.EMPTY') }}
      </p>
    </div>
    <div
      v-else
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <div
        v-for="flow in flows"
        :key="flow.id"
        class="flex flex-wrap items-center gap-3 px-4 py-3 border-b border-n-weak last:border-0"
        data-testid="ivr-flow-row"
      >
        <Switch
          :model-value="flow.active"
          :disabled="busy[flow.id]"
          @update:model-value="toggle(flow, $event)"
        />
        <button
          type="button"
          class="flex flex-col flex-1 min-w-0 text-left"
          @click="openFlow(flow)"
        >
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ flow.name }}
          </span>
          <span class="text-xs truncate text-n-slate-11">
            {{ numbersOf(flow) }} ·
            {{ t('OUTSIDER_VOICE.IVR.LIST.BLOCKS', { count: flow.blocks }) }}
            · {{ formatDateTime(flow.updated_at, t) }}
          </span>
        </button>
        <Button
          sm
          slate
          faded
          icon="i-lucide-pencil"
          :label="t('OUTSIDER_VOICE.IVR.LIST.EDIT')"
          @click="openFlow(flow)"
        />
        <Button
          sm
          ghost
          ruby
          icon="i-lucide-trash-2"
          :title="t('OUTSIDER_VOICE.IVR.LIST.DELETE')"
          @click="remove(flow)"
        />
      </div>
    </div>
  </div>
</template>
