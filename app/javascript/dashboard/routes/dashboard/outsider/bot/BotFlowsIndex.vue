<script setup>
// OUTSIDER: Configurações > Automação por bot (só administradores). Lista os fluxos com ligar e
// desligar, caixas, gatilho e números dos últimos 7 dias. "Novo fluxo" já cria um começo pronto
// (boas-vindas, horário, menu e passar para a equipe) e abre o editor. As abas Conexões, Planilhas e
// Registro (?tab=) cuidam dos sistemas que os blocos de integração usam.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import BotFlowsAPI from 'dashboard/api/outsider/botFlows';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import BotConnections from './integrations/BotConnections.vue';
import BotDatasets from './integrations/BotDatasets.vue';
import BotLogs from './integrations/BotLogs.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const TABS = ['flows', 'connections', 'datasets', 'logs'];
const tab = computed(() =>
  TABS.includes(route.query.tab) ? route.query.tab : 'flows'
);
const tabItems = computed(() =>
  TABS.map(id => ({ id, label: t(`OUTSIDER_TOOLS.BOT.TABS.${id}`) }))
);
const setTab = id =>
  router.replace({
    query: { ...route.query, tab: id === 'flows' ? undefined : id },
  });
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');

const flows = ref([]);
// a aba aberta (Conexões, Planilhas, Registro), para o botão do cabeçalho
const panel = ref(null);
const isLoading = ref(true);
// '' parado; 'blank' ou 'document' enquanto cria (o botão que mostra o carregando)
const isCreating = ref('');
const busy = ref({});

const load = async () => {
  try {
    const { data } = await BotFlowsAPI.get();
    flows.value = data.payload;
  } catch {
    useAlert(t('OUTSIDER_TOOLS.BOT.LIST.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const openFlow = flow =>
  router.push({
    name: 'outsider_bot_flow_editor',
    params: { flowId: flow.id },
  });

// template 'document': o exemplo da 2ª via de documento (confere o WhatsApp no cadastro antes de mandar)
const create = async (template = '') => {
  if (isCreating.value) return;
  isCreating.value = template || 'blank';
  try {
    const { data } = await BotFlowsAPI.create({
      name:
        template === 'document'
          ? t('OUTSIDER_TOOLS.BOT.LIST.EXAMPLE_NAME')
          : t('OUTSIDER_TOOLS.BOT.LIST.NEW_NAME', {
              number: flows.value.length + 1,
            }),
      template: template || undefined,
    });
    openFlow(data);
  } catch {
    useAlert(t('OUTSIDER_TOOLS.BOT.LIST.CREATE_ERROR'));
  } finally {
    isCreating.value = '';
  }
};

const toggle = async (flow, active) => {
  busy.value = { ...busy.value, [flow.id]: true };
  try {
    await BotFlowsAPI.update(flow.id, { active });
    flow.active = active;
    useAlert(
      t(
        active
          ? 'OUTSIDER_TOOLS.BOT.LIST.ACTIVATED'
          : 'OUTSIDER_TOOLS.BOT.LIST.DEACTIVATED'
      )
    );
  } catch {
    useAlert(t('OUTSIDER_TOOLS.BOT.EDITOR.SAVE_ERROR'));
  } finally {
    busy.value = { ...busy.value, [flow.id]: false };
  }
};

const duplicate = async flow => {
  try {
    await BotFlowsAPI.duplicate(flow.id);
    await load();
  } catch {
    useAlert(t('OUTSIDER_TOOLS.BOT.EDITOR.SAVE_ERROR'));
  }
};

const remove = async flow => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('OUTSIDER_TOOLS.BOT.LIST.DELETE_CONFIRM', { name: flow.name })
    )
  ) {
    return;
  }
  try {
    await BotFlowsAPI.delete(flow.id);
    flows.value = flows.value.filter(item => item.id !== flow.id);
  } catch {
    useAlert(t('OUTSIDER_TOOLS.BOT.EDITOR.SAVE_ERROR'));
  }
};

const inboxNames = flow => {
  if (!flow.inbox_ids?.length)
    return t('OUTSIDER_TOOLS.BOT.EDITOR.ALL_INBOXES');
  return flow.inbox_ids
    .map(id => inboxes.value.find(inbox => inbox.id === id)?.name)
    .filter(Boolean)
    .join(', ');
};

const hasActive = computed(() => flows.value.some(flow => flow.active));

onMounted(() => {
  store.dispatch('inboxes/get');
  load();
});
</script>

<template>
  <SettingsLayout
    :is-loading="tab === 'flows' && isLoading"
    :no-records-found="tab === 'flows' && !isLoading && !flows.length"
    :no-records-message="t('OUTSIDER_TOOLS.BOT.LIST.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('OUTSIDER_TOOLS.BOT.LIST.TITLE')"
        :description="
          tab === 'flows'
            ? t('OUTSIDER_TOOLS.BOT.LIST.DESCRIPTION')
            : t(`OUTSIDER_TOOLS.BOT.TABS_DESCRIPTION.${tab}`)
        "
      >
        <template #tabs>
          <TabBar
            :tabs="tabItems"
            :initial-active-tab="TABS.indexOf(tab)"
            @tab-changed="setTab($event.id)"
          />
        </template>
        <template #actions>
          <div v-if="tab === 'flows'" class="flex flex-wrap items-center gap-2">
            <Button
              v-tooltip.bottom="t('OUTSIDER_TOOLS.BOT.LIST.EXAMPLE_HINT')"
              :label="t('OUTSIDER_TOOLS.BOT.LIST.EXAMPLE')"
              icon="i-lucide-file-search"
              faded
              slate
              :is-loading="isCreating === 'document'"
              @click="create('document')"
            />
            <Button
              :label="t('OUTSIDER_TOOLS.BOT.LIST.NEW')"
              icon="i-lucide-plus"
              :is-loading="isCreating === 'blank'"
              @click="create()"
            />
          </div>
          <Button
            v-else-if="tab === 'connections'"
            :label="t('OUTSIDER_TOOLS.BOT.CONNECTIONS.NEW')"
            icon="i-lucide-plus"
            @click="panel?.openCreate()"
          />
          <Button
            v-else-if="tab === 'datasets'"
            :label="t('OUTSIDER_TOOLS.BOT.DATASETS.UPLOAD')"
            icon="i-lucide-upload"
            @click="panel?.pickFile()"
          />
          <Button
            v-else
            :label="t('OUTSIDER_TOOLS.BOT.LOGS.REFRESH')"
            icon="i-lucide-refresh-cw"
            faded
            slate
            @click="panel?.reload()"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BotConnections v-if="tab === 'connections'" ref="panel" />
      <BotDatasets v-else-if="tab === 'datasets'" ref="panel" />
      <BotLogs v-else-if="tab === 'logs'" ref="panel" :flows="flows" />
      <div v-else class="flex flex-col gap-3">
        <p
          v-if="flows.length > 1 && hasActive"
          class="flex items-start gap-2 px-3 py-2 mb-0 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11"
        >
          <Icon icon="i-lucide-info" class="size-4 shrink-0" />
          {{ t('OUTSIDER_TOOLS.BOT.LIST.ORDER_HINT') }}
        </p>
        <div
          v-for="flow in flows"
          :key="flow.id"
          class="flex flex-wrap items-center gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <span
            class="flex items-center justify-center rounded-xl size-10 shrink-0"
            :class="
              flow.active
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-10'
            "
          >
            <Icon icon="i-lucide-workflow" class="size-5" />
          </span>
          <button
            type="button"
            class="flex flex-col flex-1 min-w-[12rem] text-left"
            @click="openFlow(flow)"
          >
            <span class="text-base font-medium text-n-slate-12 hover:underline">
              {{ flow.name }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{
                t(
                  `OUTSIDER_TOOLS.BOT.TRIGGERS.${flow.trigger || 'unassigned_message'}.TITLE`
                )
              }}
              · {{ inboxNames(flow) }} ·
              {{
                t(
                  'OUTSIDER_TOOLS.BOT.LIST.BLOCKS',
                  { count: flow.nodes_count },
                  flow.nodes_count
                )
              }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{
                t('OUTSIDER_TOOLS.BOT.LIST.STATS', {
                  started: flow.stats.started,
                  handedOff: flow.stats.handed_off,
                  finished: flow.stats.finished,
                })
              }}
            </span>
          </button>
          <label class="flex items-center gap-2 text-sm text-n-slate-12">
            <Switch
              :model-value="flow.active"
              :disabled="busy[flow.id]"
              @update:model-value="toggle(flow, $event)"
            />
            {{
              flow.active
                ? t('OUTSIDER_TOOLS.BOT.EDITOR.ACTIVE')
                : t('OUTSIDER_TOOLS.BOT.EDITOR.INACTIVE')
            }}
          </label>
          <div class="flex items-center gap-1">
            <Button
              :label="t('OUTSIDER_TOOLS.BOT.LIST.EDIT')"
              icon="i-lucide-pencil"
              sm
              faded
              slate
              @click="openFlow(flow)"
            />
            <Button
              v-tooltip.top="t('OUTSIDER_TOOLS.BOT.LIST.DUPLICATE')"
              icon="i-lucide-copy"
              sm
              ghost
              slate
              @click="duplicate(flow)"
            />
            <Button
              v-tooltip.top="t('OUTSIDER_TOOLS.BOT.LIST.DELETE')"
              icon="i-lucide-trash-2"
              sm
              ghost
              ruby
              @click="remove(flow)"
            />
          </div>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
