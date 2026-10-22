<script setup>
// OUTSIDER: mapa pequeno com o pin no meio, montado com os pedaços (tiles) do OpenStreetMap,
// sem biblioteca de mapa. Se as imagens não carregarem (sem internet, bloqueio), fica um fundo
// verde com o pin, como a localização do WhatsApp sem prévia. Os pedaços ficam presos ao meio do
// quadro: se ele ficar mais estreito que width, o mapa só corta dos lados e o pin segue no ponto.
import { computed, ref, watch } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { mapTiles } from 'dashboard/helper/outsider/location';

const props = defineProps({
  latitude: { type: Number, required: true },
  longitude: { type: Number, required: true },
  width: { type: Number, default: 288 },
  height: { type: Number, default: 144 },
  zoom: { type: Number, default: 16 },
});

// crédito exigido pelo uso dos mapas do OpenStreetMap
const ATTRIBUTION = '© OpenStreetMap';

const failed = ref(false);

const tiles = computed(() =>
  mapTiles({
    latitude: props.latitude,
    longitude: props.longitude,
    width: props.width,
    height: props.height,
    zoom: props.zoom,
  })
);

watch(
  () => [props.latitude, props.longitude],
  () => {
    failed.value = false;
  }
);
</script>

<template>
  <div
    class="relative max-w-full overflow-hidden bg-[#0D9B8A]/15 select-none"
    :style="{ width: `${width}px`, height: `${height}px` }"
    data-location-map
  >
    <template v-if="!failed">
      <img
        v-for="tile in tiles"
        :key="tile.key"
        :src="tile.url"
        alt=""
        width="256"
        height="256"
        draggable="false"
        loading="lazy"
        referrerpolicy="strict-origin-when-cross-origin"
        class="absolute max-w-none pointer-events-none size-64"
        :style="{
          left: `calc(50% + ${tile.left - width / 2}px)`,
          top: `${tile.top}px`,
        }"
        @error="failed = true"
      />
    </template>
    <div
      v-else
      class="absolute inset-0 bg-gradient-to-br from-[#0D9B8A]/30 to-[#0D9B8A]/10"
    />
    <Icon
      icon="i-ph-map-pin-fill"
      class="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-full size-8 text-[#E5484D] drop-shadow-[0_1px_1px_rgba(0,0,0,0.45)]"
    />
    <span
      v-if="!failed"
      class="absolute bottom-0 right-0 px-1 text-[9px] leading-[14px] text-[#333333] bg-[#ffffffb3]"
    >
      {{ ATTRIBUTION }}
    </span>
  </div>
</template>
