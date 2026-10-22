<script setup>
// OUTSIDER: bolha de localização estilo WhatsApp (ver helper/outsider/location.js): mapa com o
// pin, nome e endereço do lugar, e "Abrir no Maps" e "Waze" embaixo. Tocar no mapa abre o Maps.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from '../bubbles/Base.vue';
import Icon from 'next/icon/Icon.vue';
import LocationMap from './LocationMap.vue';
import { useMessageContext } from '../provider.js';
import {
  formatCoordinates,
  googleMapsUrl,
  locationOf,
  wazeUrl,
} from 'dashboard/helper/outsider/location';

const { content, contentAttributes } = useMessageContext();
const { t } = useI18n();

const place = computed(() =>
  locationOf({
    content: content.value,
    contentAttributes: contentAttributes.value,
  })
);
const title = computed(
  () => place.value.name || t('OUTSIDER_WHATSAPP.LOCATION_CARD.TITLE')
);
const subtitle = computed(
  () => place.value.address || formatCoordinates(place.value)
);
</script>

<template>
  <BaseBubble
    class="pt-1 pb-2 overflow-hidden w-72 max-w-full"
    data-bubble-name="location-card"
  >
    <p v-if="place.header" class="px-3 pt-1 pb-1 mb-0 font-semibold">
      {{ `${place.header}:` }}
    </p>
    <a
      :href="googleMapsUrl(place)"
      target="_blank"
      rel="noopener noreferrer"
      class="block mx-1 overflow-hidden rounded-lg"
      :aria-label="t('OUTSIDER_WHATSAPP.LOCATION_CARD.OPEN_MAPS')"
    >
      <LocationMap
        :latitude="place.latitude"
        :longitude="place.longitude"
        :width="280"
        :height="140"
      />
    </a>
    <div class="px-3 pt-2">
      <p class="mb-0 font-semibold break-words text-n-slate-12">
        {{ title }}
      </p>
      <p class="mb-0 text-xs break-words text-n-slate-11">
        {{ subtitle }}
      </p>
    </div>
    <div
      class="grid grid-cols-2 mt-2 border-t divide-x border-n-alpha-2 divide-n-alpha-2"
    >
      <a
        :href="googleMapsUrl(place)"
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center justify-center gap-1.5 py-2 text-sm font-medium text-n-teal-11 hover:bg-n-alpha-1 hover:underline-offset-0"
      >
        <Icon icon="i-lucide-map" class="size-4" />
        {{ t('OUTSIDER_WHATSAPP.LOCATION_CARD.OPEN_MAPS') }}
      </a>
      <a
        :href="wazeUrl(place)"
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center justify-center gap-1.5 py-2 text-sm font-medium text-n-teal-11 hover:bg-n-alpha-1"
      >
        <Icon icon="i-lucide-navigation" class="size-4" />
        {{ t('OUTSIDER_WHATSAPP.LOCATION_CARD.WAZE') }}
      </a>
    </div>
  </BaseBubble>
</template>
