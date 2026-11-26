<script setup>
// OUTSIDER (Maps): "Mapa dos agendamentos" (Aplicativos > Google). Mapa de ruas do Google (Maps JavaScript API, sem
// satélite) com um pin por cliente com OS agendada no período (Outsider::Erp::ScheduleMap); de longe os pins se juntam
// num círculo com o número (helper/outsider/scheduleMap.js#clusterize). Tocar no pin abre os agendamentos dele e enche
// as laterais: ficha do cliente e contatos (esquerda), máquinas e OS abertas (direita). "Vista 3D" inclina e gira o mapa
// (precisa do Map ID vetorial nas Configurações). "Ver rota" (só quando aperta) liga os clientes do dia na ordem do
// horário, um caminho por técnico, traçado pelo Google (Directions); as OS sem hora entram onde menos aumentam o caminho.
// Tocar numa máquina ou OS abre o painel lateral do ERP por cima do mapa (sem sair da tela). Mapa sempre claro.
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MapsAPI from 'dashboard/api/outsider/maps';
import { loadMapsKey, mapsState } from 'dashboard/helper/outsider/maps';
import {
  loadGoogleMaps,
  clusterize,
  orderStops,
} from 'dashboard/helper/outsider/scheduleMap';
import { googleMapsUrl } from 'dashboard/helper/outsider/location';
import AppLogo from '../AppLogo.vue';
import MapClientSheet from './MapClientSheet.vue';
import MapClientAssets from './MapClientAssets.vue';
import ErpRecordPanel from '../../erp/records/ErpRecordPanel.vue';
import ErpRentalPanel from '../../erp/rentals/ErpRentalPanel.vue';
import '../apps.css';

const { t } = useI18n();
const route = useRoute();

const ROUTE_COLORS = [
  '#1F6FEB',
  '#E5484D',
  '#12A594',
  '#F76B15',
  '#8E4EC6',
  '#0090FF',
];
const CENTER = { lat: -16.6869, lng: -49.2648 }; // Goiânia, até os pontos chegarem
const MAX_RETRIES = 10;

const pad = value => String(value).padStart(2, '0');
const dayKey = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const addDays = (date, days) => {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
};
const brDay = value => {
  const [, m, d] = String(value || '')
    .slice(0, 10)
    .split('-');
  return d ? `${d}/${m}` : '';
};
const timeZone =
  Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Sao_Paulo';

const period = ref('week');
const from = ref(dayKey(new Date()));
const to = ref(dayKey(addDays(new Date(), 7)));
const technician = ref('');
const data = ref(null);
const isLoading = ref(false);
const failure = ref('');
const selected = ref(null); // { company, code }
const clientInfo = ref(null);
const clientLoading = ref(false);
const panel = ref(null); // { kind: 'orders' | 'machines', company, number }
const is3d = ref(false);
const routeOn = ref(false);
const routeDay = ref('');
const routeLegs = ref([]);
const routeLoading = ref(false);
const mapRef = ref(null);
const mapReady = ref(false);

let maps = null;
let map = null;
let markers = [];
let infoWindow = null;
let renderers = [];
let retries = 0;
let retryTimer = null;

const clients = computed(() => data.value?.clients || []);
const missing = computed(() => data.value?.missing || []);
const scheduleCount = computed(() =>
  [...clients.value, ...missing.value].reduce(
    (sum, client) => sum + client.schedules.length,
    0
  )
);
const days = computed(() => {
  const set = new Set();
  clients.value.forEach(client =>
    client.schedules.forEach(row => set.add(row.start.slice(0, 10)))
  );
  return [...set].sort();
});

const setPeriod = value => {
  period.value = value;
  const today = new Date();
  if (value === 'today') {
    from.value = dayKey(today);
    to.value = dayKey(today);
  } else if (value === 'week') {
    from.value = dayKey(today);
    to.value = dayKey(addDays(today, 7));
  } else if (value === 'month') {
    from.value = dayKey(today);
    to.value = dayKey(addDays(today, 30));
  }
};

const load = async ({ quiet = false } = {}) => {
  clearTimeout(retryTimer);
  if (!quiet) {
    isLoading.value = true;
    retries = 0;
  }
  failure.value = '';
  try {
    const { data: body } = await MapsAPI.scheduleMap({
      from: from.value,
      to: to.value,
      technician: technician.value || undefined,
      time_zone: timeZone,
    });
    data.value = body;
    if (body.pending > 0 && retries < MAX_RETRIES) {
      retries += 1;
      retryTimer = setTimeout(() => load({ quiet: true }), 2500);
    }
  } catch (error) {
    const code = error?.response?.data?.error;
    failure.value =
      code === 'erp_forbidden'
        ? t('OUTSIDER_MAPS.MAP.FORBIDDEN')
        : t('OUTSIDER_MAPS.MAP.LOAD_FAILED');
  } finally {
    isLoading.value = false;
  }
};

// ---------- mapa ----------
const pinIcon = (color, label = '') => ({
  url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="30" height="40" viewBox="0 0 30 40"><path d="M15 1C7.3 1 1 7.2 1 14.9 1 25.4 15 39 15 39s14-13.6 14-24.1C29 7.2 22.7 1 15 1z" fill="${color}" stroke="#fff" stroke-width="2"/><circle cx="15" cy="15" r="${label ? 9 : 5}" fill="#fff"/>${label ? `<text x="15" y="19" font-size="11" font-family="Arial" font-weight="700" text-anchor="middle" fill="${color}">${label}</text>` : ''}</svg>`
  )}`,
  scaledSize: new maps.Size(30, 40),
  anchor: new maps.Point(15, 40),
});

const clusterIcon = count => {
  const size = Math.min(64, 34 + Math.log2(count) * 7);
  return {
    url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${size / 2}" fill="#1F6FEB" fill-opacity=".25"/><circle cx="${size / 2}" cy="${size / 2}" r="${size / 2 - 6}" fill="#1F6FEB"/><text x="50%" y="50%" dy=".35em" font-size="13" font-family="Arial" font-weight="800" text-anchor="middle" fill="#fff">${count}</text></svg>`
    )}`,
    scaledSize: new maps.Size(size, size),
    anchor: new maps.Point(size / 2, size / 2),
  };
};

const toPixel = point => {
  const projection = map.getProjection();
  const scale = 2 ** map.getZoom();
  const world = projection.fromLatLngToPoint(
    new maps.LatLng(point.latitude, point.longitude)
  );
  return { x: world.x * scale, y: world.y * scale };
};

const clearMarkers = () => {
  markers.forEach(marker => marker.setMap(null));
  markers = [];
};

const brTime = row =>
  row.all_day
    ? t('OUTSIDER_MAPS.MAP.NO_TIME')
    : `${row.start.slice(11, 16)}${row.end ? `–${row.end.slice(11, 16)}` : ''}`;

// conteúdo da janela do pin montado com textContent (nada do ERP vira HTML)
const infoContent = client => {
  const box = document.createElement('div');
  box.style.cssText =
    'font: 13px/1.4 Arial, sans-serif; max-width: 260px; color: #1c2024';
  const title = document.createElement('b');
  title.textContent = client.name || '';
  box.appendChild(title);
  client.schedules.slice(0, 5).forEach(row => {
    const line = document.createElement('div');
    line.style.color = '#60646c';
    line.textContent = [
      t('OUTSIDER_MAPS.MAP.ORDER', { code: row.order }),
      row.kind,
      `${brDay(row.start)} ${brTime(row)}`,
      row.technician,
    ]
      .filter(Boolean)
      .join(' · ');
    box.appendChild(line);
  });
  const address = document.createElement('div');
  address.style.color = '#60646c';
  address.textContent = [client.place_name, client.city]
    .filter(Boolean)
    .join(' - ');
  box.appendChild(address);
  if (client.approximate) {
    const warn = document.createElement('div');
    warn.style.cssText = 'color:#8a5a00;font-size:11px;margin-top:4px';
    warn.textContent = t('OUTSIDER_MAPS.MAP.APPROXIMATE');
    box.appendChild(warn);
  }
  const links = document.createElement('div');
  links.style.cssText = 'display:flex;gap:10px;margin-top:6px;font-weight:600';
  const first = client.schedules[0];
  [
    [
      t('OUTSIDER_MAPS.MAP.OPEN_ORDER'),
      `/app/accounts/${route.params.accountId}/erp/os?open=${client.company}:${first.order}`,
    ],
    [t('OUTSIDER_MAPS.VIEW.OPEN_MAPS'), googleMapsUrl(client)],
    [
      t('OUTSIDER_MAPS.VIEW.STREET'),
      `https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${client.latitude},${client.longitude}`,
    ],
  ].forEach(([label, href]) => {
    const link = document.createElement('a');
    link.textContent = label;
    link.href = href;
    link.style.color = '#1f6feb';
    if (href.startsWith('/')) {
      // "Abrir OS": o painel lateral do ERP, sem sair do mapa
      link.addEventListener('click', event => {
        event.preventDefault();
        panel.value = {
          kind: 'orders',
          company: String(client.company),
          number: Number(first.order),
        };
      });
    } else {
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
    }
    links.appendChild(link);
  });
  box.appendChild(links);
  return box;
};

const selectClient = async client => {
  selected.value = { company: client.company, code: client.code };
  clientInfo.value = null;
  panel.value = null;
  clientLoading.value = true;
  try {
    const { data: body } = await MapsAPI.mapClient(client.company, client.code);
    clientInfo.value = { ...body, name: client.name };
  } catch {
    clientInfo.value = { error: true, name: client.name };
  } finally {
    clientLoading.value = false;
  }
};

const closeClient = () => {
  selected.value = null;
  clientInfo.value = null;
  panel.value = null;
  infoWindow?.close();
};

const openClient = (client, marker) => {
  infoWindow.setContent(infoContent(client));
  infoWindow.open({ map, anchor: marker });
  selectClient(client);
};

const drawMarkers = () => {
  if (!map || !map.getProjection()) return;
  clearMarkers();
  clusterize(clients.value, toPixel).forEach(group => {
    const position = { lat: group.latitude, lng: group.longitude };
    if (group.points.length > 1) {
      const marker = new maps.Marker({
        map,
        position,
        icon: clusterIcon(group.points.length),
        zIndex: 1000 + group.points.length,
        title: t('OUTSIDER_MAPS.MAP.CLUSTER', { count: group.points.length }),
      });
      marker.addListener('click', () => {
        const bounds = new maps.LatLngBounds();
        group.points.forEach(p =>
          bounds.extend({ lat: p.latitude, lng: p.longitude })
        );
        map.fitBounds(bounds, 80);
      });
      markers.push(marker);
      return;
    }
    const client = group.points[0];
    const marker = new maps.Marker({
      map,
      position,
      icon: pinIcon(client.approximate ? '#F76B15' : '#E5484D'),
      title: client.name,
    });
    marker.addListener('click', () => openClient(client, marker));
    markers.push(marker);
  });
};

const fitAll = () => {
  if (!map || !clients.value.length) return;
  const bounds = new maps.LatLngBounds();
  clients.value.forEach(c =>
    bounds.extend({ lat: c.latitude, lng: c.longitude })
  );
  if (clients.value.length === 1) {
    map.setCenter(bounds.getCenter());
    map.setZoom(16);
  } else map.fitBounds(bounds, 60);
};

const initMap = async () => {
  await loadMapsKey();
  if (!mapsState.key) return;
  try {
    maps = await loadGoogleMaps(mapsState.key);
  } catch {
    failure.value = t('OUTSIDER_MAPS.MAP.MAPS_FAILED');
    return;
  }
  await nextTick();
  map = new maps.Map(mapRef.value, {
    center: CENTER,
    zoom: 11,
    mapTypeId: 'roadmap',
    mapTypeControl: false,
    streetViewControl: true,
    fullscreenControl: true,
    clickableIcons: false,
    // o Map ID vetorial segue o tema escuro do computador; o mapa fica sempre claro
    colorScheme: maps.ColorScheme?.LIGHT || 'LIGHT',
    ...(mapsState.mapId ? { mapId: mapsState.mapId } : {}),
  });
  infoWindow = new maps.InfoWindow();
  map.addListener('idle', drawMarkers);
  mapReady.value = true;
  drawMarkers();
  fitAll();
};

// ---------- Vista 3D ----------
const toggle3d = () => {
  is3d.value = !is3d.value;
  if (!map) return;
  if (is3d.value && map.getZoom() < 16) map.setZoom(17);
  map.setTilt(is3d.value ? 67.5 : 0);
  map.setHeading(is3d.value ? 30 : 0);
};
const rotate = () => map?.setHeading(((map.getHeading() || 0) + 45) % 360);

// ---------- rota ----------
const clearRoute = () => {
  renderers.forEach(renderer => renderer.setMap(null));
  renderers = [];
  routeLegs.value = [];
};

const stopsOf = day =>
  clients.value.flatMap(client =>
    client.schedules
      .filter(row => row.start.slice(0, 10) === day)
      .map(row => ({
        ...row,
        client,
        latitude: client.latitude,
        longitude: client.longitude,
      }))
  );

const drawRoute = async () => {
  clearRoute();
  if (!map || !routeDay.value) return;
  routeLoading.value = true;
  const groups = {};
  stopsOf(routeDay.value).forEach(stop => {
    const key = stop.technician || t('OUTSIDER_MAPS.MAP.NO_TECHNICIAN');
    (groups[key] ||= []).push(stop);
  });
  const service = new maps.DirectionsService();
  const results = await Promise.all(
    Object.entries(groups).map(async ([name, stops], index) => {
      const ordered = orderStops(stops);
      const color = ROUTE_COLORS[index % ROUTE_COLORS.length];
      if (ordered.length < 2)
        return { name, color, stops: ordered, legs: [], error: '' };
      const point = stop => ({ lat: stop.latitude, lng: stop.longitude });
      try {
        const result = await service.route({
          origin: point(ordered[0]),
          destination: point(ordered[ordered.length - 1]),
          waypoints: ordered
            .slice(1, -1)
            .slice(0, 23)
            .map(stop => ({ location: point(stop), stopover: true })),
          optimizeWaypoints: false,
          travelMode: maps.TravelMode.DRIVING,
        });
        const renderer = new maps.DirectionsRenderer({
          map,
          directions: result,
          suppressMarkers: true,
          preserveViewport: true,
          polylineOptions: {
            strokeColor: color,
            strokeWeight: 5,
            strokeOpacity: 0.85,
          },
        });
        renderers.push(renderer);
        return {
          name,
          color,
          stops: ordered,
          legs: result.routes[0].legs,
          error: '',
        };
      } catch {
        return {
          name,
          color,
          stops: ordered,
          legs: [],
          error: t('OUTSIDER_MAPS.MAP.ROUTE_FAILED'),
        };
      }
    })
  );
  // números das paradas em cima dos pins
  results.forEach(group =>
    group.stops.forEach((stop, index) => {
      const marker = new maps.Marker({
        map,
        position: { lat: stop.latitude, lng: stop.longitude },
        icon: pinIcon(group.color, String(index + 1)),
        zIndex: 3000,
        title: stop.client.name,
      });
      marker.addListener('click', () => openClient(stop.client, marker));
      renderers.push(marker);
    })
  );
  routeLegs.value = results;
  routeLoading.value = false;
};

const toggleRoute = () => {
  routeOn.value = !routeOn.value;
  if (!routeOn.value) {
    clearRoute();
    drawMarkers();
    return;
  }
  if (!days.value.includes(routeDay.value)) [routeDay.value] = days.value;
  clearMarkers();
  drawRoute();
};

const legText = leg =>
  leg ? `${leg.distance?.text || ''} · ${leg.duration?.text || ''}` : '';
const totalOf = group => {
  const meters = group.legs.reduce(
    (sum, leg) => sum + (leg.distance?.value || 0),
    0
  );
  const seconds = group.legs.reduce(
    (sum, leg) => sum + (leg.duration?.value || 0),
    0
  );
  return t('OUTSIDER_MAPS.MAP.ROUTE_TOTAL', {
    km: (meters / 1000).toFixed(1).replace('.', ','),
    min: Math.round(seconds / 60),
  });
};

watch(routeDay, () => routeOn.value && drawRoute());
watch(clients, () => {
  if (routeOn.value) drawRoute();
  else drawMarkers();
});
watch([from, to, technician], () => {
  routeOn.value = false;
  clearRoute();
  load();
});
watch(
  () => data.value && !isLoading.value,
  ready => ready && fitAll()
);

onMounted(() => {
  load();
  initMap();
});
onBeforeUnmount(() => {
  clearTimeout(retryTimer);
  clearRoute();
  clearMarkers();
});

const chip = active =>
  active
    ? 'bg-n-brand text-white outline-n-brand'
    : 'bg-n-solid-1 text-n-slate-12 outline-n-weak hover:bg-n-alpha-1';
</script>

<template>
  <section
    class="oapps flex flex-col w-full h-full min-h-0 bg-n-surface-1"
    data-schedule-map
  >
    <header
      class="flex flex-wrap items-center gap-2 px-4 py-2.5 border-b border-n-weak"
    >
      <AppLogo name="gmaps" :size="22" />
      <h2 class="mb-0 mr-2 text-base font-semibold text-n-slate-12">
        {{ t('OUTSIDER_MAPS.MAP.TITLE') }}
      </h2>
      <button
        v-for="item in ['today', 'week', 'month', 'custom']"
        :key="item"
        type="button"
        class="!px-3 !py-1 text-xs font-semibold rounded-full outline outline-1 -outline-offset-1"
        :class="chip(period === item)"
        :data-map-period="item"
        @click="setPeriod(item)"
      >
        {{ t(`OUTSIDER_MAPS.MAP.PERIOD.${item.toUpperCase()}`) }}
      </button>
      <template v-if="period === 'custom'">
        <input v-model="from" type="date" class="!mb-0 !h-8 !w-auto text-xs" />
        <input v-model="to" type="date" class="!mb-0 !h-8 !w-auto text-xs" />
      </template>
      <select
        v-model="technician"
        class="!mb-0 !h-8 !w-auto text-xs pl-2.5 !pr-8 bg-[right_-1.25rem_center]"
        data-map-technician
      >
        <option value="">{{ t('OUTSIDER_MAPS.MAP.ALL_TECHNICIANS') }}</option>
        <option
          v-for="name in data?.technicians || []"
          :key="name"
          :value="name"
        >
          {{ name }}
        </option>
      </select>
      <span class="flex-1" />
      <span v-if="data" class="text-xs text-n-slate-11">
        {{
          t('OUTSIDER_MAPS.MAP.COUNT', {
            schedules: scheduleCount,
            clients: clients.length + missing.length,
          })
        }}
      </span>
      <button
        v-if="mapsState.mapId && mapReady"
        type="button"
        class="oa-ghost !h-9"
        :class="{ '!bg-n-alpha-2': is3d }"
        data-map-3d
        @click="toggle3d"
      >
        <Icon icon="i-lucide-box" class="size-4" />
        {{ t('OUTSIDER_MAPS.MAP.VIEW_3D') }}
      </button>
      <button
        v-if="is3d"
        v-tooltip.bottom="t('OUTSIDER_MAPS.MAP.ROTATE')"
        type="button"
        class="oa-ghost !h-9"
        :aria-label="t('OUTSIDER_MAPS.MAP.ROTATE')"
        @click="rotate"
      >
        <Icon icon="i-lucide-rotate-cw" class="size-4" />
      </button>
      <button
        type="button"
        class="inline-flex items-center gap-2 !h-10 !px-4 text-sm font-bold rounded-xl shadow-sm"
        :class="
          routeOn
            ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
            : 'bg-n-teal-9 text-white hover:bg-n-teal-10'
        "
        :disabled="!mapReady || !clients.length"
        data-map-route
        @click="toggleRoute"
      >
        <Icon
          :icon="routeOn ? 'i-lucide-x' : 'i-lucide-route'"
          class="size-5"
        />
        {{
          routeOn
            ? t('OUTSIDER_MAPS.MAP.ROUTE_HIDE')
            : t('OUTSIDER_MAPS.MAP.ROUTE_SHOW')
        }}
      </button>
    </header>

    <div class="flex flex-col flex-1 min-h-0 lg:flex-row">
      <!-- esquerda: ficha do cliente e contatos -->
      <aside
        class="order-2 lg:order-1 w-full lg:w-[320px] shrink-0 p-4 overflow-y-auto border-t lg:border-t-0 lg:border-r border-n-weak max-h-[45vh] lg:max-h-none"
        data-map-left
      >
        <button
          v-if="selected"
          type="button"
          class="flex items-center gap-1.5 !px-2 !py-1 mb-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
          data-map-back
          @click="closeClient"
        >
          <Icon icon="i-lucide-arrow-left" class="size-4" />
          {{ t('OUTSIDER_MAPS.MAP.BACK') }}
        </button>
        <div v-if="clientLoading" class="flex justify-center py-6">
          <Spinner class="text-n-slate-10" />
        </div>
        <template v-else-if="clientInfo && !clientInfo.error">
          <MapClientSheet :info="clientInfo" @saved="selectClient(selected)" />
        </template>
        <p v-else-if="clientInfo?.error" class="text-sm text-n-ruby-11">
          {{ t('OUTSIDER_MAPS.MAP.CLIENT_FAILED') }}
        </p>
        <template v-else>
          <p class="mb-2 text-sm text-n-slate-11">
            {{ t('OUTSIDER_MAPS.MAP.PICK_HINT') }}
          </p>
          <button
            v-for="client in clients"
            :key="`${client.company}-${client.code}`"
            type="button"
            class="flex flex-col w-full gap-0.5 !px-2 !py-1.5 mb-1 text-left rounded-lg hover:bg-n-alpha-1"
            data-map-client-row
            @click="
              selectClient(client);
              map?.panTo({ lat: client.latitude, lng: client.longitude });
            "
          >
            <span class="text-sm font-medium text-n-slate-12">{{
              client.name
            }}</span>
            <span class="text-xs text-n-slate-11">
              {{
                [
                  `${brDay(client.schedules[0].start)} ${brTime(client.schedules[0])}`,
                  client.city,
                ]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </button>
          <template v-if="missing.length">
            <p class="mt-3 mb-1 text-xs font-semibold text-n-amber-11">
              {{
                t('OUTSIDER_MAPS.MAP.MISSING_TITLE', { count: missing.length })
              }}
            </p>
            <button
              v-for="client in missing"
              :key="`m-${client.company}-${client.code}`"
              type="button"
              class="flex flex-col w-full !px-2 !py-1 text-left rounded-lg hover:bg-n-alpha-1"
              @click="selectClient(client)"
            >
              <span class="text-sm text-n-slate-12">{{ client.name }}</span>
              <span class="text-xs text-n-slate-10">{{ client.city }}</span>
            </button>
            <p class="mt-1 mb-0 text-[11px] text-n-slate-10">
              {{
                data?.pending
                  ? t('OUTSIDER_MAPS.MAP.LOCATING', { count: data.pending })
                  : t('OUTSIDER_MAPS.MAP.MISSING_HINT')
              }}
            </p>
          </template>
        </template>
      </aside>

      <!-- mapa -->
      <div class="relative flex-1 order-1 min-h-[50vh] lg:order-2 lg:min-h-0">
        <!-- o Google põe position: relative no div do mapa: por isso o mapa fica dentro de uma caixa absoluta -->
        <div class="absolute inset-0 z-0">
          <div ref="mapRef" class="w-full h-full" data-map-canvas />
        </div>
        <div
          v-if="mapsState.loaded && !mapsState.key"
          class="absolute inset-0 grid p-6 text-sm text-center place-content-center bg-n-solid-2 text-n-slate-11"
        >
          {{ t('OUTSIDER_MAPS.MAP.NO_KEY') }}
        </div>
        <div
          v-if="isLoading"
          class="absolute z-10 flex items-center gap-2 px-3 py-1 text-xs -translate-x-1/2 rounded-full shadow top-2 left-1/2 bg-n-surface-1 text-n-slate-11"
        >
          <Spinner :size="12" /> {{ t('OUTSIDER_APPS.LOADING') }}
        </div>
        <p
          v-if="failure"
          class="absolute z-10 px-3 py-2 m-0 text-sm -translate-x-1/2 rounded-lg shadow top-2 left-1/2 bg-n-surface-1 text-n-ruby-11"
        >
          {{ failure }}
        </p>
        <!-- painel da rota -->
        <div
          v-if="routeOn"
          class="absolute z-10 flex flex-col gap-2 p-3 overflow-y-auto shadow-lg left-3 bottom-3 rounded-xl bg-n-surface-1 w-[300px] max-h-[60%]"
          data-map-route-panel
        >
          <div class="flex items-center gap-2">
            <Icon icon="i-lucide-route" class="size-4 text-n-teal-11" />
            <b class="text-sm text-n-slate-12">{{
              t('OUTSIDER_MAPS.MAP.ROUTE_OF')
            }}</b>
            <select
              v-model="routeDay"
              class="!mb-0 !h-7 !w-auto text-xs pl-2 !pr-7 bg-[right_-1.25rem_center]"
            >
              <option v-for="day in days" :key="day" :value="day">
                {{ brDay(day) }}
              </option>
            </select>
            <Spinner v-if="routeLoading" :size="12" />
          </div>
          <div
            v-for="group in routeLegs"
            :key="group.name"
            class="flex flex-col gap-1"
          >
            <span
              class="flex items-center gap-1.5 text-xs font-semibold text-n-slate-12"
            >
              <span
                class="inline-block w-3 h-3 rounded-full"
                :style="{ background: group.color }"
              />
              {{ group.name }}
              <span
                v-if="group.legs.length"
                class="font-normal text-n-slate-11"
              >
                {{ totalOf(group) }}
              </span>
            </span>
            <ol class="pl-5 mb-0 text-xs list-decimal text-n-slate-11">
              <li
                v-for="(stop, index) in group.stops"
                :key="`${stop.order}-${index}`"
              >
                <b class="text-n-slate-12">{{ brTime(stop) }}</b>
                {{
                  `${stop.client.name} · ${t('OUTSIDER_MAPS.MAP.ORDER', { code: stop.order })}`
                }}
                <span
                  v-if="index > 0 && group.legs[index - 1]"
                  class="block text-[11px] text-n-slate-10"
                >
                  {{
                    t('OUTSIDER_MAPS.MAP.LEG', {
                      text: legText(group.legs[index - 1]),
                    })
                  }}
                </span>
              </li>
            </ol>
            <p v-if="group.error" class="mb-0 text-xs text-n-ruby-11">
              {{ group.error }}
            </p>
          </div>
          <p class="mb-0 text-[11px] text-n-slate-10">
            {{ t('OUTSIDER_MAPS.MAP.ROUTE_HINT') }}
          </p>
        </div>
      </div>

      <!-- direita: máquinas e OS abertas -->
      <aside
        class="order-3 w-full lg:w-[300px] shrink-0 p-4 overflow-y-auto border-t lg:border-t-0 lg:border-l border-n-weak max-h-[45vh] lg:max-h-none"
        data-map-right
      >
        <MapClientAssets
          v-if="clientInfo && !clientInfo.error"
          :info="clientInfo"
          @open="panel = $event"
        />
        <p v-else class="mb-0 text-sm text-n-slate-10">
          {{ t('OUTSIDER_MAPS.MAP.ASSETS_EMPTY') }}
        </p>
      </aside>
    </div>
    <ErpRecordPanel
      v-if="panel?.kind === 'orders'"
      :key="`o:${panel.company}:${panel.number}`"
      kind="orders"
      :company="panel.company"
      :number="panel.number"
      floating
      @close="panel = null"
    />
    <div
      v-else-if="panel"
      :key="`m:${panel.company}:${panel.number}`"
      class="fixed inset-y-0 right-0 z-50 flex xl:pt-4 xl:pr-4 bg-n-background xl:shadow-xl"
      data-map-machine-panel
    >
      <ErpRentalPanel
        kind="machines"
        :company="panel.company"
        :number="panel.number"
        @close="panel = null"
      />
    </div>
  </section>
</template>
