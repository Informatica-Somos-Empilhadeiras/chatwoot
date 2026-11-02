<script setup>
// OUTSIDER: aba Ligações do negócio (Entrega 26): as ligações vinculadas a ele, de qualquer vendedor, com a gravação
// e o recado da URA para ouvir ali mesmo e por onde o cliente passou na URA. Ligar daqui já vincula a ligação ao
// negócio. Atualiza sozinha a cada ligação.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import LoadError from './LoadError.vue';
import CallButton from '../../voice/CallButton.vue';
import IvrTrail from '../../voice/IvrTrail.vue';
import { formatPhone, formatDuration } from '../../voice/format';
import { errorMessage, formatDateTime } from '../helpers';
import { useCrmChanges } from '../live';

const props = defineProps({
  opportunity: { type: Object, required: true },
});

const { t } = useI18n();

const STATUS_COLORS = {
  answered: 'bg-n-teal-3 text-n-teal-11',
  missed: 'bg-n-ruby-3 text-n-ruby-11',
  unanswered: 'bg-n-amber-3 text-n-amber-11',
  busy: 'bg-n-amber-3 text-n-amber-11',
  failed: 'bg-n-slate-3 text-n-slate-11',
  ringing: 'bg-n-blue-3 text-n-blue-11',
};

const calls = ref([]);
const isLoading = ref(true);
const loadError = ref('');
// { id, kind: 'recording' | 'voicemail' } tocando
const playing = ref(null);

const recorded = computed(
  () => calls.value.filter(call => call.recording_url).length
);

const load = async () => {
  try {
    const { data } = await VoiceAPI.getOpportunityCalls(props.opportunity.id);
    calls.value = data.payload;
    loadError.value = '';
  } catch (error) {
    loadError.value = errorMessage(t, error);
  } finally {
    isLoading.value = false;
  }
};

const toggle = (call, kind) => {
  playing.value =
    playing.value?.id === call.id && playing.value.kind === kind
      ? null
      : { id: call.id, kind };
};

const urlOf = call =>
  playing.value?.kind === 'voicemail' ? call.voicemail_url : call.recording_url;

useCrmChanges(changes => {
  if (changes.some(({ kind }) => ['call', 'reconnected'].includes(kind))) {
    load();
  }
});

watch(
  () => props.opportunity.id,
  () => {
    isLoading.value = true;
    playing.value = null;
    load();
  }
);
onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="opportunity-calls">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <span class="text-xs text-n-slate-11">
        {{
          t('OUTSIDER_VOICE.DEAL_CALLS.SUMMARY', {
            total: calls.length,
            recorded,
          })
        }}
      </span>
      <CallButton
        :number="opportunity.contact?.phone_number"
        :deal="{ id: opportunity.id, title: opportunity.title }"
        :label="t('OUTSIDER_VOICE.DEAL_CALLS.CALL')"
      />
    </div>

    <div v-if="isLoading" class="flex justify-center p-4 text-n-slate-10">
      <Spinner :size="18" />
    </div>
    <LoadError v-else-if="loadError" :message="loadError" @retry="load()" />
    <p v-else-if="!calls.length" class="mb-0 text-sm text-n-slate-11">
      {{ t('OUTSIDER_VOICE.DEAL_CALLS.EMPTY') }}
    </p>

    <ol v-else class="flex flex-col gap-2 mb-0 list-none">
      <li
        v-for="call in calls"
        :key="call.id"
        class="flex flex-col gap-2 px-3 py-2.5 rounded-lg bg-n-alpha-1"
        data-testid="opportunity-call-row"
      >
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
          <Icon
            :icon="
              call.direction === 'inbound'
                ? 'i-lucide-phone-incoming'
                : 'i-lucide-phone-outgoing'
            "
            class="size-4 shrink-0 text-n-slate-11"
          />
          <span class="text-n-slate-12">
            {{ formatDateTime(call.started_at, t) }}
          </span>
          <span
            class="px-2 py-0.5 text-xs rounded-md"
            :class="STATUS_COLORS[call.status]"
          >
            {{ t(`OUTSIDER_VOICE.PANEL.HISTORY.STATUS.${call.status}`) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ call.user?.name || t('OUTSIDER_VOICE.PANEL.HISTORY.NOBODY') }}
            · {{ formatPhone(call.customer_number) }}
            <template v-if="call.talk_seconds">
              · {{ formatDuration(call.talk_seconds) }}
            </template>
          </span>
          <span class="flex gap-1.5 ltr:ml-auto rtl:mr-auto">
            <button
              v-for="kind in ['recording', 'voicemail']"
              v-show="call[`${kind}_url`]"
              :key="kind"
              type="button"
              class="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md"
              :class="
                playing?.id === call.id && playing.kind === kind
                  ? 'bg-n-ruby-3 text-n-ruby-11'
                  : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12'
              "
              :data-testid="`opportunity-call-${kind}`"
              @click="toggle(call, kind)"
            >
              <Icon
                :icon="
                  kind === 'recording'
                    ? 'i-lucide-audio-lines'
                    : 'i-lucide-voicemail'
                "
                class="size-3.5"
              />
              {{
                kind === 'recording'
                  ? t('OUTSIDER_VOICE.PANEL.HISTORY.RECORDING')
                  : t('OUTSIDER_VOICE.DEAL_CALLS.VOICEMAIL')
              }}
            </button>
          </span>
        </div>
        <IvrTrail v-if="call.ivr" :ivr="call.ivr" />
        <div v-if="playing?.id === call.id" class="flex items-center gap-2">
          <audio
            :src="urlOf(call)"
            controls
            autoplay
            class="flex-1 h-9"
            data-testid="opportunity-call-player"
          />
          <a
            :href="urlOf(call)"
            download
            class="flex items-center justify-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :title="t('OUTSIDER_VOICE.PANEL.HISTORY.DOWNLOAD_RECORDING')"
          >
            <Icon icon="i-lucide-download" class="size-4" />
          </a>
        </div>
      </li>
    </ol>
  </div>
</template>
