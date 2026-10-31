<script setup>
// OUTSIDER: "Testar" do editor do bot. Roda o fluxo desenhado (ainda não salvo) na tela, com um
// contato de exemplo, sem mandar nada a ninguém. Segue as regras do servidor (simulator.js) e mostra
// em cinza o que o bot faria na conversa (equipe, etiquetas, passar para a equipe).
// Os blocos de integração rodam de verdade no servidor (o mesmo código da conversa): consultas leem os
// outros sistemas; o que altera dados pergunta antes ("Chamar de verdade" ou "Pular"). Enviar documento
// só mostra o que o cliente receberia.
import {
  ref,
  reactive,
  computed,
  nextTick,
  inject,
  onBeforeUnmount,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BotFlowsAPI from 'dashboard/api/outsider/botFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import BotMenuPreview from './BotMenuPreview.vue';
import {
  integrationPorts,
  errorText,
  isIntegration,
} from './integrations/integrationTypes';
import {
  matchOption,
  matchRoute,
  openNow,
  renderText,
  whatsappHtml,
  fold,
  SAMPLE_CONTACT,
} from './simulator';

const props = defineProps({
  graph: { type: Object, required: true },
});

const emit = defineEmits(['close', 'focus']);

const MAX_STEPS = 40;
// como Outsider::Bot::IntegrationSteps: chamadas por mensagem do cliente e saídas de falha
const MAX_CALLS = 10;
const FAILURE_PORTS = ['error', 'not_found', 'default'];
// "Pular" uma chamada que altera dados segue como se tivesse dado certo
const SKIP_PORTS = { api: 'ok', db_query: 'found' };
const { t, te } = useI18n();
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');
const flowId = inject('botFlowId', ref(null));

const messages = ref([]);
const draft = ref('');
const typing = ref(false);
const clock = ref('now');
const scroller = ref(null);
const run = reactive({
  started: false,
  finished: false,
  nodeId: null,
  waiting: null,
  attempts: 0,
  variables: {},
  // chamadas a outros sistemas desde a última mensagem do cliente
  calls: 0,
  // documentos achados esperando o cliente escolher: { items, options }
  choice: null,
  token: 0,
});

let counter = 0;
const sleep = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const nodesById = computed(() =>
  Object.fromEntries(props.graph.nodes.map(node => [node.id, node]))
);
const startNode = computed(() =>
  props.graph.nodes.find(node => node.type === 'start')
);
const nextOf = (node, port) => {
  const edge = props.graph.edges.find(
    item => item.from === node.id && item.port === port
  );
  return edge ? nodesById.value[edge.to] : null;
};

const scrollDown = async () => {
  await nextTick();
  if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight;
};

const push = message => {
  counter += 1;
  messages.value.push({ id: counter, ...message });
  scrollDown();
};
const system = text => push({ from: 'system', text });
const render = text => renderText(text, run.variables);

const teamName = id => teams.value.find(team => team.id === id)?.name;
const agentName = id => agents.value.find(agent => agent.id === id)?.name;

const triggerNote = computed(() => {
  const data = startNode.value?.data || {};
  if (data.trigger === 'keyword') {
    return t('OUTSIDER_TOOLS.BOT.TEST.TRIGGER_KEYWORD', {
      words: (data.keywords || []).join(', ') || '—',
    });
  }
  return t(
    `OUTSIDER_TOOLS.BOT.TEST.TRIGGER_${(data.trigger || 'unassigned_message').toUpperCase()}`
  );
});

const finish = text => {
  run.finished = true;
  run.waiting = null;
  if (text) system(text);
  emit('focus', null);
};

const botSays = async (text, delaySeconds = 0) => {
  const content = render(text);
  if (!content.trim()) return;
  typing.value = true;
  scrollDown();
  await sleep(Math.min(Math.max(delaySeconds, 0.5), 3) * 1000);
  typing.value = false;
  push({ from: 'bot', text: content });
};

const sendMenu = async node => {
  const data = node.data;
  typing.value = true;
  scrollDown();
  await sleep(600);
  typing.value = false;
  push({
    from: 'bot',
    menu: {
      text: render(data.text),
      title: render(data.title),
      footer: render(data.footer),
      menuStyle: data.style,
      buttonLabel: data.button_label,
      options: data.options,
    },
    nodeId: node.id,
    chosenId: '',
  });
};

const actionSummary = data => {
  const parts = [];
  if (data.team_id) {
    parts.push(
      t('OUTSIDER_TOOLS.BOT.TEST.SET_TEAM', {
        name: teamName(data.team_id) || '—',
      })
    );
  }
  if (data.assignee_id) {
    parts.push(
      t('OUTSIDER_TOOLS.BOT.TEST.SET_AGENT', {
        name: agentName(data.assignee_id) || '—',
      })
    );
  }
  if (data.labels?.length) {
    parts.push(
      t('OUTSIDER_TOOLS.BOT.TEST.SET_LABELS', {
        labels: data.labels.join(', '),
      })
    );
  }
  if (data.priority) {
    parts.push(
      t('OUTSIDER_TOOLS.BOT.TEST.SET_PRIORITY', {
        priority: t(`OUTSIDER_TOOLS.BOT.PRIORITIES.${data.priority}`),
      })
    );
  }
  if (data.note) {
    parts.push(
      t('OUTSIDER_TOOLS.BOT.TEST.SET_NOTE', { note: render(data.note) })
    );
  }
  return parts.join(' · ') || t('OUTSIDER_TOOLS.BOT.SUMMARY.NO_ACTION');
};

const isOpen = data => {
  if (clock.value === 'inside') return true;
  if (clock.value === 'outside') return false;
  return openNow(data);
};

// anda pelos blocos até um que espera o cliente, ou o fim
const walk = async (nodeId, token) => {
  let node = nodesById.value[nodeId];
  for (let step = 0; step < MAX_STEPS; step += 1) {
    if (token !== run.token) return;
    if (!node) {
      finish(t('OUTSIDER_TOOLS.BOT.TEST.NO_ARROW'));
      return;
    }
    run.nodeId = node.id;
    emit('focus', node.id);
    const data = node.data || {};
    switch (node.type) {
      case 'start':
        node = nextOf(node, 'next');
        break;
      case 'message':
        // eslint-disable-next-line no-await-in-loop
        await botSays(data.text, data.delay_seconds);
        node = nextOf(node, 'next');
        break;
      case 'menu':
        // eslint-disable-next-line no-await-in-loop
        await sendMenu(node);
        run.waiting = 'menu';
        run.attempts = 0;
        return;
      case 'question':
        // eslint-disable-next-line no-await-in-loop
        await botSays(data.text);
        run.waiting = 'question';
        return;
      case 'condition': {
        const open = isOpen(data);
        system(
          t(
            open
              ? 'OUTSIDER_TOOLS.BOT.TEST.INSIDE'
              : 'OUTSIDER_TOOLS.BOT.TEST.OUTSIDE'
          )
        );
        node = nextOf(node, open ? 'inside' : 'outside');
        break;
      }
      case 'action':
        system(actionSummary(data));
        node = nextOf(node, 'next');
        break;
      case 'handoff': {
        // eslint-disable-next-line no-await-in-loop
        await botSays(data.text);
        const target = [teamName(data.team_id), agentName(data.assignee_id)]
          .filter(Boolean)
          .join(' · ');
        finish(
          target
            ? t('OUTSIDER_TOOLS.BOT.TEST.HANDOFF_TO', { target })
            : t('OUTSIDER_TOOLS.BOT.TEST.HANDOFF')
        );
        return;
      }
      case 'end':
        // eslint-disable-next-line no-await-in-loop
        await botSays(data.text);
        finish(
          t(
            data.resolve
              ? 'OUTSIDER_TOOLS.BOT.TEST.END_RESOLVED'
              : 'OUTSIDER_TOOLS.BOT.TEST.END'
          )
        );
        return;
      default: {
        if (!isIntegration(node.type)) {
          finish(t('OUTSIDER_TOOLS.BOT.TEST.END'));
          return;
        }
        // eslint-disable-next-line no-await-in-loop, no-use-before-define
        const port = await integrationStep(node);
        if (token !== run.token || port === null) return;
        const following = nextOf(node, port);
        if (!following && FAILURE_PORTS.includes(port)) {
          finish(t('OUTSIDER_TOOLS.BOT.TEST.FAILURE_HANDOFF'));
          return;
        }
        node = following;
        break;
      }
    }
  }
  finish(t('OUTSIDER_TOOLS.BOT.TEST.TOO_MANY_STEPS', { count: MAX_STEPS }));
};

const goFrom = (node, port, fallbackHandoff = false) => {
  const following = nextOf(node, port);
  if (following) return walk(following.id, run.token);
  if (fallbackHandoff) return finish(t('OUTSIDER_TOOLS.BOT.TEST.HANDOFF'));
  return finish(t('OUTSIDER_TOOLS.BOT.TEST.NO_ARROW'));
};

// ---- blocos de integração ----

const portLabel = (node, port) =>
  integrationPorts(node, t).find(item => item.id === port)?.label || port;

const blockName = node => t(`OUTSIDER_TOOLS.BOT.TYPES.${node.type}`);

const savedNames = variables =>
  Object.keys(variables || {})
    .filter(key => key !== 'erro')
    .slice(0, 4)
    .map(key => `{{${key}}}`)
    .join(', ');

// a linha cinza de cada bloco: por onde seguiu, código e tempo, erro e o que guardou
const callNote = (node, result) => {
  const parts = [
    t('OUTSIDER_TOOLS.BOT.TEST.CALL_RESULT', {
      block: blockName(node),
      port: portLabel(node, result.port),
    }),
  ];
  const response = result.response;
  if (response) {
    parts.push(
      response.cached
        ? t('OUTSIDER_TOOLS.BOT.TEST.CALL_CACHED', { status: response.status })
        : t('OUTSIDER_TOOLS.BOT.TEST.CALL_HTTP', {
            status: response.status,
            ms: response.duration_ms,
          })
    );
  }
  const error = result.variables?.erro;
  if (error) parts.push(errorText(error, t, te));
  const saved = savedNames(result.variables);
  if (saved && !error) {
    parts.push(t('OUTSIDER_TOOLS.BOT.TEST.CALL_SAVED', { names: saved }));
  }
  return parts.join(' · ');
};

const callServer = async (node, confirmWrite) => {
  const { data } = await BotFlowsAPI.runBlock({
    node: { id: node.id, type: node.type, data: node.data },
    variables: run.variables,
    contact: {
      nome: SAMPLE_CONTACT.name,
      telefone: SAMPLE_CONTACT.phone_number,
      email: SAMPLE_CONTACT.email,
    },
    flow_id: flowId.value,
    confirm_write: confirmWrite,
  });
  return data;
};

const sendChoice = async node => {
  const data = node.data || {};
  const count = run.choice.items.length;
  typing.value = true;
  scrollDown();
  await sleep(600);
  typing.value = false;
  push({
    from: 'bot',
    menu: {
      text: render(
        data.text ||
          t('OUTSIDER_TOOLS.BOT.TEST.CHOOSE_DOCUMENT', { count }, count)
      ),
      title: '',
      footer: '',
      menuStyle: 'list',
      buttonLabel: data.button_label,
      options: run.choice.options,
    },
    nodeId: node.id,
    chosenId: '',
  });
};

// na lista: o nome sem a extensão (até 24 letras); embaixo, o resto do nome, o tipo e a data
const fileParts = item => {
  const name = String(item.nome || '');
  const match = /\.([A-Za-z0-9]{1,5})$/.exec(name);
  const base = match ? name.slice(0, -match[0].length) : name;
  return { base: base || name, extension: match ? match[1].toUpperCase() : '' };
};

const choiceDescription = item => {
  const { base, extension } = fileParts(item);
  const rest = base.length > 24 ? base.slice(24, 64).trim() : '';
  const date = item.modificado
    ? new Date(item.modificado).toLocaleDateString('pt-BR', {
        timeZone: 'America/Sao_Paulo',
      })
    : '';
  return [rest, extension, date].filter(Boolean).join(' · ').slice(0, 72);
};

const offerChoice = async (node, items) => {
  run.choice = {
    items,
    options: items.map((item, index) => ({
      id: `doc_${index + 1}`,
      label: fileParts(item).base.slice(0, 24).trim(),
      description: choiceDescription(item),
    })),
  };
  run.waiting = 'choice';
  run.attempts = 0;
  await sendChoice(node);
};

// o que o cliente receberia no Enviar documento (no teste nada sai do Nextcloud)
const previewDocument = async (node, preview) => {
  const data = node.data || {};
  typing.value = true;
  scrollDown();
  await sleep(600);
  typing.value = false;
  if (preview?.mode === 'link') {
    const days = Number(data.link_days) || 7;
    const text =
      data.link_text ||
      t('OUTSIDER_TOOLS.BOT.TEST.DOCUMENT_LINK', { days, link: '{{link}}' });
    push({
      from: 'bot',
      text: renderText(text, {
        ...run.variables,
        link: t('OUTSIDER_TOOLS.BOT.TEST.SAMPLE_LINK'),
      }),
    });
    return;
  }
  push({
    from: 'bot',
    document: { name: preview?.name || '', caption: render(data.caption) },
  });
};

// roda o bloco no servidor e diz por qual saída seguir; null quando o teste espera o cliente
// (escolher o documento) ou a confirmação de uma chamada que altera dados
const runIntegration = async (node, confirmWrite = false) => {
  let result;
  typing.value = true;
  scrollDown();
  try {
    result = await callServer(node, confirmWrite);
  } catch (error) {
    typing.value = false;
    const code = error?.response?.data?.error;
    system(
      t('OUTSIDER_TOOLS.BOT.TEST.CALL_FAILED', {
        block: blockName(node),
        error: code ? errorText(code, t, te) : error?.message || '',
      })
    );
    return 'error';
  }
  typing.value = false;
  if (result.needs_confirmation) {
    run.waiting = 'confirm';
    push({
      from: 'system',
      confirm: true,
      nodeId: node.id,
      answered: '',
      text: t('OUTSIDER_TOOLS.BOT.TEST.CONFIRM_WRITE', {
        block: blockName(node),
      }),
    });
    return null;
  }
  Object.assign(run.variables, result.variables || {});
  if (result.choice?.length) {
    system(
      t('OUTSIDER_TOOLS.BOT.TEST.DOCUMENTS_FOUND', {
        count: result.choice.length,
      })
    );
    await offerChoice(node, result.choice);
    return null;
  }
  system(callNote(node, result));
  if (['doc_send', 'file_send'].includes(node.type) && result.port === 'ok') {
    await previewDocument(node, result.preview);
  }
  return result.port;
};

const integrationStep = async node => {
  if (!['decision', 'doc_send', 'file_send'].includes(node.type)) {
    run.calls += 1;
    if (run.calls > MAX_CALLS) {
      system(t('OUTSIDER_TOOLS.BOT.TEST.TOO_MANY_CALLS', { count: MAX_CALLS }));
      return 'error';
    }
  }
  return runIntegration(node);
};

// segue pela saída de um bloco de integração que parou (confirmação ou escolha do documento)
const continueFrom = (node, port) => {
  const following = nextOf(node, port);
  if (following) return walk(following.id, run.token);
  if (FAILURE_PORTS.includes(port)) {
    return finish(t('OUTSIDER_TOOLS.BOT.TEST.FAILURE_HANDOFF'));
  }
  return finish(t('OUTSIDER_TOOLS.BOT.TEST.NO_ARROW'));
};

const confirmCall = async (message, really) => {
  if (message.answered || run.waiting !== 'confirm') return;
  const node = nodesById.value[message.nodeId];
  if (!node) return;
  message.answered = really ? 'run' : 'skip';
  run.waiting = null;
  const token = run.token;
  let port = SKIP_PORTS[node.type] || 'ok';
  if (really) port = await runIntegration(node, true);
  else
    system(
      t('OUTSIDER_TOOLS.BOT.TEST.SKIPPED', { port: portLabel(node, port) })
    );
  if (token !== run.token || port === null) return;
  await continueFrom(node, port);
};

const answerChoice = async (node, text, option) => {
  const { items, options } = run.choice || { items: [], options: [] };
  const chosen = option
    ? options.find(item => item.id === option.id)
    : matchOption(options, text);
  if (chosen) {
    const bubble = [...messages.value]
      .reverse()
      .find(item => item.nodeId === node.id && item.menu);
    if (bubble) bubble.chosenId = chosen.id;
    run.variables[`bloco_${node.id}`] = chosen.label;
    run.variables[node.data?.variable || 'documento'] =
      items[options.indexOf(chosen)];
    run.waiting = null;
    run.choice = null;
    await continueFrom(node, 'found');
    return;
  }
  run.attempts += 1;
  const limit = Math.min(Math.max(Number(node.data?.max_attempts) || 1, 1), 5);
  if (run.attempts >= limit) {
    run.waiting = null;
    run.choice = null;
    system(t('OUTSIDER_TOOLS.BOT.TEST.CHOICE_LIMIT'));
    await continueFrom(node, 'not_found');
    return;
  }
  await botSays(t('OUTSIDER_TOOLS.BOT.TEST.INVALID_DEFAULT'));
  await sendChoice(node);
};

const keywordMatches = text => {
  const words = (startNode.value?.data?.keywords || [])
    .map(fold)
    .filter(Boolean);
  const folded = fold(text);
  return words.some(
    word => folded === word || ` ${folded} `.includes(` ${word} `)
  );
};

const answerMenu = async (node, text, option) => {
  const data = node.data;
  const chosen = option || matchOption(data.options || [], text);
  if (chosen) {
    const bubble = [...messages.value]
      .reverse()
      .find(item => item.nodeId === node.id);
    if (bubble) bubble.chosenId = chosen.id;
    run.variables[`bloco_${node.id}`] = chosen.label;
    run.waiting = null;
    await goFrom(node, chosen.id);
    return;
  }
  run.attempts += 1;
  if (run.attempts >= Number(data.max_attempts || 2)) {
    run.waiting = null;
    system(t('OUTSIDER_TOOLS.BOT.TEST.INVALID_LIMIT'));
    await goFrom(node, 'invalid', true);
    return;
  }
  await botSays(
    data.invalid_text || t('OUTSIDER_TOOLS.BOT.TEST.INVALID_DEFAULT')
  );
  await sendMenu(node);
};

const answerQuestion = async (node, text) => {
  const data = node.data;
  run.variables[`bloco_${node.id}`] = text;
  if (data.variable) run.variables[data.variable.toLowerCase()] = text;
  if (data.contact_field) {
    system(
      t('OUTSIDER_TOOLS.BOT.TEST.SAVED_FIELD', {
        field: t(`OUTSIDER_TOOLS.BOT.CONTACT_FIELDS.${data.contact_field}`),
        value: text,
      })
    );
  }
  run.waiting = null;
  const route = matchRoute(data.routes, text);
  await goFrom(node, route ? route.id : 'default');
};

const send = async (text, option = null) => {
  const content = String(text || '').trim();
  if (!content || typing.value) return;
  draft.value = '';
  push({ from: 'contact', text: content });
  run.calls = 0;
  if (run.finished) {
    system(t('OUTSIDER_TOOLS.BOT.TEST.ALREADY_FINISHED'));
    return;
  }
  if (!startNode.value) {
    system(t('OUTSIDER_TOOLS.BOT.TEST.NO_START'));
    return;
  }
  if (!run.started) {
    if (
      startNode.value.data?.trigger === 'keyword' &&
      !keywordMatches(content)
    ) {
      system(t('OUTSIDER_TOOLS.BOT.TEST.KEYWORD_MISS'));
      return;
    }
    run.started = true;
    run.variables.primeira_mensagem = content;
    await walk(startNode.value.id, run.token);
    return;
  }
  const node = nodesById.value[run.nodeId];
  if (!node) {
    finish(t('OUTSIDER_TOOLS.BOT.TEST.NO_ARROW'));
    return;
  }
  if (run.waiting === 'menu') await answerMenu(node, content, option);
  else if (run.waiting === 'question') await answerQuestion(node, content);
  else if (run.waiting === 'choice') await answerChoice(node, content, option);
  else if (run.waiting === 'confirm') {
    system(t('OUTSIDER_TOOLS.BOT.TEST.CONFIRM_FIRST'));
  }
};

const choose = option => send(option.label, option);

const restart = () => {
  run.token += 1;
  Object.assign(run, {
    started: false,
    finished: false,
    nodeId: null,
    waiting: null,
    attempts: 0,
    variables: {},
    calls: 0,
    choice: null,
  });
  typing.value = false;
  messages.value = [];
  system(triggerNote.value);
  emit('focus', null);
};

restart();

onBeforeUnmount(() => {
  run.token += 1;
  emit('focus', null);
});

const html = text => whatsappHtml(text);
</script>

<template>
  <aside
    class="flex flex-col w-[24rem] max-w-full h-full border-l border-n-weak bg-n-solid-1"
  >
    <header class="flex items-center gap-2 px-4 py-3 border-b border-n-weak">
      <span
        class="flex items-center justify-center rounded-full size-8 shrink-0 bg-n-teal-9 text-white"
      >
        <Icon icon="i-lucide-flask-conical" class="size-4" />
      </span>
      <div class="flex flex-col min-w-0">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t('OUTSIDER_TOOLS.BOT.TEST.TITLE') }}
        </span>
        <span class="text-xs truncate text-n-slate-11">
          {{
            t('OUTSIDER_TOOLS.BOT.TEST.SUBTITLE', { name: SAMPLE_CONTACT.name })
          }}
        </span>
      </div>
      <Button
        v-tooltip.bottom="t('OUTSIDER_TOOLS.BOT.TEST.RESTART')"
        icon="i-lucide-rotate-ccw"
        xs
        ghost
        slate
        class="ml-auto"
        @click="restart"
      />
      <Button icon="i-lucide-x" xs ghost slate @click="emit('close')" />
    </header>
    <div
      class="flex items-center gap-2 px-4 py-2 text-xs border-b border-n-weak text-n-slate-11"
    >
      <Icon icon="i-lucide-clock" class="size-3.5 shrink-0" />
      <span>{{ t('OUTSIDER_TOOLS.BOT.TEST.CLOCK') }}</span>
      <select v-model="clock" class="!mb-0 !h-7 !py-0 !text-xs !w-auto">
        <option value="now">
          {{ t('OUTSIDER_TOOLS.BOT.TEST.CLOCK_NOW') }}
        </option>
        <option value="inside">
          {{ t('OUTSIDER_TOOLS.BOT.TEST.CLOCK_INSIDE') }}
        </option>
        <option value="outside">
          {{ t('OUTSIDER_TOOLS.BOT.TEST.CLOCK_OUTSIDE') }}
        </option>
      </select>
    </div>

    <div
      ref="scroller"
      class="flex flex-col flex-1 gap-2 px-3 py-4 overflow-y-auto bg-n-slate-2"
    >
      <template v-for="message in messages" :key="message.id">
        <div
          v-if="message.from === 'system' && message.confirm"
          class="flex justify-center"
        >
          <div
            class="flex flex-col items-center gap-2 px-3 py-2 text-xs text-center rounded-lg bg-n-amber-3 text-n-amber-11 max-w-[90%]"
          >
            <span class="flex items-start gap-1.5">
              <Icon
                icon="i-lucide-triangle-alert"
                class="size-3.5 mt-px shrink-0"
              />
              {{ message.text }}
            </span>
            <div v-if="!message.answered" class="flex gap-1.5">
              <Button
                :label="t('OUTSIDER_TOOLS.BOT.TEST.CONFIRM_RUN')"
                xs
                amber
                @click="confirmCall(message, true)"
              />
              <Button
                :label="t('OUTSIDER_TOOLS.BOT.TEST.CONFIRM_SKIP')"
                xs
                faded
                slate
                @click="confirmCall(message, false)"
              />
            </div>
            <span v-else class="opacity-80">
              {{
                message.answered === 'run'
                  ? t('OUTSIDER_TOOLS.BOT.TEST.CONFIRMED_RUN')
                  : t('OUTSIDER_TOOLS.BOT.TEST.CONFIRMED_SKIP')
              }}
            </span>
          </div>
        </div>
        <div v-else-if="message.from === 'system'" class="flex justify-center">
          <span
            class="px-2.5 py-1 text-xs text-center rounded-lg bg-n-alpha-2 text-n-slate-11 max-w-[90%] break-words"
          >
            {{ message.text }}
          </span>
        </div>
        <div v-else-if="message.from === 'contact'" class="flex justify-end">
          <!-- eslint-disable vue/no-v-html -->
          <span
            class="px-3 py-2 text-sm break-words rounded-xl rounded-tr-sm max-w-[80%] bg-n-teal-4 text-n-slate-12"
            v-html="html(message.text)"
          />
          <!-- eslint-enable vue/no-v-html -->
        </div>
        <div v-else class="flex justify-start">
          <BotMenuPreview
            v-if="message.menu"
            v-bind="message.menu"
            :chosen-id="message.chosenId"
            interactive
            :disabled="
              !!message.chosenId ||
              run.nodeId !== message.nodeId ||
              !['menu', 'choice'].includes(run.waiting)
            "
            @choose="choose"
          />
          <div
            v-else-if="message.document"
            class="flex flex-col gap-1.5 p-1.5 rounded-xl rounded-tl-sm max-w-[80%] bg-n-solid-1 shadow-sm"
          >
            <span
              class="flex items-center gap-2 px-2.5 py-2 rounded-lg bg-n-alpha-1"
            >
              <Icon
                icon="i-lucide-file-text"
                class="size-6 shrink-0 text-n-ruby-10"
              />
              <span class="text-sm break-all text-n-slate-12">
                {{ message.document.name }}
              </span>
            </span>
            <!-- eslint-disable vue/no-v-html -->
            <span
              v-if="message.document.caption"
              class="px-1.5 pb-0.5 text-sm break-words text-n-slate-12"
              v-html="html(message.document.caption)"
            />
            <!-- eslint-enable vue/no-v-html -->
          </div>
          <!-- eslint-disable vue/no-v-html -->
          <span
            v-else
            class="px-3 py-2 text-sm break-words rounded-xl rounded-tl-sm max-w-[80%] bg-n-solid-1 text-n-slate-12 shadow-sm"
            v-html="html(message.text)"
          />
          <!-- eslint-enable vue/no-v-html -->
        </div>
      </template>
      <div v-if="typing" class="flex justify-start">
        <span
          class="flex items-center gap-1 px-3 py-2.5 rounded-xl rounded-tl-sm bg-n-solid-1 shadow-sm"
        >
          <span class="rounded-full size-1.5 bg-n-slate-9 animate-bounce" />
          <span
            class="rounded-full size-1.5 bg-n-slate-9 animate-bounce [animation-delay:150ms]"
          />
          <span
            class="rounded-full size-1.5 bg-n-slate-9 animate-bounce [animation-delay:300ms]"
          />
        </span>
      </div>
    </div>

    <form
      class="flex items-center gap-2 px-3 py-3 border-t border-n-weak"
      @submit.prevent="send(draft)"
    >
      <input
        v-model="draft"
        type="text"
        class="flex-1 min-w-0 !mb-0 !h-9 text-sm"
        :placeholder="
          run.finished
            ? t('OUTSIDER_TOOLS.BOT.TEST.FINISHED_PLACEHOLDER')
            : t('OUTSIDER_TOOLS.BOT.TEST.PLACEHOLDER')
        "
      />
      <Button
        type="submit"
        icon="i-lucide-send-horizontal"
        sm
        :disabled="!draft.trim() || typing"
      />
    </form>
  </aside>
</template>
