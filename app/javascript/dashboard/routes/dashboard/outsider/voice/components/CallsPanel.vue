<script setup>
// OUTSIDER: Telefonia > Ligações (Entrega 22, separada do CRM na 23). A fila de perdidas para retornar com
// 1 clique e o histórico do mês, com filtros. Cada pessoa vê o que Outsider::Voice::CallAccess deixa (o
// vendedor, as dele e as perdidas para ele retornar); atualiza sozinho a cada ligação. Entrega 24: exporta a
// lista com os filtros da tela (planilha) e toca a gravação da ligação, quando houver.
// Entrega 26: vincular (ou trocar) o negócio do CRM de cada ligação, ouvir o recado deixado na URA e ver por onde
// o cliente passou nela.
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CallButton from '../CallButton.vue';
import DealPicker from '../DealPicker.vue';
import IvrTrail from '../IvrTrail.vue';
import { formatPhone, formatDuration, downloadBlob } from '../format';
import {
  currentMonth,
  errorMessage,
  formatDateTime,
  formatMonth,
  shiftMonth,
} from '../../crm/helpers';
import { useCrmChanges } from '../../crm/live';
import { canConfigure, CRM_ROUTE } from '../../crm/sections';

const props = defineProps({
  access: { type: Object, required: true },
});

const { t } = useI18n();
const router = useRouter();
const route = useRoute();

const STATUS_COLORS = {
  answered: 'bg-n-teal-3 text-n-teal-11',
  missed: 'bg-n-ruby-3 text-n-ruby-11',
  unanswered: 'bg-n-amber-3 text-n-amber-11',
  busy: 'bg-n-amber-3 text-n-amber-11',
  failed: 'bg-n-slate-3 text-n-slate-11',
  ringing: 'bg-n-blue-3 text-n-blue-11',
};

const month = ref(currentMonth());
const team = ref([]);
const toReturn = ref([]);
const calls = ref([]);
const total = ref(0);
const page = ref(1);
const filters = ref({ direction: '', status: '', user_id: '' });
const loaded = ref(false);
const isLoading = ref(true);
const isLoadingMore = ref(false);
const isExporting = ref(false);
// ligação com a gravação ou o recado aberto (tocando) na lista: { id, kind: 'recording' | 'voicemail' }
const playing = ref(null);
// ligação com a escolha de negócio aberta
const linking = ref(null);
const isLinking = ref(false);

// gestor de unidade e administrador filtram por vendedor
const manager = computed(() => canConfigure(props.access));

const directionOptions = computed(() => [
  { value: '', label: t('OUTSIDER_VOICE.PANEL.HISTORY.ALL_DIRECTIONS') },
  ...['outbound', 'inbound'].map(value => ({
    value,
    label: t(`OUTSIDER_VOICE.PANEL.HISTORY.DIRECTIONS.${value}`),
  })),
]);
const statusOptions = computed(() => [
  { value: '', label: t('OUTSIDER_VOICE.PANEL.HISTORY.ALL_STATUS') },
  ...['answered', 'missed', 'unanswered', 'busy', 'failed'].map(value => ({
    value,
    label: t(`OUTSIDER_VOICE.PANEL.HISTORY.STATUS.${value}`),
  })),
]);
const sellerOptions = computed(() => [
  { value: '', label: t('OUTSIDER_VOICE.PANEL.HISTORY.ALL_SELLERS') },
  ...team.value.map(person => ({ value: person.id, label: person.name })),
]);

const customerName = call =>
  call.contact_name || formatPhone(call.customer_number);

const isPlaying = (call, kind) =>
  playing.value?.id === call.id && playing.value.kind === kind;

const togglePlay = (call, kind) => {
  playing.value = isPlaying(call, kind) ? null : { id: call.id, kind };
};

const playingUrl = call =>
  playing.value?.kind === 'voicemail' ? call.voicemail_url : call.recording_url;

const linkDeal = async (call, deal) => {
  isLinking.value = true;
  try {
    const { data } = await VoiceAPI.linkCall(call.id, deal?.id);
    Object.assign(call, data);
    linking.value = null;
    useAlert(
      deal
        ? t('OUTSIDER_VOICE.DEAL_LINK.LINKED', { title: deal.title })
        : t('OUTSIDER_VOICE.DEAL_LINK.UNLINKED')
    );
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLinking.value = false;
  }
};

const openDeal = id =>
  router.push({
    name: CRM_ROUTE,
    params: { accountId: route.params.accountId, tab: 'opportunities' },
    query: { negocio: id },
  });

const loadCalls = async (more = false) => {
  page.value = more ? page.value + 1 : 1;
  const { data } = await VoiceAPI.getCalls({
    month: month.value,
    page: page.value,
    ...filters.value,
  });
  calls.value = more ? [...calls.value, ...data.payload] : data.payload;
  total.value = data.meta.total;
};

const load = async () => {
  try {
    const [returnResponse, teamResponse] = await Promise.all([
      VoiceAPI.getCalls({ to_return: 1 }),
      VoiceAPI.team(),
      loadCalls(),
    ]);
    toReturn.value = returnResponse.data.payload;
    team.value = teamResponse.data;
    loaded.value = true;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const loadMore = async () => {
  isLoadingMore.value = true;
  try {
    await loadCalls(true);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoadingMore.value = false;
  }
};

const exportList = async () => {
  isExporting.value = true;
  try {
    const response = await VoiceAPI.exportCalls({
      kind: 'calls',
      source: 'history',
      month: month.value,
      ...filters.value,
    });
    downloadBlob(response);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isExporting.value = false;
  }
};

const deleteRecording = async call => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(t('OUTSIDER_VOICE.PANEL.HISTORY.DELETE_RECORDING_CONFIRM'))
  ) {
    return;
  }
  try {
    await VoiceAPI.deleteRecording(call.id);
    call.recording_url = null;
    if (playing.value?.kind === 'recording') playing.value = null;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

watch(month, () => {
  isLoading.value = true;
  load();
});
watch(filters, () => loadCalls().catch(() => {}), { deep: true });

// cada ligação que começa, é atendida ou termina avisa ao vivo
useCrmChanges(changes => {
  if (changes.some(({ kind }) => ['call', 'reconnected'].includes(kind))) {
    load();
  }
});

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-wrap items-center gap-2">
      <Button
        icon="i-lucide-chevron-left"
        size="sm"
        variant="faded"
        color="slate"
        :aria-label="t('OUTSIDER_CRM.GOALS.PREVIOUS')"
        @click="month = shiftMonth(month, -1)"
      />
      <span
        class="inline-block px-1 text-sm font-medium first-letter:uppercase text-n-slate-12"
      >
        {{ formatMonth(month) }}
      </span>
      <Button
        icon="i-lucide-chevron-right"
        size="sm"
        variant="faded"
        color="slate"
        :aria-label="t('OUTSIDER_CRM.GOALS.NEXT')"
        @click="month = shiftMonth(month, 1)"
      />
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
    </div>

    <template v-if="loaded">
      <!-- perdidas para retornar -->
      <section
        class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="flex flex-col gap-0.5 px-4 py-3 border-b border-n-weak">
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.PANEL.RETURN.TITLE') }}
            <span
              v-if="toReturn.length"
              class="px-1.5 py-0.5 ml-1 text-xs rounded-md bg-n-ruby-3 text-n-ruby-11"
            >
              {{ toReturn.length }}
            </span>
          </h3>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.PANEL.RETURN.DESCRIPTION') }}
          </p>
        </div>
        <p
          v-if="!toReturn.length"
          class="px-4 py-3 mb-0 text-sm text-n-slate-11"
        >
          {{ t('OUTSIDER_VOICE.PANEL.RETURN.EMPTY') }}
        </p>
        <div
          v-for="call in toReturn"
          :key="call.id"
          class="flex flex-wrap items-center justify-between gap-3 px-4 py-2.5 border-b border-n-weak last:border-0"
          data-testid="calls-return-row"
        >
          <span class="flex items-center min-w-0 gap-3">
            <Icon
              icon="i-lucide-phone-missed"
              class="size-4 shrink-0 text-n-ruby-11"
            />
            <span class="flex flex-col min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ customerName(call) }}
                <span v-if="call.contact_name" class="text-xs text-n-slate-11">
                  {{ formatPhone(call.customer_number) }}
                </span>
              </span>
              <span class="text-xs text-n-slate-11">
                {{ formatDateTime(call.started_at, t) }}
                <template v-if="call.did">
                  ·
                  {{
                    t('OUTSIDER_VOICE.PANEL.RETURN.TO_NUMBER', {
                      number: formatPhone(call.did),
                    })
                  }}
                </template>
              </span>
            </span>
          </span>
          <span class="flex items-center gap-2">
            <Button
              v-if="call.voicemail_url"
              size="sm"
              :variant="isPlaying(call, 'voicemail') ? 'solid' : 'ghost'"
              color="ruby"
              icon="i-lucide-voicemail"
              :label="t('OUTSIDER_VOICE.DEAL_CALLS.VOICEMAIL')"
              data-testid="calls-return-voicemail"
              @click="togglePlay(call, 'voicemail')"
            />
            <Button
              v-if="call.opportunity_id"
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-kanban"
              :label="t('OUTSIDER_VOICE.PANEL.RETURN.OPEN_DEAL')"
              @click="openDeal(call.opportunity_id)"
            />
            <CallButton
              :number="call.customer_number"
              :label="t('OUTSIDER_VOICE.PANEL.RETURN.CALL_BACK')"
              :deal="call.opportunity"
            />
          </span>
          <IvrTrail v-if="call.ivr" :ivr="call.ivr" class="basis-full" />
          <audio
            v-if="isPlaying(call, 'voicemail')"
            :src="call.voicemail_url"
            controls
            autoplay
            class="w-full h-9 basis-full"
          />
        </div>
      </section>

      <!-- histórico -->
      <section
        class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div
          class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 border-b border-n-weak"
        >
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.PANEL.HISTORY.TITLE') }}
          </h3>
          <span class="flex flex-wrap items-center gap-2">
            <Select v-model="filters.direction" :options="directionOptions" />
            <Select v-model="filters.status" :options="statusOptions" />
            <Select
              v-if="manager"
              v-model="filters.user_id"
              :options="sellerOptions"
            />
            <Button
              size="sm"
              variant="faded"
              color="slate"
              icon="i-lucide-download"
              :label="t('OUTSIDER_VOICE.PANEL.HISTORY.EXPORT')"
              :is-loading="isExporting"
              data-testid="calls-export"
              @click="exportList"
            />
          </span>
        </div>
        <p v-if="!calls.length" class="px-4 py-3 mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.PANEL.HISTORY.EMPTY') }}
        </p>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm min-w-[46rem]">
            <thead>
              <tr class="text-xs text-left text-n-slate-11">
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.WHEN') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.CUSTOMER') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.SELLER') }}
                </th>
                <th class="px-4 py-2 font-medium">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.SITUATION') }}
                </th>
                <th class="px-4 py-2 font-medium text-right">
                  {{ t('OUTSIDER_VOICE.PANEL.HISTORY.DURATION') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <template v-for="call in calls" :key="call.id">
                <tr
                  class="border-t border-n-weak"
                  data-testid="calls-history-row"
                >
                  <td class="px-4 py-2.5 whitespace-nowrap text-n-slate-11">
                    <span class="flex items-center gap-2">
                      <Icon
                        :icon="
                          call.direction === 'inbound'
                            ? 'i-lucide-phone-incoming'
                            : 'i-lucide-phone-outgoing'
                        "
                        class="size-3.5"
                        :title="
                          t(
                            `OUTSIDER_VOICE.PANEL.HISTORY.DIRECTIONS.${call.direction}`
                          )
                        "
                      />
                      {{ formatDateTime(call.started_at, t) }}
                    </span>
                  </td>
                  <td class="px-4 py-2.5">
                    <span class="flex items-center gap-2 min-w-0">
                      <span class="truncate text-n-slate-12">
                        {{ customerName(call) }}
                      </span>
                      <CallButton show-number :number="call.customer_number" />
                    </span>
                    <span class="flex items-center gap-1 mt-0.5 text-xs">
                      <button
                        v-if="call.opportunity"
                        type="button"
                        class="flex items-center min-w-0 gap-1 text-n-slate-11 hover:text-n-slate-12"
                        :title="t('OUTSIDER_VOICE.PANEL.RETURN.OPEN_DEAL')"
                        @click="openDeal(call.opportunity.id)"
                      >
                        <Icon
                          icon="i-lucide-kanban"
                          class="size-3.5 shrink-0"
                        />
                        <span class="truncate max-w-[14rem]">
                          {{ call.opportunity.title }}
                        </span>
                      </button>
                      <button
                        type="button"
                        class="flex items-center gap-1 shrink-0 text-n-blue-11 hover:underline"
                        data-testid="calls-link-deal"
                        @click="linking = linking === call.id ? null : call.id"
                      >
                        <Icon icon="i-lucide-link" class="size-3.5" />
                        {{
                          call.opportunity
                            ? t('OUTSIDER_VOICE.DEAL_LINK.CHANGE')
                            : t('OUTSIDER_VOICE.DEAL_LINK.LINK')
                        }}
                      </button>
                    </span>
                  </td>
                  <td class="px-4 py-2.5 text-n-slate-12">
                    {{
                      call.user?.name ||
                      t('OUTSIDER_VOICE.PANEL.HISTORY.NOBODY')
                    }}
                  </td>
                  <td class="px-4 py-2.5">
                    <span
                      class="px-2 py-0.5 text-xs rounded-md whitespace-nowrap"
                      :class="STATUS_COLORS[call.status]"
                    >
                      {{
                        t(`OUTSIDER_VOICE.PANEL.HISTORY.STATUS.${call.status}`)
                      }}
                    </span>
                    <span
                      v-if="call.returned_by"
                      class="block mt-0.5 text-xs text-n-slate-11"
                    >
                      {{
                        t('OUTSIDER_VOICE.PANEL.HISTORY.RETURNED_BY', {
                          name: call.returned_by.name,
                        })
                      }}
                    </span>
                  </td>
                  <td
                    class="px-4 py-2.5 text-right tabular-nums text-n-slate-12"
                  >
                    <span class="inline-flex items-center gap-2">
                      <button
                        v-if="call.voicemail_url"
                        type="button"
                        class="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md"
                        :class="
                          isPlaying(call, 'voicemail')
                            ? 'bg-n-ruby-3 text-n-ruby-11'
                            : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12'
                        "
                        data-testid="calls-voicemail"
                        @click="togglePlay(call, 'voicemail')"
                      >
                        <Icon icon="i-lucide-voicemail" class="size-3.5" />
                        {{ t('OUTSIDER_VOICE.DEAL_CALLS.VOICEMAIL') }}
                      </button>
                      <button
                        v-if="call.recording_url"
                        type="button"
                        class="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md"
                        :class="
                          isPlaying(call, 'recording')
                            ? 'bg-n-ruby-3 text-n-ruby-11'
                            : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12'
                        "
                        :title="t('OUTSIDER_VOICE.PANEL.HISTORY.RECORDING')"
                        data-testid="calls-recording"
                        @click="togglePlay(call, 'recording')"
                      >
                        <Icon icon="i-lucide-audio-lines" class="size-3.5" />
                        {{ t('OUTSIDER_VOICE.PANEL.HISTORY.RECORDING') }}
                      </button>
                      {{
                        call.talk_seconds
                          ? formatDuration(call.talk_seconds)
                          : '—'
                      }}
                    </span>
                  </td>
                </tr>
                <tr v-if="linking === call.id">
                  <td colspan="5" class="px-4 pb-3">
                    <div class="max-w-md">
                      <DealPicker
                        :current="call.opportunity"
                        :busy="isLinking"
                        @pick="linkDeal(call, $event)"
                        @cancel="linking = null"
                      />
                    </div>
                  </td>
                </tr>
                <tr v-if="call.ivr && playing?.id === call.id">
                  <td colspan="5" class="px-4 pb-2">
                    <IvrTrail :ivr="call.ivr" />
                  </td>
                </tr>
                <tr v-if="playing?.id === call.id && playingUrl(call)">
                  <td colspan="5" class="px-4 pb-3">
                    <span class="flex items-center gap-2">
                      <audio
                        :src="playingUrl(call)"
                        controls
                        autoplay
                        class="flex-1 h-9"
                        data-testid="calls-recording-player"
                      />
                      <a
                        :href="playingUrl(call)"
                        download
                        class="flex items-center justify-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
                        :title="
                          t('OUTSIDER_VOICE.PANEL.HISTORY.DOWNLOAD_RECORDING')
                        "
                      >
                        <Icon icon="i-lucide-download" class="size-4" />
                      </a>
                      <Button
                        v-if="
                          access.administrator && playing.kind === 'recording'
                        "
                        size="sm"
                        variant="ghost"
                        color="ruby"
                        icon="i-lucide-trash-2"
                        :title="
                          t('OUTSIDER_VOICE.PANEL.HISTORY.DELETE_RECORDING')
                        "
                        @click="deleteRecording(call)"
                      />
                    </span>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>
        <div
          v-if="calls.length < total"
          class="px-4 py-2 border-t border-n-weak"
        >
          <Button
            size="sm"
            variant="ghost"
            :label="t('OUTSIDER_VOICE.PANEL.HISTORY.LOAD_MORE')"
            :is-loading="isLoadingMore"
            @click="loadMore"
          />
        </div>
      </section>
    </template>
  </div>
</template>
