<script setup>
// OUTSIDER: editor de fluxograma do bot (Configurações > Automação por bot > um fluxo). Quadro com
// arrastar e zoom, blocos (BotNodeCard) ligados por setas, painel do bloco escolhido (BotInspector)
// e o Testar (BotSimulator). Liga arrastando da bolinha de uma saída até outro bloco; soltar no vazio
// abre a lista de blocos para criar um já ligado. Ctrl+Z desfaz, Delete apaga, Ctrl+S salva.
import {
  ref,
  reactive,
  computed,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { vOnClickOutside } from '@vueuse/components';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import BotFlowsAPI from 'dashboard/api/outsider/botFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BotNodeCard from './BotNodeCard.vue';
import BotInspector from './BotInspector.vue';
import BotSimulator from './BotSimulator.vue';
import {
  NODE_TYPES,
  PALETTE,
  NODE_WIDTH,
  HEADER_HEIGHT,
  nodeHeight,
  portsOf,
  portPoint,
  inputPoint,
  edgePath,
  makeNode,
  newId,
  warningsOf,
} from './nodeTypes';

const MAX_NODES = 200;
const MIN_SCALE = 0.3;
const MAX_SCALE = 1.6;
const GRID = 10;
const HISTORY_LIMIT = 40;

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');

const flowId = computed(() => route.params.flowId);
const isLoading = ref(true);
const loadFailed = ref(false);
const isSaving = ref(false);
const meta = reactive({ name: '', active: false, inbox_ids: [] });
const graph = reactive({ nodes: [], edges: [] });
const savedSnapshot = ref('');

const selectedId = ref(null);
const selectedEdgeId = ref(null);
const testing = ref(false);
const simulatingId = ref(null);
const inboxMenuOpen = ref(false);
const quickAdd = ref(null);

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

// ---------- desfazer / refazer ----------
const history = { past: [], future: [], last: '' };
const canUndo = ref(false);
const canRedo = ref(false);
let historyTimer = null;
const graphJson = () => JSON.stringify(graph);
const syncHistoryFlags = () => {
  canUndo.value = history.past.length > 0;
  canRedo.value = history.future.length > 0;
};
const record = () => {
  clearTimeout(historyTimer);
  const now = graphJson();
  if (now === history.last) return;
  history.past.push(history.last);
  if (history.past.length > HISTORY_LIMIT) history.past.shift();
  history.future = [];
  history.last = now;
  syncHistoryFlags();
};
watch(
  graph,
  () => {
    clearTimeout(historyTimer);
    historyTimer = setTimeout(record, 400);
  },
  { deep: true }
);
const applyGraph = json => {
  const parsed = JSON.parse(json);
  graph.nodes = parsed.nodes;
  graph.edges = parsed.edges;
  history.last = json;
  if (!nodesById.value[selectedId.value]) selectedId.value = null;
  syncHistoryFlags();
};
const undo = () => {
  record();
  if (!history.past.length) return;
  history.future.push(history.last);
  applyGraph(history.past.pop());
};
const redo = () => {
  record();
  if (!history.future.length) return;
  history.past.push(history.last);
  applyGraph(history.future.pop());
};

// ---------- carregar e salvar ----------
const withDefaults = node => {
  const defaults = NODE_TYPES[node.type]?.defaults() || {};
  const data = { ...defaults, ...(node.data || {}) };
  if (node.type === 'condition') {
    data.hours = { ...defaults.hours, ...(node.data?.hours || {}) };
  }
  return { ...node, data };
};

const applyFlow = flow => {
  meta.name = flow.name || '';
  meta.active = !!flow.active;
  meta.inbox_ids = [...(flow.inbox_ids || [])];
  graph.nodes = (flow.graph?.nodes || [])
    .filter(node => NODE_TYPES[node.type])
    .map(withDefaults);
  graph.edges = flow.graph?.edges || [];
  clearTimeout(historyTimer);
  history.last = graphJson();
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
    const { data } = await BotFlowsAPI.show(flowId.value);
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
    useAlert(t('OUTSIDER_TOOLS.BOT.EDITOR.NAME_REQUIRED'));
    return;
  }
  isSaving.value = true;
  try {
    const { data } = await BotFlowsAPI.update(flowId.value, {
      name: meta.name.trim(),
      active: meta.active,
      inbox_ids: meta.inbox_ids,
      graph: { nodes: graph.nodes, edges: validEdges() },
    });
    applyFlow(data);
    useAlert(t('OUTSIDER_TOOLS.BOT.EDITOR.SAVED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('OUTSIDER_TOOLS.BOT.EDITOR.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const goBack = () => router.push({ name: 'outsider_bot_flows' });

// ---------- avisos ----------
const incoming = computed(
  () => new Set(graph.edges.map(edge => edge.to).filter(Boolean))
);
const warningsByNode = computed(() =>
  Object.fromEntries(
    graph.nodes.map(node => {
      const list = warningsOf(node, graph.edges, t);
      if (node.type !== 'start' && !incoming.value.has(node.id)) {
        list.push(t('OUTSIDER_TOOLS.BOT.WARNINGS.NO_INPUT'));
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

const centerOn = node => {
  const box = viewport.value?.getBoundingClientRect();
  if (!box) return;
  view.x = box.width / 2 - (node.x + NODE_WIDTH / 2) * view.scale;
  view.y = box.height / 3 - node.y * view.scale;
};

const ensureVisible = node => {
  const box = viewport.value?.getBoundingClientRect();
  if (!box) return;
  const left = node.x * view.scale + view.x;
  const top = node.y * view.scale + view.y;
  const right = left + NODE_WIDTH * view.scale;
  const bottom = top + nodeHeight(node, t) * view.scale;
  if (left < 0 || top < 0 || right > box.width || bottom > box.height) {
    centerOn(node);
  }
};

const selectNode = id => {
  selectedId.value = id;
  selectedEdgeId.value = null;
  quickAdd.value = null;
};

const selectAndShow = id => {
  selectNode(id);
  nextTick(() => {
    const node = nodesById.value[id];
    if (node) ensureVisible(node);
  });
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
  quickAdd.value = null;
  drag.value = { kind: 'connect', from: node.id, port: portId, hover: null };
};

const onCanvasDown = event => {
  if (event.button !== 0 && event.button !== 1) return;
  selectedId.value = null;
  selectedEdgeId.value = null;
  quickAdd.value = null;
  inboxMenuOpen.value = false;
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
  // sem selecionar texto da tela enquanto arrasta
  document.documentElement.classList.add('select-none');
  if (current.kind === 'node') {
    const node = nodesById.value[current.id];
    if (!node) return;
    current.moved = true;
    node.x = snap(
      current.originX + (event.clientX - current.startX) / view.scale
    );
    node.y = snap(
      current.originY + (event.clientY - current.startY) / view.scale
    );
  } else if (current.kind === 'pan') {
    view.x = current.originX + event.clientX - current.startX;
    view.y = current.originY + event.clientY - current.startY;
  } else if (current.kind === 'connect') {
    const point = toCanvas(event.clientX, event.clientY);
    pointer.x = point.x;
    pointer.y = point.y;
    current.hover = targetNodeAt(event.clientX, event.clientY);
  }
};

const onPointerUp = event => {
  const current = drag.value;
  drag.value = null;
  document.documentElement.classList.remove('select-none');
  // clique no bloco (sem arrastar): o painel da direita abre e o bloco não pode ficar atrás dele
  if (current?.kind === 'node' && !current.moved) {
    nextTick(() => {
      const node = nodesById.value[current.id];
      if (node) ensureVisible(node);
    });
  }
  if (current?.kind !== 'connect') return;
  const target = targetNodeAt(event.clientX, event.clientY);
  if (target && target !== current.from) {
    connect(current.from, current.port, target);
    return;
  }
  const overCanvas = event.target?.closest?.('[data-bot-canvas]');
  if (!target && overCanvas) {
    const box = viewport.value.getBoundingClientRect();
    const point = toCanvas(event.clientX, event.clientY);
    quickAdd.value = {
      from: current.from,
      port: current.port,
      x: point.x,
      y: point.y,
      left: clamp(event.clientX - box.left, 8, box.width - 216),
      top: clamp(event.clientY - box.top, 8, box.height - 330),
    };
  }
};

// ---------- blocos ----------
// lugar livre para um bloco novo: desce até não ficar em cima de outro bloco
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

const addNode = (type, at = null, link = null) => {
  if (graph.nodes.length >= MAX_NODES) {
    useAlert(t('OUTSIDER_TOOLS.BOT.EDITOR.TOO_MANY_NODES', { max: MAX_NODES }));
    return null;
  }
  let x;
  let y;
  let from = link;
  if (at) {
    x = at.x;
    y = at.y - HEADER_HEIGHT / 2;
  } else if (selectedNode.value) {
    const source = selectedNode.value;
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
  return node;
};

const addFromQuickMenu = type => {
  const spot = quickAdd.value;
  quickAdd.value = null;
  if (!spot) return;
  addNode(
    type,
    { x: spot.x + 20, y: spot.y },
    { from: spot.from, port: spot.port }
  );
};

const onPaletteDragStart = (type, event) => {
  event.dataTransfer.setData('text/x-outsider-bot', type);
  event.dataTransfer.effectAllowed = 'copy';
};

const onDrop = event => {
  const type = event.dataTransfer.getData('text/x-outsider-bot');
  if (!NODE_TYPES[type]) return;
  const point = toCanvas(event.clientX, event.clientY);
  addNode(type, { x: point.x - NODE_WIDTH / 2, y: point.y });
};

const deleteNode = id => {
  const node = nodesById.value[id];
  if (!node) return;
  if (node.type === 'start') {
    useAlert(t('OUTSIDER_TOOLS.BOT.EDITOR.START_LOCKED'));
    return;
  }
  graph.nodes = graph.nodes.filter(item => item.id !== id);
  graph.edges = graph.edges.filter(edge => edge.from !== id && edge.to !== id);
  if (selectedId.value === id) selectedId.value = null;
};

const duplicateNode = id => {
  const node = nodesById.value[id];
  if (!node || node.type === 'start') return;
  const copy = JSON.parse(JSON.stringify(node));
  copy.id = newId(node.type);
  copy.x = snap(node.x + 40);
  copy.y = snap(freeSpot(node.x + 40, node.y + 40));
  (copy.data.options || []).forEach(option => {
    option.id = newId('opt');
  });
  (copy.data.routes || []).forEach(item => {
    item.id = newId('rt');
  });
  graph.nodes.push(copy);
  selectNode(copy.id);
};

const deleteEdge = id => {
  graph.edges = graph.edges.filter(edge => edge.id !== id);
  selectedEdgeId.value = null;
};

// organiza em colunas a partir do Início, na ordem das saídas
const tidy = ({ keepSaved = false } = {}) => {
  const start = graph.nodes.find(node => node.type === 'start');
  if (!start) return;
  const depth = { [start.id]: 0 };
  const queue = [start.id];
  for (let index = 0; index < queue.length; index += 1) {
    const node = nodesById.value[queue[index]];
    portsOf(node, t).forEach(port => {
      const edge = graph.edges.find(
        item => item.from === node.id && item.port === port.id
      );
      if (edge && nodesById.value[edge.to] && depth[edge.to] === undefined) {
        depth[edge.to] = depth[node.id] + 1;
        queue.push(edge.to);
      }
    });
  }
  const maxDepth = Math.max(...Object.values(depth));
  graph.nodes.forEach(node => {
    if (depth[node.id] === undefined) {
      depth[node.id] = maxDepth + 1;
      queue.push(node.id);
    }
  });
  const columns = {};
  queue.forEach(id => {
    (columns[depth[id]] ||= []).push(nodesById.value[id]);
  });
  const heights = Object.values(columns).map(column =>
    column.reduce((sum, node) => sum + nodeHeight(node, t) + 40, -40)
  );
  const tallest = Math.max(...heights);
  Object.entries(columns).forEach(([column, nodes], index) => {
    let y = 40 + (tallest - heights[index]) / 2;
    nodes.forEach(node => {
      node.x = 40 + Number(column) * (NODE_WIDTH + 120);
      node.y = snap(y);
      y += nodeHeight(node, t) + 40;
    });
  });
  if (keepSaved) {
    clearTimeout(historyTimer);
    history.last = graphJson();
    savedSnapshot.value = snapshot();
  }
  nextTick(fitView);
};

// fluxo criado fora do editor (sem posições): blocos uns sobre os outros
const overlapping = () => {
  const spots = new Set(graph.nodes.map(node => `${node.x}:${node.y}`));
  return graph.nodes.length > 1 && spots.size < graph.nodes.length;
};

// ---------- setas ----------
const edgeViews = computed(() =>
  validEdges().map(edge => {
    const from = nodesById.value[edge.from];
    const to = nodesById.value[edge.to];
    const start = portPoint(from, edge.port, t);
    const end = inputPoint(to);
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
  if (!from) return '';
  return edgePath(portPoint(from, current.port, t), pointer);
});

const selectEdge = id => {
  selectedEdgeId.value = id;
  selectedId.value = null;
  quickAdd.value = null;
};

// ---------- caixas ----------
const inboxLabel = computed(() => {
  if (!meta.inbox_ids.length) return t('OUTSIDER_TOOLS.BOT.EDITOR.ALL_INBOXES');
  if (meta.inbox_ids.length === 1) {
    return (
      inboxes.value.find(inbox => inbox.id === meta.inbox_ids[0])?.name ||
      t('OUTSIDER_TOOLS.BOT.EDITOR.INBOX_COUNT', { count: 1 })
    );
  }
  return t('OUTSIDER_TOOLS.BOT.EDITOR.INBOX_COUNT', {
    count: meta.inbox_ids.length,
  });
});
const toggleInbox = id => {
  meta.inbox_ids = meta.inbox_ids.includes(id)
    ? meta.inbox_ids.filter(item => item !== id)
    : [...meta.inbox_ids, id];
};

const firstWarning = () => {
  const node = graph.nodes.find(item => warningsByNode.value[item.id]?.length);
  if (!node) return;
  testing.value = false;
  selectNode(node.id);
  centerOn(node);
};

// ---------- teclado e saída ----------
const isTyping = target =>
  ['INPUT', 'TEXTAREA', 'SELECT'].includes(target?.tagName) ||
  target?.isContentEditable;

const onKeydown = event => {
  const mod = event.ctrlKey || event.metaKey;
  if (mod && event.key.toLowerCase() === 's') {
    event.preventDefault();
    save();
    return;
  }
  if (isTyping(event.target)) return;
  if (mod && event.key.toLowerCase() === 'z') {
    event.preventDefault();
    if (event.shiftKey) redo();
    else undo();
  } else if (mod && event.key.toLowerCase() === 'y') {
    event.preventDefault();
    redo();
  } else if (event.key === 'Delete' || event.key === 'Backspace') {
    if (selectedEdgeId.value) deleteEdge(selectedEdgeId.value);
    else if (selectedId.value) deleteNode(selectedId.value);
  } else if (event.key === 'Escape') {
    quickAdd.value = null;
    selectedEdgeId.value = null;
    selectedId.value = null;
  }
};

const onBeforeUnload = event => {
  if (!isDirty.value) return;
  event.preventDefault();
  // eslint-disable-next-line no-param-reassign
  event.returnValue = '';
};

onBeforeRouteLeave(() => {
  if (
    isDirty.value &&
    !window.confirm(t('OUTSIDER_TOOLS.BOT.EDITOR.LEAVE_CONFIRM'))
  ) {
    return false;
  }
  return true;
});

onMounted(async () => {
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp);
  window.addEventListener('keydown', onKeydown);
  window.addEventListener('beforeunload', onBeforeUnload);
  store.dispatch('teams/get');
  store.dispatch('agents/get');
  store.dispatch('labels/get');
  await load();
  if (overlapping()) tidy({ keepSaved: true });
});

onBeforeUnmount(() => {
  clearTimeout(historyTimer);
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('pointerup', onPointerUp);
  window.removeEventListener('keydown', onKeydown);
  window.removeEventListener('beforeunload', onBeforeUnload);
});

const canvasStyle = computed(() => ({
  transform: `translate(${view.x}px, ${view.y}px) scale(${view.scale})`,
}));
const gridStyle = computed(() => ({
  backgroundImage:
    'radial-gradient(rgb(var(--slate-7)) 1px, transparent 1.2px)',
  backgroundSize: `${20 * view.scale}px ${20 * view.scale}px`,
  backgroundPosition: `${view.x}px ${view.y}px`,
}));
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <!-- barra de cima -->
    <header
      class="flex flex-wrap items-center gap-2 px-4 py-2.5 border-b border-n-weak bg-n-solid-1"
    >
      <Button
        v-tooltip.bottom="t('OUTSIDER_TOOLS.BOT.EDITOR.BACK')"
        icon="i-lucide-arrow-left"
        sm
        ghost
        slate
        @click="goBack"
      />
      <input
        v-model="meta.name"
        maxlength="120"
        class="!mb-0 !h-9 !w-64 max-w-full !border-transparent hover:!border-n-weak focus:!border-n-brand text-base font-semibold !bg-transparent"
        :placeholder="t('OUTSIDER_TOOLS.BOT.EDITOR.NAME_PLACEHOLDER')"
      />
      <div v-on-click-outside="() => (inboxMenuOpen = false)" class="relative">
        <Button
          :label="inboxLabel"
          icon="i-lucide-inbox"
          sm
          faded
          slate
          @click="inboxMenuOpen = !inboxMenuOpen"
        />
        <div
          v-if="inboxMenuOpen"
          class="absolute left-0 z-50 flex flex-col w-72 gap-1 p-2 mt-1 border rounded-xl top-full bg-n-solid-2 border-n-weak shadow-lg"
        >
          <span class="px-2 py-1 text-xs text-n-slate-11">
            {{ t('OUTSIDER_TOOLS.BOT.EDITOR.INBOXES_HINT') }}
          </span>
          <div class="flex flex-col max-h-72 overflow-y-auto">
            <label
              v-for="inbox in inboxes"
              :key="inbox.id"
              class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-lg cursor-pointer hover:bg-n-alpha-1 text-n-slate-12"
            >
              <input
                type="checkbox"
                class="!mb-0"
                :checked="meta.inbox_ids.includes(inbox.id)"
                @change="toggleInbox(inbox.id)"
              />
              <span class="truncate">{{ inbox.name }}</span>
            </label>
          </div>
        </div>
      </div>
      <label
        class="flex items-center gap-2 px-2 text-sm cursor-pointer text-n-slate-12"
      >
        <Switch v-model="meta.active" />
        {{
          meta.active
            ? t('OUTSIDER_TOOLS.BOT.EDITOR.ACTIVE')
            : t('OUTSIDER_TOOLS.BOT.EDITOR.INACTIVE')
        }}
      </label>

      <div class="flex items-center gap-1.5 ml-auto">
        <button
          v-if="warningCount"
          type="button"
          class="flex items-center gap-1 px-2 py-1 text-xs rounded-lg bg-n-amber-3 text-n-amber-11 hover:opacity-80"
          @click="firstWarning"
        >
          <Icon icon="i-lucide-triangle-alert" class="size-3.5" />
          {{
            t(
              'OUTSIDER_TOOLS.BOT.EDITOR.WARNINGS',
              { count: warningCount },
              warningCount
            )
          }}
        </button>
        <Button
          v-tooltip.bottom="t('OUTSIDER_TOOLS.BOT.EDITOR.UNDO')"
          icon="i-lucide-undo-2"
          sm
          ghost
          slate
          :disabled="!canUndo"
          @click="undo"
        />
        <Button
          v-tooltip.bottom="t('OUTSIDER_TOOLS.BOT.EDITOR.REDO')"
          icon="i-lucide-redo-2"
          sm
          ghost
          slate
          :disabled="!canRedo"
          @click="redo"
        />
        <Button
          :label="t('OUTSIDER_TOOLS.BOT.EDITOR.TIDY')"
          icon="i-lucide-layout-grid"
          sm
          faded
          slate
          @click="tidy()"
        />
        <Button
          :label="t('OUTSIDER_TOOLS.BOT.EDITOR.TEST')"
          icon="i-lucide-flask-conical"
          sm
          faded
          teal
          @click="testing = !testing"
        />
        <Button
          :label="
            isDirty
              ? t('OUTSIDER_TOOLS.BOT.EDITOR.SAVE')
              : t('OUTSIDER_TOOLS.BOT.EDITOR.SAVED_SHORT')
          "
          icon="i-lucide-save"
          sm
          :is-loading="isSaving"
          :disabled="!isDirty || isSaving"
          @click="save"
        />
      </div>
    </header>

    <div v-if="isLoading" class="flex items-center justify-center flex-1">
      <Spinner />
    </div>
    <div
      v-else-if="loadFailed"
      class="flex flex-col items-center justify-center flex-1 gap-3 text-sm text-n-slate-11"
    >
      {{ t('OUTSIDER_TOOLS.BOT.EDITOR.LOAD_ERROR') }}
      <Button
        :label="t('OUTSIDER_TOOLS.BOT.EDITOR.RETRY')"
        sm
        faded
        @click="load"
      />
    </div>

    <div v-else class="flex flex-1 min-h-0">
      <!-- blocos para adicionar -->
      <aside
        class="flex flex-col w-52 gap-1.5 p-3 overflow-y-auto border-r shrink-0 border-n-weak bg-n-solid-1"
      >
        <span class="px-1 text-xs font-medium uppercase text-n-slate-10">
          {{ t('OUTSIDER_TOOLS.BOT.EDITOR.PALETTE') }}
        </span>
        <button
          v-for="type in PALETTE"
          :key="type"
          type="button"
          draggable="true"
          class="flex items-center gap-2 px-2 py-2 text-left border rounded-lg cursor-grab border-n-weak hover:bg-n-alpha-1 hover:border-n-slate-6"
          @dragstart="onPaletteDragStart(type, $event)"
          @click="addNode(type)"
        >
          <span
            class="flex items-center justify-center rounded-md size-7 shrink-0 text-white"
            :class="NODE_TYPES[type].color"
          >
            <Icon :icon="NODE_TYPES[type].icon" class="size-4" />
          </span>
          <span class="flex flex-col min-w-0">
            <span class="text-sm text-n-slate-12">
              {{ t(`OUTSIDER_TOOLS.BOT.TYPES.${type}`) }}
            </span>
            <span class="text-[11px] leading-tight text-n-slate-10">
              {{ t(`OUTSIDER_TOOLS.BOT.TYPE_HINTS.${type}`) }}
            </span>
          </span>
        </button>
        <p class="px-1 mt-2 text-[11px] leading-snug text-n-slate-10">
          {{ t('OUTSIDER_TOOLS.BOT.EDITOR.PALETTE_HINT') }}
        </p>
      </aside>

      <!-- quadro -->
      <div
        ref="viewport"
        data-bot-canvas
        class="relative flex-1 min-w-0 overflow-hidden select-none touch-none"
        :class="drag?.kind === 'pan' ? 'cursor-grabbing' : 'cursor-default'"
        :style="gridStyle"
        @pointerdown="onCanvasDown"
        @wheel.prevent="onWheel"
        @dragover.prevent
        @drop.prevent="onDrop"
      >
        <div class="absolute top-0 left-0 origin-top-left" :style="canvasStyle">
          <svg
            class="absolute top-0 left-0 overflow-visible pointer-events-none"
            width="1"
            height="1"
          >
            <defs>
              <marker
                id="outsider-bot-arrow"
                viewBox="0 0 10 10"
                refX="9"
                refY="5"
                markerWidth="7"
                markerHeight="7"
                orient="auto"
              >
                <path d="M0,0 L10,5 L0,10 z" class="fill-n-slate-8" />
              </marker>
              <marker
                id="outsider-bot-arrow-active"
                viewBox="0 0 10 10"
                refX="9"
                refY="5"
                markerWidth="7"
                markerHeight="7"
                orient="auto"
              >
                <path d="M0,0 L10,5 L0,10 z" class="fill-n-brand" />
              </marker>
            </defs>
            <g v-for="edge in edgeViews" :key="edge.id">
              <path
                :d="edge.path"
                fill="none"
                stroke="transparent"
                stroke-width="14"
                class="cursor-pointer [pointer-events:stroke]"
                @pointerdown.stop="selectEdge(edge.id)"
              />
              <path
                :d="edge.path"
                fill="none"
                :stroke-width="edge.active ? 2.5 : 2"
                :class="edge.active ? 'stroke-n-brand' : 'stroke-n-slate-8'"
                :marker-end="
                  edge.active
                    ? 'url(#outsider-bot-arrow-active)'
                    : 'url(#outsider-bot-arrow)'
                "
              />
            </g>
            <path
              v-if="draftPath"
              :d="draftPath"
              fill="none"
              stroke-width="2"
              stroke-dasharray="6 5"
              class="stroke-n-brand"
            />
          </svg>

          <BotNodeCard
            v-for="node in graph.nodes"
            :key="node.id"
            :node="node"
            :selected="selectedId === node.id"
            :highlighted="simulatingId === node.id"
            :connecting="drag?.kind === 'connect' && drag.from !== node.id"
            :warnings="warningsByNode[node.id] || []"
            :connected-ports="connectedPorts[node.id] || []"
            @select="selectAndShow"
            @drag-start="onNodeDragStart(node, $event)"
            @port-down="(portId, event) => onPortDown(node, portId, event)"
          />

          <!-- apagar a seta escolhida -->
          <template v-for="edge in edgeViews" :key="`x-${edge.id}`">
            <button
              v-if="edge.id === selectedEdgeId"
              type="button"
              class="absolute z-30 flex items-center justify-center -translate-x-1/2 -translate-y-1/2 rounded-full shadow-md size-7 bg-n-ruby-9 text-white hover:bg-n-ruby-10"
              :style="{ left: `${edge.mid.x}px`, top: `${edge.mid.y}px` }"
              @pointerdown.stop
              @click="deleteEdge(edge.id)"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </template>
        </div>

        <!-- soltar a seta no vazio: escolher o bloco novo -->
        <div
          v-if="quickAdd"
          class="absolute z-40 flex flex-col w-52 gap-0.5 p-1.5 border rounded-xl bg-n-solid-2 border-n-weak shadow-lg"
          :style="{ left: `${quickAdd.left}px`, top: `${quickAdd.top}px` }"
          @pointerdown.stop
        >
          <span class="px-2 py-1 text-xs text-n-slate-11">
            {{ t('OUTSIDER_TOOLS.BOT.EDITOR.QUICK_ADD') }}
          </span>
          <button
            v-for="type in PALETTE"
            :key="type"
            type="button"
            class="flex items-center gap-2 px-2 py-1.5 text-sm text-left rounded-lg hover:bg-n-alpha-1 text-n-slate-12"
            @click="addFromQuickMenu(type)"
          >
            <span
              class="flex items-center justify-center rounded size-5 shrink-0 text-white"
              :class="NODE_TYPES[type].color"
            >
              <Icon :icon="NODE_TYPES[type].icon" class="size-3" />
            </span>
            {{ t(`OUTSIDER_TOOLS.BOT.TYPES.${type}`) }}
          </button>
        </div>

        <!-- zoom -->
        <div
          class="absolute flex items-center gap-1 p-1 border rounded-lg bottom-3 left-3 bg-n-solid-1 border-n-weak shadow-sm"
          @pointerdown.stop
        >
          <Button
            icon="i-lucide-minus"
            xs
            ghost
            slate
            @click="zoomAt(1 / 1.2)"
          />
          <span class="w-10 text-xs text-center tabular-nums text-n-slate-11">
            {{ Math.round(view.scale * 100) }}%
          </span>
          <Button icon="i-lucide-plus" xs ghost slate @click="zoomAt(1.2)" />
          <Button
            v-tooltip.top="t('OUTSIDER_TOOLS.BOT.EDITOR.FIT')"
            icon="i-lucide-maximize"
            xs
            ghost
            slate
            @click="fitView"
          />
        </div>
        <span
          class="absolute px-2 py-1 text-[11px] rounded-md pointer-events-none bottom-3 right-3 bg-n-solid-1/80 text-n-slate-10"
        >
          {{ t('OUTSIDER_TOOLS.BOT.EDITOR.CANVAS_HINT') }}
        </span>
      </div>

      <BotSimulator
        v-if="testing"
        :graph="graph"
        @close="testing = false"
        @focus="simulatingId = $event"
      />
      <BotInspector
        v-else-if="selectedNode"
        :key="selectedNode.id"
        :node="selectedNode"
        :warnings="warningsByNode[selectedNode.id] || []"
        @close="selectedId = null"
        @delete="deleteNode(selectedNode.id)"
        @duplicate="duplicateNode(selectedNode.id)"
      />
    </div>
  </div>
</template>
