<script setup>
// OUTSIDER: editor da URA (Entrega 26), em tela cheia, no mesmo jeito do fluxograma do bot: blocos à esquerda,
// quadro com arrastar e zoom no meio e o bloco escolhido à direita (IvrInspector). Liga arrastando da bolinha de
// uma saída até outro bloco; clicar num bloco da lista cria ele ligado à primeira saída livre do bloco escolhido.
// No topo: nome, números em que a URA atende (nenhum = todos os que não têm URA própria), ligada/desligada e
// salvar (Ctrl+S). Delete apaga o bloco ou a seta escolhida.
import {
  ref,
  reactive,
  computed,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { vOnClickOutside } from '@vueuse/components';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IvrNodeCard from './IvrNodeCard.vue';
import IvrInspector from './IvrInspector.vue';
import {
  NODE_TYPES,
  PALETTE,
  NODE_WIDTH,
  HEADER_HEIGHT,
  MAX_NODES,
  nodeHeight,
  portsOf,
  portPoint,
  inputPoint,
  edgePath,
  makeNode,
  copyNode,
  newId,
  warningsOf,
} from './ivrNodes';
import { formatPhone } from '../format';
import { VOICE_ROUTE } from '../sections';

const MIN_SCALE = 0.3;
const MAX_SCALE = 1.6;
const GRID = 10;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const flowId = computed(() => route.params.flowId);
const isLoading = ref(true);
const loadFailed = ref(false);
const isSaving = ref(false);
const meta = reactive({ name: '', active: false, numbers: [] });
const graph = reactive({ nodes: [], edges: [] });
const audios = ref([]);
const options = ref({});
const savedSnapshot = ref('');
const selectedId = ref(null);
const selectedEdgeId = ref(null);
const numbersOpen = ref(false);

const viewport = ref(null);
const view = reactive({ x: 60, y: 60, scale: 1 });
const drag = ref(null);
const pointer = reactive({ x: 0, y: 0 });

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
const snap = value => Math.round(value / GRID) * GRID;
const snapshot = () => JSON.stringify({ meta, graph });
const isDirty = computed(
  () => !isLoading.value && snapshot() !== savedSnapshot.value
);

const nodesById = computed(() =>
  Object.fromEntries(graph.nodes.map(node => [node.id, node]))
);
const selectedNode = computed(() => nodesById.value[selectedId.value] || null);

// ---------- carregar e salvar ----------
const withDefaults = node => {
  const defaults = NODE_TYPES[node.type]?.defaults() || {};
  const data = { ...defaults, ...(node.data || {}) };
  if (node.type === 'hours') {
    data.hours = { ...defaults.hours, ...(node.data?.hours || {}) };
  }
  return { ...node, data };
};

const applyFlow = flow => {
  meta.name = flow.name || '';
  meta.active = !!flow.active;
  meta.numbers = [...(flow.numbers || [])];
  graph.nodes = (flow.graph?.nodes || [])
    .filter(node => NODE_TYPES[node.type])
    .map(withDefaults);
  graph.edges = flow.graph?.edges || [];
  audios.value = flow.audios || [];
  options.value = flow.options || {};
  savedSnapshot.value = snapshot();
  if (!nodesById.value[selectedId.value]) selectedId.value = null;
};

const validEdges = () =>
  graph.edges.filter(edge => {
    const from = nodesById.value[edge.from];
    return (
      from &&
      nodesById.value[edge.to] &&
      portsOf(from, t).some(port => port.id === edge.port)
    );
  });

const fitView = () => {
  const box = viewport.value?.getBoundingClientRect();
  if (!box || !graph.nodes.length) return;
  const minX = Math.min(...graph.nodes.map(node => node.x));
  const minY = Math.min(...graph.nodes.map(node => node.y));
  const maxX = Math.max(...graph.nodes.map(node => node.x + NODE_WIDTH));
  const maxY = Math.max(
    ...graph.nodes.map(node => node.y + nodeHeight(node, t))
  );
  const pad = 60;
  const scale = clamp(
    Math.min(
      (box.width - pad * 2) / Math.max(maxX - minX, 1),
      (box.height - pad * 2) / Math.max(maxY - minY, 1)
    ),
    MIN_SCALE,
    1
  );
  view.scale = scale;
  view.x = (box.width - (maxX - minX) * scale) / 2 - minX * scale;
  view.y =
    Math.max((box.height - (maxY - minY) * scale) / 2, pad) - minY * scale;
};

const load = async () => {
  isLoading.value = true;
  loadFailed.value = false;
  try {
    const { data } = await VoiceAPI.getIvrFlow(flowId.value);
    applyFlow(data);
  } catch {
    loadFailed.value = true;
  } finally {
    isLoading.value = false;
  }
  await nextTick();
  fitView();
};

const save = async () => {
  if (isSaving.value) return;
  if (!meta.name.trim()) {
    useAlert(t('OUTSIDER_VOICE.IVR.EDITOR.NAME_REQUIRED'));
    return;
  }
  isSaving.value = true;
  try {
    const { data } = await VoiceAPI.updateIvrFlow(flowId.value, {
      name: meta.name.trim(),
      active: meta.active,
      numbers: meta.numbers,
      graph: { nodes: graph.nodes, edges: validEdges() },
    });
    applyFlow(data);
    useAlert(t('OUTSIDER_VOICE.IVR.EDITOR.SAVED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('OUTSIDER_VOICE.IVR.EDITOR.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const goBack = () =>
  router.push({
    name: VOICE_ROUTE,
    params: { accountId: route.params.accountId, tab: 'ivr' },
  });

// ---------- números ----------
const numbersLabel = computed(() => {
  if (!meta.numbers.length) return t('OUTSIDER_VOICE.IVR.EDITOR.ALL_NUMBERS');
  if (meta.numbers.length === 1) return formatPhone(meta.numbers[0]);
  return t('OUTSIDER_VOICE.IVR.EDITOR.SOME_NUMBERS', {
    count: meta.numbers.length,
  });
});

const toggleNumber = number => {
  const index = meta.numbers.indexOf(number);
  if (index >= 0) meta.numbers.splice(index, 1);
  else meta.numbers.push(number);
};

// ---------- avisos ----------
const incoming = computed(
  () => new Set(graph.edges.map(edge => edge.to).filter(Boolean))
);
const warningsByNode = computed(() =>
  Object.fromEntries(
    graph.nodes.map(node => {
      const list = warningsOf(node, graph.edges, t);
      if (node.type !== 'start' && !incoming.value.has(node.id)) {
        list.push(t('OUTSIDER_VOICE.IVR.WARNINGS.NO_INPUT'));
      }
      return [node.id, list];
    })
  )
);
const warningCount = computed(
  () => Object.values(warningsByNode.value).filter(list => list.length).length
);
const connectedPorts = computed(() => {
  const map = {};
  graph.edges.forEach(edge => {
    (map[edge.from] ||= []).push(edge.port);
  });
  return map;
});

// ---------- quadro: coordenadas, zoom e arrastar ----------
const toCanvas = (clientX, clientY) => {
  const box = viewport.value.getBoundingClientRect();
  return {
    x: (clientX - box.left - view.x) / view.scale,
    y: (clientY - box.top - view.y) / view.scale,
  };
};

const zoomAt = (factor, clientX, clientY) => {
  const box = viewport.value.getBoundingClientRect();
  const px = (clientX ?? box.left + box.width / 2) - box.left;
  const py = (clientY ?? box.top + box.height / 2) - box.top;
  const next = clamp(view.scale * factor, MIN_SCALE, MAX_SCALE);
  view.x = px - (px - view.x) * (next / view.scale);
  view.y = py - (py - view.y) * (next / view.scale);
  view.scale = next;
};

const onWheel = event => {
  if (event.ctrlKey || event.metaKey) {
    zoomAt(event.deltaY < 0 ? 1.1 : 1 / 1.1, event.clientX, event.clientY);
    return;
  }
  view.x -= event.shiftKey ? event.deltaY : event.deltaX;
  view.y -= event.shiftKey ? 0 : event.deltaY;
};

const ensureVisible = node => {
  const box = viewport.value?.getBoundingClientRect();
  if (!box) return;
  const left = node.x * view.scale + view.x;
  const top = node.y * view.scale + view.y;
  const right = left + NODE_WIDTH * view.scale;
  const bottom = top + nodeHeight(node, t) * view.scale;
  if (left < 0 || top < 0 || right > box.width || bottom > box.height) {
    view.x = box.width / 2 - (node.x + NODE_WIDTH / 2) * view.scale;
    view.y = box.height / 3 - node.y * view.scale;
  }
};

const selectNode = id => {
  selectedId.value = id;
  selectedEdgeId.value = null;
};

const targetNodeAt = (clientX, clientY) => {
  const element = document
    .elementFromPoint(clientX, clientY)
    ?.closest('[data-node-id]');
  const node = nodesById.value[element?.dataset.nodeId];
  return node && node.type !== 'start' ? node.id : null;
};

const onNodeDragStart = (node, event) => {
  if (event.button !== 0) return;
  selectNode(node.id);
  drag.value = {
    kind: 'node',
    id: node.id,
    startX: event.clientX,
    startY: event.clientY,
    originX: node.x,
    originY: node.y,
  };
};

const onPortDown = (node, portId, event) => {
  const point = toCanvas(event.clientX, event.clientY);
  pointer.x = point.x;
  pointer.y = point.y;
  drag.value = { kind: 'connect', from: node.id, port: portId };
};

const onCanvasDown = event => {
  if (event.button !== 0 && event.button !== 1) return;
  selectedId.value = null;
  selectedEdgeId.value = null;
  numbersOpen.value = false;
  drag.value = {
    kind: 'pan',
    startX: event.clientX,
    startY: event.clientY,
    originX: view.x,
    originY: view.y,
  };
};

const connect = (from, port, to) => {
  graph.edges = graph.edges.filter(
    edge => !(edge.from === from && edge.port === port)
  );
  graph.edges.push({ id: newId('e'), from, port, to });
};

const onPointerMove = event => {
  const current = drag.value;
  if (!current) return;
  document.documentElement.classList.add('select-none');
  if (current.kind === 'node') {
    const node = nodesById.value[current.id];
    if (!node) return;
    node.x = snap(
      current.originX + (event.clientX - current.startX) / view.scale
    );
    node.y = snap(
      current.originY + (event.clientY - current.startY) / view.scale
    );
  } else if (current.kind === 'pan') {
    view.x = current.originX + event.clientX - current.startX;
    view.y = current.originY + event.clientY - current.startY;
  } else {
    const point = toCanvas(event.clientX, event.clientY);
    pointer.x = point.x;
    pointer.y = point.y;
  }
};

const onPointerUp = event => {
  const current = drag.value;
  drag.value = null;
  document.documentElement.classList.remove('select-none');
  if (current?.kind !== 'connect') return;
  const target = targetNodeAt(event.clientX, event.clientY);
  if (target && target !== current.from) {
    connect(current.from, current.port, target);
  }
};

// ---------- blocos ----------
const NEW_NODE_HEIGHT = 170;
const isTaken = (x, y) =>
  graph.nodes.some(
    node =>
      x < node.x + NODE_WIDTH + 20 &&
      x + NODE_WIDTH + 20 > node.x &&
      y < node.y + nodeHeight(node, t) + 20 &&
      y + NEW_NODE_HEIGHT > node.y
  );
const freeSpot = (x, y) => {
  let spotY = y;
  for (let tries = 0; tries < 60 && isTaken(x, spotY); tries += 1) {
    spotY += 40;
  }
  return spotY;
};

const addNode = type => {
  if (graph.nodes.length >= MAX_NODES) {
    useAlert(t('OUTSIDER_VOICE.IVR.EDITOR.TOO_MANY_NODES', { max: MAX_NODES }));
    return;
  }
  let x;
  let y;
  let from = null;
  const source = selectedNode.value;
  if (source) {
    const free = portsOf(source, t).find(
      port =>
        !graph.edges.some(
          edge => edge.from === source.id && edge.port === port.id
        )
    );
    x = source.x + NODE_WIDTH + 100;
    y = free ? portPoint(source, free.id, t).y - HEADER_HEIGHT / 2 : source.y;
    if (free) from = { from: source.id, port: free.id };
  } else {
    const box = viewport.value.getBoundingClientRect();
    const center = toCanvas(box.left + box.width / 2, box.top + box.height / 3);
    x = center.x - NODE_WIDTH / 2;
    y = center.y;
  }
  const node = makeNode(type, snap(x), snap(freeSpot(x, y)));
  graph.nodes.push(node);
  if (from) connect(from.from, from.port, node.id);
  selectNode(node.id);
  nextTick(() => ensureVisible(node));
};

const deleteNode = id => {
  const node = nodesById.value[id];
  if (!node || node.type === 'start') return;
  graph.nodes = graph.nodes.filter(item => item.id !== id);
  graph.edges = graph.edges.filter(edge => edge.from !== id && edge.to !== id);
  if (selectedId.value === id) selectedId.value = null;
};

const duplicateNode = id => {
  const node = nodesById.value[id];
  if (!node || node.type === 'start') return;
  const copy = copyNode(
    node,
    snap(node.x + 40),
    snap(freeSpot(node.x + 40, node.y + 40))
  );
  graph.nodes.push(copy);
  selectNode(copy.id);
};

const deleteEdge = id => {
  graph.edges = graph.edges.filter(edge => edge.id !== id);
  selectedEdgeId.value = null;
};

const onAudioUploaded = audio => {
  audios.value = [...audios.value, audio];
};

// ---------- setas ----------
const edgeViews = computed(() =>
  validEdges().map(edge => {
    const start = portPoint(nodesById.value[edge.from], edge.port, t);
    const end = inputPoint(nodesById.value[edge.to]);
    return {
      ...edge,
      path: edgePath(start, { x: end.x - 2, y: end.y }),
      mid: { x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 },
      active:
        edge.id === selectedEdgeId.value ||
        edge.from === selectedId.value ||
        edge.to === selectedId.value,
    };
  })
);

const draftPath = computed(() => {
  const current = drag.value;
  if (current?.kind !== 'connect') return '';
  const from = nodesById.value[current.from];
  return from ? edgePath(portPoint(from, current.port, t), pointer) : '';
});

const selectEdge = id => {
  selectedEdgeId.value = id;
  selectedId.value = null;
};

// ---------- teclado e saída ----------
const typing = event =>
  ['INPUT', 'TEXTAREA', 'SELECT'].includes(event.target?.tagName) ||
  event.target?.isContentEditable;

const onKeydown = event => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
    event.preventDefault();
    save();
    return;
  }
  if (typing(event) || !['Delete', 'Backspace'].includes(event.key)) return;
  if (selectedEdgeId.value) deleteEdge(selectedEdgeId.value);
  else if (selectedId.value) deleteNode(selectedId.value);
};

const onBeforeUnload = event => {
  if (!isDirty.value) return;
  event.preventDefault();
  event.returnValue = '';
};

onBeforeRouteLeave(() => {
  // eslint-disable-next-line no-alert
  return !isDirty.value || window.confirm(t('OUTSIDER_VOICE.IVR.EDITOR.LEAVE'));
});

onMounted(() => {
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp);
  window.addEventListener('keydown', onKeydown);
  window.addEventListener('beforeunload', onBeforeUnload);
  load();
});

onBeforeUnmount(() => {
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('pointerup', onPointerUp);
  window.removeEventListener('keydown', onKeydown);
  window.removeEventListener('beforeunload', onBeforeUnload);
  document.documentElement.classList.remove('select-none');
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex flex-wrap items-center gap-2 px-4 py-2.5 border-b border-n-weak bg-n-solid-2 shrink-0"
    >
      <Button
        sm
        ghost
        slate
        icon="i-lucide-arrow-left"
        :label="t('OUTSIDER_VOICE.IVR.EDITOR.BACK')"
        @click="goBack"
      />
      <input
        v-model="meta.name"
        maxlength="120"
        class="!mb-0 !h-9 !w-64 max-w-full font-medium"
        :placeholder="t('OUTSIDER_VOICE.IVR.EDITOR.NAME')"
        data-testid="ivr-name"
      />
      <div v-on-click-outside="() => (numbersOpen = false)" class="relative">
        <Button
          sm
          slate
          faded
          icon="i-lucide-phone"
          :label="numbersLabel"
          data-testid="ivr-numbers"
          @click="numbersOpen = !numbersOpen"
        />
        <div
          v-if="numbersOpen"
          class="absolute z-30 flex flex-col gap-1 p-2 mt-1 border shadow-lg w-72 rounded-xl border-n-weak bg-n-solid-2"
        >
          <span class="px-1 text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.IVR.EDITOR.NUMBERS_HINT') }}
          </span>
          <label
            v-for="row in options.numbers || []"
            :key="row.number"
            class="flex items-center gap-2 px-1 py-1 text-sm rounded-lg hover:bg-n-alpha-2 text-n-slate-12"
          >
            <input
              type="checkbox"
              class="!mb-0"
              :checked="meta.numbers.includes(row.number)"
              @change="toggleNumber(row.number)"
            />
            {{ formatPhone(row.number) }}
            <span class="text-xs text-n-slate-11">
              {{ [row.state, row.label].filter(Boolean).join(' · ') }}
            </span>
          </label>
          <p
            v-if="!(options.numbers || []).length"
            class="px-1 mb-0 text-xs text-n-slate-11"
          >
            {{ t('OUTSIDER_VOICE.IVR.EDITOR.NO_NUMBERS') }}
          </p>
        </div>
      </div>
      <label class="flex items-center gap-2 px-2 text-sm text-n-slate-12">
        <Switch v-model="meta.active" />
        {{
          meta.active
            ? t('OUTSIDER_VOICE.IVR.EDITOR.ACTIVE')
            : t('OUTSIDER_VOICE.IVR.EDITOR.INACTIVE')
        }}
      </label>
      <span class="flex items-center gap-2 ltr:ml-auto rtl:mr-auto">
        <span
          v-if="warningCount"
          class="flex items-center gap-1 text-xs text-n-amber-11"
        >
          <Icon icon="i-lucide-triangle-alert" class="size-4" />
          {{ t('OUTSIDER_VOICE.IVR.EDITOR.WARNINGS', { count: warningCount }) }}
        </span>
        <span v-if="isDirty" class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_VOICE.IVR.EDITOR.UNSAVED') }}
        </span>
        <Button
          sm
          icon="i-lucide-save"
          :label="t('OUTSIDER_VOICE.IVR.EDITOR.SAVE')"
          :is-loading="isSaving"
          :disabled="isLoading || loadFailed"
          data-testid="ivr-save"
          @click="save"
        />
      </span>
    </header>

    <div v-if="isLoading" class="flex items-center justify-center flex-1">
      <Spinner class="text-n-slate-10" />
    </div>
    <div
      v-else-if="loadFailed"
      class="flex flex-col items-center justify-center flex-1 gap-3"
    >
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_VOICE.IVR.EDITOR.LOAD_ERROR') }}
      </p>
      <Button sm :label="t('OUTSIDER_VOICE.IVR.EDITOR.RETRY')" @click="load" />
    </div>

    <div v-else class="flex flex-1 min-h-0">
      <!-- blocos -->
      <aside
        class="flex flex-col w-56 gap-4 p-3 overflow-y-auto border-r shrink-0 border-n-weak bg-n-solid-2"
      >
        <div
          v-for="group in PALETTE"
          :key="group.id"
          class="flex flex-col gap-1"
        >
          <span class="px-1 text-xs font-medium text-n-slate-11">
            {{ t(`OUTSIDER_VOICE.IVR.PALETTE.${group.id}`) }}
          </span>
          <button
            v-for="type in group.types"
            :key="type"
            type="button"
            class="flex items-start gap-2 p-2 text-left rounded-lg hover:bg-n-alpha-2"
            :data-testid="`ivr-palette-${type}`"
            @click="addNode(type)"
          >
            <span
              class="flex items-center justify-center rounded-md size-7 shrink-0"
              :class="NODE_TYPES[type].soft"
            >
              <Icon :icon="NODE_TYPES[type].icon" class="size-4" />
            </span>
            <span class="flex flex-col min-w-0">
              <span class="text-sm text-n-slate-12">
                {{ t(`OUTSIDER_VOICE.IVR.TYPES.${type}`) }}
              </span>
              <span class="text-xs text-n-slate-11 line-clamp-2">
                {{ t(`OUTSIDER_VOICE.IVR.HINTS.${type}`) }}
              </span>
            </span>
          </button>
        </div>
        <p class="px-1 mb-0 text-xs text-n-slate-10">
          {{ t('OUTSIDER_VOICE.IVR.PALETTE.HINT') }}
        </p>
      </aside>

      <!-- quadro -->
      <div
        ref="viewport"
        class="relative flex-1 min-w-0 overflow-hidden select-none touch-none bg-n-alpha-1"
        :class="drag?.kind === 'pan' ? 'cursor-grabbing' : 'cursor-grab'"
        data-ivr-canvas
        @pointerdown="onCanvasDown"
        @wheel.prevent="onWheel"
      >
        <div
          class="absolute top-0 left-0 origin-top-left"
          :style="{
            transform: `translate(${view.x}px, ${view.y}px) scale(${view.scale})`,
          }"
        >
          <svg
            class="absolute overflow-visible pointer-events-none"
            width="1"
            height="1"
          >
            <g v-for="edge in edgeViews" :key="edge.id">
              <path
                :d="edge.path"
                fill="none"
                stroke="transparent"
                stroke-width="14"
                class="pointer-events-auto cursor-pointer"
                @pointerdown.stop="selectEdge(edge.id)"
              />
              <path
                :d="edge.path"
                fill="none"
                :stroke-width="edge.active ? 2.5 : 1.75"
                :class="edge.active ? 'stroke-n-brand' : 'stroke-n-slate-8'"
              />
              <g
                v-if="edge.id === selectedEdgeId"
                class="cursor-pointer pointer-events-auto"
                @pointerdown.stop="deleteEdge(edge.id)"
              >
                <circle
                  :cx="edge.mid.x"
                  :cy="edge.mid.y"
                  r="10"
                  class="fill-n-ruby-9"
                />
                <path
                  :d="`M ${edge.mid.x - 4} ${edge.mid.y - 4} L ${edge.mid.x + 4} ${edge.mid.y + 4} M ${edge.mid.x + 4} ${edge.mid.y - 4} L ${edge.mid.x - 4} ${edge.mid.y + 4}`"
                  stroke="white"
                  stroke-width="2"
                />
              </g>
            </g>
            <path
              v-if="draftPath"
              :d="draftPath"
              fill="none"
              stroke-width="2"
              stroke-dasharray="6 4"
              class="stroke-n-brand"
            />
          </svg>
          <IvrNodeCard
            v-for="node in graph.nodes"
            :key="node.id"
            :node="node"
            :selected="node.id === selectedId"
            :connecting="drag?.kind === 'connect'"
            :warnings="warningsByNode[node.id]"
            :connected-ports="connectedPorts[node.id] || []"
            :options="options"
            @select="selectNode"
            @drag-start="onNodeDragStart(node, $event)"
            @port-down="(port, event) => onPortDown(node, port, event)"
          />
        </div>
        <div
          class="absolute flex gap-1 p-1 border shadow-sm bottom-3 ltr:left-3 rtl:right-3 rounded-xl border-n-weak bg-n-solid-2"
          @pointerdown.stop
        >
          <Button
            xs
            ghost
            slate
            icon="i-lucide-zoom-out"
            @click="zoomAt(1 / 1.2)"
          />
          <Button xs ghost slate icon="i-lucide-zoom-in" @click="zoomAt(1.2)" />
          <Button
            xs
            ghost
            slate
            icon="i-lucide-maximize"
            :title="t('OUTSIDER_VOICE.IVR.EDITOR.FIT')"
            @click="fitView"
          />
        </div>
      </div>

      <IvrInspector
        v-if="selectedNode"
        :key="selectedNode.id"
        :node="selectedNode"
        :edges="graph.edges"
        :flow-id="flowId"
        :audios="audios"
        :options="options"
        @close="selectedId = null"
        @delete="deleteNode(selectedNode.id)"
        @duplicate="duplicateNode(selectedNode.id)"
        @audio-uploaded="onAudioUploaded"
      />
    </div>
  </section>
</template>
