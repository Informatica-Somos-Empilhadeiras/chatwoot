// OUTSIDER: Google Maps na agenda. A chave do navegador (Configurações > Google > Google Maps) é lida uma vez por
// conta e fica em memória; sem chave, os locais aparecem no mapa do OpenStreetMap (LocationMap.vue), sem Street View.
// Os quadros do Google são da Maps Embed API (grátis): Street View no ponto e o mapa de ruas visto de cima.
import { reactive } from 'vue';
import MapsAPI from 'dashboard/api/outsider/maps';

export const PLACES_CHANGED_EVENT = 'outsider_places_changed';

export const mapsState = reactive({
  loaded: false,
  key: null,
  mapId: null,
  canManage: false,
});

let pending = null;

export const loadMapsKey = (force = false) => {
  if (mapsState.loaded && !force) return Promise.resolve(mapsState.key);
  if (pending && !force) return pending;
  pending = MapsAPI.settings()
    .then(({ data }) => {
      mapsState.key = data.key || null;
      mapsState.mapId = data.map_id || null;
      mapsState.canManage = !!data.can_manage;
    })
    .catch(() => {
      mapsState.key = null;
    })
    .finally(() => {
      mapsState.loaded = true;
      pending = null;
    });
  return pending;
};

export const setMapsKey = key => {
  mapsState.key = key || null;
  mapsState.loaded = true;
};

const EMBED = 'https://www.google.com/maps/embed/v1';

// Street View no ponto (o Google acha a foto mais perto da rua); fov 80 = visão parecida com a do olho
export const streetViewUrl = ({ key, latitude, longitude }) =>
  `${EMBED}/streetview?key=${encodeURIComponent(key)}&location=${latitude},${longitude}&fov=80&language=pt-BR&region=BR`;

// mapa de ruas visto de cima com o pin (roadmap: sem satélite)
export const topMapUrl = ({ key, latitude, longitude, query }) => {
  const q =
    latitude !== null && latitude !== undefined
      ? `${latitude},${longitude}`
      : query;
  return `${EMBED}/place?key=${encodeURIComponent(key)}&q=${encodeURIComponent(q)}&zoom=18&maptype=roadmap&language=pt-BR&region=BR`;
};

export const hasPoint = place =>
  !!place &&
  Number.isFinite(Number(place.latitude)) &&
  Number.isFinite(Number(place.longitude)) &&
  place.latitude !== null &&
  place.longitude !== null;
