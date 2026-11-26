<script setup>
// OUTSIDER: Configurações > Google > Google Maps (só administrador): a chave do navegador para o Street View e o mapa
// dos locais (Maps Embed API, grátis), e o Map ID vetorial opcional da Vista 3D do Mapa dos agendamentos. Guardados
// na conta (Outsider::MapsSettings); "Testar" mostra um ponto com a chave.
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PlaceView from 'dashboard/components-next/outsider/maps/PlaceView.vue';
import MapsAPI from 'dashboard/api/outsider/maps';
import {
  loadMapsKey,
  mapsState,
  setMapsKey,
} from 'dashboard/helper/outsider/maps';

const { t } = useI18n();

// Praça Cívica, Goiânia: um ponto com Street View para o teste
const KEY_PLACEHOLDER = 'AIzaSy...';
const TEST_POINT = { latitude: -16.680882, longitude: -49.256374 };

const key = ref('');
const mapId = ref('');
const isSaving = ref(false);
const testing = ref(false);

onMounted(async () => {
  await loadMapsKey(true);
  key.value = mapsState.key || '';
  mapId.value = mapsState.mapId || '';
});

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await MapsAPI.saveSettings({
      key: key.value.trim(),
      map_id: mapId.value.trim(),
    });
    setMapsKey(data.key);
    mapsState.mapId = data.map_id || null;
    key.value = data.key || '';
    mapId.value = data.map_id || '';
    useAlert(
      data.key
        ? t('OUTSIDER_MAPS.SETTINGS.SAVED')
        : t('OUTSIDER_MAPS.SETTINGS.REMOVED')
    );
    testing.value = !!data.key;
  } catch (error) {
    const code = error?.response?.data?.error;
    const messages = {
      invalid_key: t('OUTSIDER_MAPS.ERRORS.INVALID_KEY'),
      invalid_map_id: t('OUTSIDER_MAPS.ERRORS.INVALID_MAP_ID'),
    };
    useAlert(messages[code] || t('OUTSIDER_MAPS.ERRORS.DEFAULT'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <section
    class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
    data-google-maps-settings
  >
    <div class="flex flex-wrap items-center gap-2">
      <Icon icon="i-lucide-map" class="size-5 text-n-slate-12" />
      <h3 class="mb-0 text-[15px] font-semibold text-n-slate-12">
        {{ t('OUTSIDER_MAPS.SETTINGS.TITLE') }}
      </h3>
      <span
        class="px-2 py-0.5 text-xs font-semibold rounded-full"
        :class="
          mapsState.key
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-amber-3 text-n-amber-11'
        "
      >
        {{
          mapsState.key
            ? t('OUTSIDER_MAPS.SETTINGS.READY')
            : t('OUTSIDER_MAPS.SETTINGS.MISSING')
        }}
      </span>
      <span class="ml-auto text-xs text-n-slate-10">
        {{ t('OUTSIDER_APPS.GSET.ADMINS_ONLY') }}
      </span>
    </div>
    <p class="mt-2 mb-3 text-sm text-n-slate-11">
      {{ t('OUTSIDER_MAPS.SETTINGS.TEXT') }}
    </p>
    <div class="grid gap-4 md:grid-cols-2">
      <form class="flex flex-col gap-2" @submit.prevent="save">
        <label class="flex flex-col gap-1 text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_MAPS.SETTINGS.KEY') }}
          <input
            v-model="key"
            type="text"
            autocomplete="off"
            spellcheck="false"
            class="!mb-0 font-mono text-sm"
            :placeholder="KEY_PLACEHOLDER"
            data-google-maps-key
          />
        </label>
        <label class="flex flex-col gap-1 text-xs font-medium text-n-slate-11">
          {{ t('OUTSIDER_MAPS.SETTINGS.MAP_ID') }}
          <input
            v-model="mapId"
            type="text"
            autocomplete="off"
            spellcheck="false"
            class="!mb-0 font-mono text-sm"
            data-google-maps-map-id
          />
          <span class="font-normal text-n-slate-10">
            {{ t('OUTSIDER_MAPS.SETTINGS.MAP_ID_HINT') }}
          </span>
        </label>
        <div class="flex gap-2">
          <button
            type="submit"
            class="oa-btn"
            :disabled="isSaving"
            data-google-maps-save
          >
            {{ t('OUTSIDER_MAPS.SETTINGS.SAVE') }}
          </button>
          <button
            v-if="mapsState.key"
            type="button"
            class="oa-ghost"
            data-google-maps-test
            @click="testing = !testing"
          >
            {{ t('OUTSIDER_MAPS.SETTINGS.TEST') }}
          </button>
        </div>
        <PlaceView
          v-if="testing && mapsState.key"
          :latitude="TEST_POINT.latitude"
          :longitude="TEST_POINT.longitude"
          :height="200"
          :links="false"
        />
        <p v-if="testing && mapsState.key" class="mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_MAPS.SETTINGS.TEST_HINT') }}
        </p>
      </form>
      <ol
        class="flex flex-col gap-1.5 p-3 mb-0 text-xs rounded-xl list-decimal list-inside bg-n-amber-2 text-n-amber-12"
      >
        <li>{{ t('OUTSIDER_MAPS.SETTINGS.STEP_1') }}</li>
        <li>{{ t('OUTSIDER_MAPS.SETTINGS.STEP_2') }}</li>
        <li>{{ t('OUTSIDER_MAPS.SETTINGS.STEP_3') }}</li>
        <li>{{ t('OUTSIDER_MAPS.SETTINGS.STEP_4') }}</li>
        <li>{{ t('OUTSIDER_MAPS.SETTINGS.STEP_5') }}</li>
      </ol>
    </div>
  </section>
</template>
