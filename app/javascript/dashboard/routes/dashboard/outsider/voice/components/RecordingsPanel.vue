<script setup>
// OUTSIDER: Telefonia > Gravações (Entrega 25; ver app/controllers/api/v1/accounts/outsider/crm/
// call_recordings_controller.rb). As ligações gravadas do mês para ouvir, baixar e encaminhar a um contato.
// Cada pessoa vê o que Outsider::Voice::CallAccess deixa; só o administrador apaga. Cada linha diz até
// quando a gravação fica guardada (Telefonia > Configurações > Gravações).
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import RecordingForwardDialog from './RecordingForwardDialog.vue';
import { formatPhone, formatDuration, formatDate } from '../format';
import {
  currentMonth,
  errorMessage,
  formatDateTime,
  formatMonth,
  shiftMonth,
} from '../../crm/helpers';
import { useCrmChanges } from '../../crm/live';
import { canConfigure } from '../../crm/sections';

const props = defineProps({
  access: { type: Object, required: true },
});

const { t } = useI18n();

const month = ref(currentMonth());
const team = ref([]);
const recordings = ref([]);
const meta = ref({ total: 0, days: 365, bytes: 0 });
const page = ref(1);
const userId = ref('');
const searchText = ref('');
const isLoading = ref(true);
const isLoadingMore = ref(false);
const playing = ref(null);
const forwardDialog = ref(null);

const manager = computed(() => canConfigure(props.access));

const sellerOptions = computed(() => [
  { value: '', label: t('OUTSIDER_VOICE.PANEL.HISTORY.ALL_SELLERS') },
  ...team.value.map(person => ({ value: person.id, label: person.name })),
]);

const formatBytes = bytes => {
  const size = (value, unit) => `${value.toFixed(1).replace('.', ',')} ${unit}`;
  if (bytes >= 1024 ** 3) return size(bytes / 1024 ** 3, 'GB');
  if (bytes >= 1024 ** 2) return size(bytes / 1024 ** 2, 'MB');
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
};

const customerName = call =>
  call.contact_name || formatPhone(call.customer_number);

const load = async (more = false) => {
  page.value = more ? page.value + 1 : 1;
  const { data } = await VoiceAPI.getRecordings({
    month: month.value,
    page: page.value,
    user_id: userId.value || undefined,
    q: searchText.value.trim() || undefined,
  });
  recordings.value = more
    ? [...recordings.value, ...data.payload]
    : data.payload;
  meta.value = data.meta;
};

const refresh = async () => {
  try {
    await load();
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const loadMore = async () => {
  isLoadingMore.value = true;
  try {
    await load(true);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoadingMore.value = false;
  }
};

const remove = async call => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(t('OUTSIDER_VOICE.PANEL.HISTORY.DELETE_RECORDING_CONFIRM'))
  )
    return;
  try {
    await VoiceAPI.deleteRecording(call.id);
    if (playing.value === call.id) playing.value = null;
    refresh();
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

let searchTimer = null;
watch(searchText, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(refresh, 300);
});
watch([month, userId], () => {
  isLoading.value = true;
  refresh();
});

useCrmChanges(changes => {
  if (changes.some(({ kind }) => ['call', 'reconnected'].includes(kind))) {
    refresh();
  }
});

onMounted(async () => {
  refresh();
  if (!manager.value) return;
  try {
    team.value = (await VoiceAPI.team()).data;
  } catch {
    team.value = [];
  }
});
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

    <section
      class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <div
        class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 border-b border-n-weak"
      >
        <span class="flex flex-col gap-0.5">
          <h3 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.RECORDINGS.TITLE', { count: meta.total }) }}
          </h3>
          <span class="text-xs text-n-slate-11" data-testid="recordings-meta">
            {{
              t('OUTSIDER_VOICE.RECORDINGS.META', {
                size: formatBytes(meta.bytes),
                days: meta.days,
              })
            }}
          </span>
        </span>
        <span class="flex flex-wrap items-center justify-end gap-2">
          <input
            v-model="searchText"
            type="search"
            :placeholder="t('OUTSIDER_VOICE.RECORDINGS.SEARCH')"
            class="!mb-0 !text-sm rounded-lg !w-60"
            data-testid="recordings-search"
          />
          <Select v-if="manager" v-model="userId" :options="sellerOptions" />
        </span>
      </div>

      <p
        v-if="!isLoading && !recordings.length"
        class="px-4 py-6 mb-0 text-sm text-center text-n-slate-11"
      >
        {{ t('OUTSIDER_VOICE.RECORDINGS.EMPTY') }}
      </p>
      <div
        v-for="call in recordings"
        :key="call.id"
        class="flex flex-col gap-2 px-4 py-3 border-b border-n-weak last:border-0"
        data-testid="recording-row"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <button
            type="button"
            class="flex items-center min-w-0 gap-3 text-left"
            @click="playing = playing === call.id ? null : call.id"
          >
            <span
              class="flex items-center justify-center rounded-full size-9 shrink-0"
              :class="
                playing === call.id
                  ? 'bg-n-brand text-white'
                  : 'bg-n-alpha-2 text-n-slate-12'
              "
            >
              <Icon
                :icon="playing === call.id ? 'i-lucide-pause' : 'i-lucide-play'"
                class="size-4"
              />
            </span>
            <span class="flex flex-col min-w-0">
              <span class="flex items-center gap-2 text-sm text-n-slate-12">
                <Icon
                  :icon="
                    call.direction === 'inbound'
                      ? 'i-lucide-phone-incoming'
                      : 'i-lucide-phone-outgoing'
                  "
                  class="size-3.5 shrink-0 text-n-slate-11"
                />
                <span class="truncate">{{ customerName(call) }}</span>
                <span v-if="call.contact_name" class="text-xs text-n-slate-11">
                  {{ formatPhone(call.customer_number) }}
                </span>
              </span>
              <span class="text-xs text-n-slate-11">
                {{ formatDateTime(call.started_at, t) }}
                ·
                {{
                  call.user?.name || t('OUTSIDER_VOICE.PANEL.HISTORY.NOBODY')
                }}
                · {{ formatDuration(call.talk_seconds || 0) }} ·
                {{ formatBytes(call.byte_size) }}
              </span>
            </span>
          </button>
          <span class="flex items-center gap-1">
            <span
              class="px-2 py-0.5 mr-1 text-xs rounded-md bg-n-alpha-1 text-n-slate-11"
              :title="t('OUTSIDER_VOICE.RECORDINGS.EXPIRES_HELP')"
            >
              {{
                t('OUTSIDER_VOICE.RECORDINGS.EXPIRES', {
                  date: formatDate(call.expires_on),
                })
              }}
            </span>
            <Button
              size="sm"
              variant="faded"
              color="slate"
              icon="i-lucide-forward"
              :label="t('OUTSIDER_VOICE.RECORDINGS.FORWARD.OPEN')"
              data-testid="recording-forward"
              @click="forwardDialog.open(call)"
            />
            <a
              :href="call.recording_url"
              download
              class="flex items-center justify-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
              :title="t('OUTSIDER_VOICE.PANEL.HISTORY.DOWNLOAD_RECORDING')"
              data-testid="recording-download"
            >
              <Icon icon="i-lucide-download" class="size-4" />
            </a>
            <Button
              v-if="access.administrator"
              size="sm"
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              :title="t('OUTSIDER_VOICE.PANEL.HISTORY.DELETE_RECORDING')"
              @click="remove(call)"
            />
          </span>
        </div>
        <audio
          v-if="playing === call.id"
          :src="call.recording_url"
          controls
          autoplay
          class="w-full h-9"
          data-testid="recording-player"
          @ended="playing = null"
        />
      </div>
      <div
        v-if="recordings.length < meta.total"
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

    <RecordingForwardDialog ref="forwardDialog" />
  </div>
</template>
