<script setup>
// OUTSIDER: janela "Enviar localização", aberta pelo menu do clipe (ComposerAttachMenu.vue), só nas caixas da Evolution.
// Busca o endereço no OpenStreetMap (ou aceita coordenadas e links do Google Maps colados), mostra
// os endereços salvos da conta e a localização atual do navegador. Depois de escolher, dá para
// ajustar o nome que o cliente vê e enviar como o pin de mapa do WhatsApp
// (ver app/services/outsider/location_sender.rb). Só o administrador salva e apaga endereços.
// O mapa da escolha aceita clique para levar o pin ao ponto exato: o OpenStreetMap costuma achar só
// a rua (exact: false) e a localização do navegador num computador pode errar por centenas de metros.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import LocationMap from 'dashboard/components-next/message/outsider/LocationMap.vue';
import LocationsAPI from 'dashboard/api/outsider/locations';
import { formatCoordinates } from 'dashboard/helper/outsider/location';

const props = defineProps({
  conversationId: { type: Number, default: null },
});

const MIN_QUERY = 3;
// a partir daqui a localização do navegador merece o aviso para conferir o pin
const LOOSE_ACCURACY = 50;

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const query = ref('');
const results = ref([]);
const isSearching = ref(false);
const searchError = ref('');
const saved = ref([]);
const canManage = ref(false);
const selected = ref(null);
const isSending = ref(false);
const isSaving = ref(false);
const isLocating = ref(false);
let searchController = null;

const hasQuery = computed(() => query.value.trim().length >= MIN_QUERY);
const samePoint = (a, b) =>
  Number(a.latitude).toFixed(6) === Number(b.latitude).toFixed(6) &&
  Number(a.longitude).toFixed(6) === Number(b.longitude).toFixed(6);
const isAlreadySaved = computed(
  () =>
    !!selected.value &&
    saved.value.some(
      item =>
        item.name === selected.value.name.trim() &&
        samePoint(item, selected.value)
    )
);

const errorMessage = (error, fallback = 'DEFAULT') => {
  const code = error?.response?.data?.error;
  const key = `OUTSIDER_WHATSAPP.SEND_LOCATION.ERRORS.${String(code || '').toUpperCase()}`;
  if (code && t(key) !== key) return t(key);
  return (
    error?.response?.data?.message ||
    t(`OUTSIDER_WHATSAPP.SEND_LOCATION.ERRORS.${fallback}`)
  );
};

const search = useDebounceFn(async term => {
  searchController?.abort();
  if (term.trim().length < MIN_QUERY) {
    results.value = [];
    isSearching.value = false;
    return;
  }
  searchController = new AbortController();
  isSearching.value = true;
  searchError.value = '';
  try {
    const { data } = await LocationsAPI.search(term.trim(), {
      signal: searchController.signal,
    });
    results.value = data.payload || [];
    isSearching.value = false;
  } catch (error) {
    if (error?.name === 'CanceledError') return;
    results.value = [];
    searchError.value = errorMessage(error, 'SEARCH');
    isSearching.value = false;
  }
}, 500);

watch(query, term => {
  isSearching.value = term.trim().length >= MIN_QUERY;
  search(term);
});

const loadSaved = async () => {
  try {
    const { data } = await LocationsAPI.saved();
    saved.value = data.payload || [];
    canManage.value = !!data.can_manage;
  } catch {
    saved.value = [];
  }
};

const choose = (item, accuracy = null) => {
  selected.value = {
    name: item.name || '',
    address: item.address || '',
    latitude: Number(item.latitude),
    longitude: Number(item.longitude),
    // endereço salvo e coordenada colada já são o ponto certo
    exact: item.exact !== false,
    accuracy,
    moved: false,
  };
};

const movePin = point => {
  selected.value = { ...selected.value, ...point, moved: true };
};

const pinNotice = computed(() => {
  const place = selected.value;
  if (!place || place.moved) return '';
  if (place.accuracy > LOOSE_ACCURACY) {
    return t('OUTSIDER_WHATSAPP.SEND_LOCATION.ACCURACY', {
      meters: Math.round(place.accuracy),
    });
  }
  if (!place.exact) return t('OUTSIDER_WHATSAPP.SEND_LOCATION.APPROXIMATE');
  return '';
});

const useCurrentPosition = () => {
  if (!navigator.geolocation) {
    useAlert(t('OUTSIDER_WHATSAPP.SEND_LOCATION.ERRORS.GEOLOCATION'));
    return;
  }
  isLocating.value = true;
  navigator.geolocation.getCurrentPosition(
    async position => {
      const { latitude, longitude, accuracy } = position.coords;
      const point = `${latitude.toFixed(6)},${longitude.toFixed(6)}`;
      let found = null;
      try {
        const { data } = await LocationsAPI.search(point);
        [found] = data.payload || [];
      } catch {
        // sem o endereço do ponto, vai só o pin
      }
      // o pin fica onde o navegador disse; da busca vem só o endereço do ponto
      choose({ ...found, latitude, longitude, exact: true }, accuracy);
      isLocating.value = false;
    },
    () => {
      isLocating.value = false;
      useAlert(t('OUTSIDER_WHATSAPP.SEND_LOCATION.ERRORS.GEOLOCATION'));
    },
    { enableHighAccuracy: true, timeout: 10000 }
  );
};

const saveSelected = async () => {
  if (!selected.value?.name.trim() || isSaving.value) return;
  isSaving.value = true;
  try {
    const { name, address, latitude, longitude } = selected.value;
    const { data } = await LocationsAPI.save({
      name: name.trim(),
      address,
      latitude,
      longitude,
    });
    saved.value = [...saved.value, data];
    useAlert(t('OUTSIDER_WHATSAPP.SEND_LOCATION.SAVED'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSaving.value = false;
  }
};

const removeSaved = async item => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('OUTSIDER_WHATSAPP.SEND_LOCATION.REMOVE_CONFIRM'))) {
    return;
  }
  try {
    await LocationsAPI.remove(item.id);
    saved.value = saved.value.filter(row => row.id !== item.id);
  } catch (error) {
    useAlert(errorMessage(error));
  }
};

const open = () => {
  query.value = '';
  results.value = [];
  searchError.value = '';
  selected.value = null;
  loadSaved();
  dialogRef.value?.open();
};

const send = async () => {
  if (!selected.value || isSending.value) return;
  isSending.value = true;
  try {
    const { name, address, latitude, longitude } = selected.value;
    const { data } = await LocationsAPI.send(props.conversationId, {
      name: name.trim(),
      address: address.trim(),
      latitude,
      longitude,
    });
    if (data?.message) store.dispatch('addMessage', data.message);
    dialogRef.value?.close();
    useAlert(t('OUTSIDER_WHATSAPP.SEND_LOCATION.SENT'));
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    isSending.value = false;
  }
};

defineExpose({ open });

const fieldClass =
  'w-full !mb-0 px-3 py-2 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand';
const rowClass =
  'flex items-center gap-3 px-2 py-2 text-left rounded-lg hover:bg-n-alpha-1';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_WHATSAPP.SEND_LOCATION.TITLE')"
    :description="t('OUTSIDER_WHATSAPP.SEND_LOCATION.DESCRIPTION')"
    :confirm-button-label="t('OUTSIDER_WHATSAPP.SEND_LOCATION.SEND')"
    :disable-confirm-button="!selected"
    :is-loading="isSending"
    width="md"
    @confirm="send"
  >
    <div class="flex flex-col gap-4" data-send-location-dialog>
      <template v-if="selected">
        <div class="overflow-hidden rounded-lg border border-n-weak">
          <LocationMap
            :latitude="selected.latitude"
            :longitude="selected.longitude"
            :width="560"
            :height="220"
            :zoom="17"
            adjustable
            class="!w-full"
            @pick="movePin"
          />
        </div>
        <p
          class="mb-0 -mt-2 text-xs"
          :class="pinNotice ? 'text-n-amber-11' : 'text-n-slate-11'"
          data-location-pin-hint
        >
          {{
            pinNotice ||
            (selected.moved
              ? t('OUTSIDER_WHATSAPP.SEND_LOCATION.MOVED')
              : t('OUTSIDER_WHATSAPP.SEND_LOCATION.ADJUST_HINT'))
          }}
        </p>
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('OUTSIDER_WHATSAPP.SEND_LOCATION.NAME') }}
          </span>
          <input
            v-model="selected.name"
            type="text"
            maxlength="100"
            :class="fieldClass"
            :placeholder="t('OUTSIDER_WHATSAPP.SEND_LOCATION.NAME_PLACEHOLDER')"
            data-location-name
            @keydown.enter.prevent
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ t('OUTSIDER_WHATSAPP.SEND_LOCATION.ADDRESS') }}
          </span>
          <textarea
            v-model="selected.address"
            rows="2"
            maxlength="300"
            :class="fieldClass"
            class="resize-none"
          />
        </label>
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span class="text-xs tabular-nums text-n-slate-11">
            {{ formatCoordinates(selected) }}
          </span>
          <div class="flex items-center gap-2">
            <NextButton
              v-if="canManage"
              type="button"
              size="sm"
              variant="faded"
              color="slate"
              :icon="
                isAlreadySaved
                  ? 'i-lucide-bookmark-check'
                  : 'i-lucide-bookmark-plus'
              "
              :label="
                isAlreadySaved
                  ? t('OUTSIDER_WHATSAPP.SEND_LOCATION.ALREADY_SAVED')
                  : t('OUTSIDER_WHATSAPP.SEND_LOCATION.SAVE')
              "
              :disabled="isAlreadySaved || !selected.name.trim()"
              :is-loading="isSaving"
              data-location-save
              @click="saveSelected"
            />
            <NextButton
              type="button"
              size="sm"
              variant="faded"
              color="slate"
              icon="i-lucide-arrow-left"
              :label="t('OUTSIDER_WHATSAPP.SEND_LOCATION.CHANGE')"
              @click="selected = null"
            />
          </div>
        </div>
      </template>

      <template v-else>
        <div class="relative">
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 pointer-events-none size-4 left-3 top-1/2 text-n-slate-10"
          />
          <input
            v-model="query"
            type="search"
            :class="fieldClass"
            class="!pl-9"
            :placeholder="t('OUTSIDER_WHATSAPP.SEND_LOCATION.SEARCH')"
            data-location-search
            @keydown.enter.prevent
          />
        </div>

        <button
          type="button"
          :class="rowClass"
          class="text-n-teal-11"
          :disabled="isLocating"
          data-location-current
          @click="useCurrentPosition"
        >
          <span
            class="grid rounded-full size-8 place-content-center bg-n-teal-3 shrink-0"
          >
            <Icon
              :icon="
                isLocating
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-locate-fixed'
              "
              class="size-4"
            />
          </span>
          <span class="text-sm font-medium">
            {{ t('OUTSIDER_WHATSAPP.SEND_LOCATION.CURRENT') }}
          </span>
        </button>

        <div class="flex flex-col -mx-1 overflow-y-auto max-h-72">
          <template v-if="hasQuery">
            <p
              v-if="isSearching"
              class="px-2 py-3 mb-0 text-sm text-center text-n-slate-11"
            >
              {{ t('OUTSIDER_WHATSAPP.SEND_LOCATION.SEARCHING') }}
            </p>
            <p
              v-else-if="searchError"
              class="px-2 py-3 mb-0 text-sm text-center text-n-ruby-11"
            >
              {{ searchError }}
            </p>
            <p
              v-else-if="!results.length"
              class="px-2 py-3 mb-0 text-sm text-center text-n-slate-11"
            >
              {{ t('OUTSIDER_WHATSAPP.SEND_LOCATION.NO_RESULTS') }}
            </p>
            <template v-else>
              <button
                v-for="(item, index) in results"
                :key="`${index}-${item.latitude}-${item.longitude}`"
                type="button"
                :class="rowClass"
                data-location-result
                @click="choose(item)"
              >
                <Icon
                  icon="i-lucide-map-pin"
                  class="size-5 shrink-0 text-n-slate-10"
                />
                <span class="flex flex-col flex-1 min-w-0">
                  <span class="text-sm truncate text-n-slate-12">
                    {{ item.name || formatCoordinates(item) }}
                  </span>
                  <span class="text-xs line-clamp-2 text-n-slate-11">
                    {{ item.address || formatCoordinates(item) }}
                  </span>
                </span>
              </button>
            </template>
          </template>

          <template v-else>
            <span class="px-2 pb-1 text-xs font-medium text-n-slate-11">
              {{ t('OUTSIDER_WHATSAPP.SEND_LOCATION.SAVED_TITLE') }}
            </span>
            <p
              v-if="!saved.length"
              class="px-2 py-2 mb-0 text-sm text-n-slate-11"
            >
              {{
                canManage
                  ? t('OUTSIDER_WHATSAPP.SEND_LOCATION.SAVED_EMPTY_ADMIN')
                  : t('OUTSIDER_WHATSAPP.SEND_LOCATION.SAVED_EMPTY')
              }}
            </p>
            <div
              v-for="item in saved"
              :key="item.id"
              class="flex items-center gap-1 group"
              data-location-saved
            >
              <button
                type="button"
                :class="rowClass"
                class="flex-1 min-w-0"
                @click="choose(item)"
              >
                <Icon
                  icon="i-lucide-bookmark"
                  class="size-5 shrink-0 text-n-teal-10"
                />
                <span class="flex flex-col flex-1 min-w-0">
                  <span class="text-sm truncate text-n-slate-12">
                    {{ item.name }}
                  </span>
                  <span class="text-xs truncate text-n-slate-11">
                    {{ item.address || formatCoordinates(item) }}
                  </span>
                </span>
              </button>
              <button
                v-if="canManage"
                v-tooltip.top="t('OUTSIDER_WHATSAPP.SEND_LOCATION.REMOVE')"
                type="button"
                class="grid rounded-full size-8 place-content-center shrink-0 text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2"
                :aria-label="t('OUTSIDER_WHATSAPP.SEND_LOCATION.REMOVE')"
                data-location-remove
                @click="removeSaved(item)"
              >
                <Icon icon="i-lucide-trash-2" class="size-4" />
              </button>
            </div>
            <p class="px-2 pt-2 mb-0 text-xs text-n-slate-10">
              {{ t('OUTSIDER_WHATSAPP.SEND_LOCATION.HINT') }}
            </p>
          </template>
        </div>
      </template>
    </div>
  </Dialog>
</template>
