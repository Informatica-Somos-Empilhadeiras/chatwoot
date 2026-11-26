<script setup>
// OUTSIDER: o local em Street View (primeiro) com o botão para o mapa de ruas visto de cima, nos quadros do Google
// Maps (helper/outsider/maps.js). Sem a chave do Maps, mostra o mapa do OpenStreetMap com o pin. Sem coordenadas, só o
// endereço: aí não há Street View, só o mapa do endereço.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import LocationMap from 'dashboard/components-next/message/outsider/LocationMap.vue';
import {
  mapsState,
  loadMapsKey,
  streetViewUrl,
  topMapUrl,
  hasPoint,
} from 'dashboard/helper/outsider/maps';
import { googleMapsUrl, wazeUrl } from 'dashboard/helper/outsider/location';

const props = defineProps({
  latitude: { type: Number, default: null },
  longitude: { type: Number, default: null },
  // endereço em texto, para quando não há coordenadas (eventos marcados fora do Chatwoot)
  query: { type: String, default: '' },
  height: { type: Number, default: 180 },
  links: { type: Boolean, default: true },
});

const { t } = useI18n();

const withPoint = computed(() => hasPoint(props));
const mode = ref('street');

watch(
  () => [props.latitude, props.longitude],
  () => {
    mode.value = 'street';
  }
);

onMounted(() => loadMapsKey());

const current = computed(() => (withPoint.value ? mode.value : 'map'));

const src = computed(() => {
  if (!mapsState.key) return '';
  const place = {
    key: mapsState.key,
    latitude: withPoint.value ? props.latitude : null,
    longitude: withPoint.value ? props.longitude : null,
    query: props.query,
  };
  return current.value === 'street' ? streetViewUrl(place) : topMapUrl(place);
});

const mapsLink = computed(() =>
  withPoint.value
    ? googleMapsUrl(props)
    : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(props.query)}`
);

const tabClass = active =>
  active ? 'bg-n-brand text-white' : 'bg-white text-[#333333] hover:bg-black/5';
</script>

<template>
  <div class="flex flex-col gap-2" data-place-view>
    <div
      class="relative w-full overflow-hidden rounded-lg border border-n-weak bg-n-alpha-1"
      :style="{ height: `${height}px` }"
    >
      <iframe
        v-if="src"
        :key="src"
        :src="src"
        class="absolute inset-0 w-full h-full border-0"
        loading="lazy"
        allowfullscreen
        referrerpolicy="no-referrer-when-downgrade"
        :title="t('OUTSIDER_MAPS.VIEW.TITLE')"
        data-place-embed
      />
      <LocationMap
        v-else-if="withPoint && mapsState.loaded"
        :latitude="latitude"
        :longitude="longitude"
        :width="560"
        :height="height"
        :zoom="17"
        class="!w-full"
      />
      <div
        v-else-if="mapsState.loaded"
        class="grid h-full p-3 text-xs text-center place-content-center text-n-slate-11"
      >
        {{ t('OUTSIDER_MAPS.VIEW.NO_KEY') }}
      </div>
      <div
        v-if="src && withPoint"
        class="absolute flex overflow-hidden text-xs font-medium border rounded-md shadow-sm top-2 ltr:left-2 rtl:right-2 border-black/10"
      >
        <button
          type="button"
          class="!px-2.5 !py-1 rounded-none"
          :class="tabClass(current === 'street')"
          data-place-street
          @click="mode = 'street'"
        >
          {{ t('OUTSIDER_MAPS.VIEW.STREET') }}
        </button>
        <button
          type="button"
          class="!px-2.5 !py-1 rounded-none"
          :class="tabClass(current === 'map')"
          data-place-map
          @click="mode = 'map'"
        >
          {{ t('OUTSIDER_MAPS.VIEW.MAP') }}
        </button>
      </div>
    </div>
    <p
      v-if="!src && withPoint && mapsState.loaded"
      class="mb-0 text-[11px] text-n-slate-10"
    >
      {{ t('OUTSIDER_MAPS.VIEW.NO_KEY_HINT') }}
    </p>
    <div v-if="links" class="flex flex-wrap items-center gap-1.5">
      <a
        :href="mapsLink"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium border rounded-md border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
      >
        <Icon icon="i-lucide-map" class="size-3.5" />
        {{ t('OUTSIDER_MAPS.VIEW.OPEN_MAPS') }}
      </a>
      <a
        v-if="withPoint"
        :href="wazeUrl({ latitude, longitude })"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium border rounded-md border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
      >
        <Icon icon="i-lucide-navigation" class="size-3.5" />
        {{ t('OUTSIDER_MAPS.VIEW.WAZE') }}
      </a>
      <slot name="actions" />
    </div>
  </div>
</template>
