<script setup>
// OUTSIDER: painel do bloco Buscar documento: pasta do Nextcloud (pode ter {{variável}}, como a pasta do
// cliente), palavras do nome do arquivo e tipos; achando vários, o cliente escolhe na lista ou vai o mais novo.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BotConnectionsAPI from 'dashboard/api/outsider/botConnections';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ConnectionSelect from './ConnectionSelect.vue';
import TemplateField from './TemplateField.vue';
import VariableName from './VariableName.vue';
import BlockTester from './BlockTester.vue';
import { errorText } from './integrationTypes';

const props = defineProps({
  node: { type: Object, required: true },
});

const { t, te } = useI18n();
const data = computed(() => props.node.data);
const EXTENSIONS = ['pdf', 'xml', 'docx', 'xlsx', 'jpg', 'png', 'zip'];

const toggleExtension = ext => {
  const list = data.value.extensions || [];
  data.value.extensions = list.includes(ext)
    ? list.filter(item => item !== ext)
    : [...list, ext];
};

const clampNumber = (key, min, max, fallback) => {
  const number = Number(data.value[key]);
  data.value[key] = Number.isFinite(number)
    ? Math.min(Math.max(Math.round(number), min), max)
    : fallback;
};

// navegar nas pastas da conexão (a raiz é a pasta permitida na conexão)
const browser = ref(null);
const openBrowser = async path => {
  if (!data.value.connection_id) return;
  browser.value = { path, folders: [], loading: true, error: '' };
  try {
    const { data: response } = await BotConnectionsAPI.folders(
      data.value.connection_id,
      path
    );
    browser.value = {
      path,
      folders: response.payload,
      loading: false,
      error: '',
    };
  } catch (error) {
    browser.value = {
      path,
      folders: [],
      loading: false,
      error: errorText(
        error?.response?.data?.error || 'connection_failed',
        t,
        te
      ),
    };
  }
};
const parentOf = path => {
  const parts = path.split('/').filter(Boolean);
  parts.pop();
  return `/${parts.join('/')}`;
};
const useFolder = path => {
  data.value.folder = path || '/';
  browser.value = null;
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConnectionSelect v-model="data.connection_id" kind="nextcloud" />
    <div class="flex flex-col gap-1.5">
      <TemplateField
        v-model="data.folder"
        mono
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.FOLDER')"
        placeholder="/Clientes/{{cnpj | digitos}}"
        :hint="
          t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.FOLDER_HINT', {
            example: '/Clientes/{{cnpj | digitos}}',
          })
        "
        :maxlength="500"
      />
      <Button
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.BROWSE')"
        icon="i-lucide-folder-open"
        xs
        faded
        slate
        class="self-start"
        :disabled="!data.connection_id"
        @click="openBrowser(browser?.path || '/')"
      />
      <div
        v-if="browser"
        class="flex flex-col gap-1 p-2 border rounded-lg border-n-weak bg-n-solid-2"
      >
        <div class="flex items-center gap-1 text-xs">
          <Button
            icon="i-lucide-arrow-up"
            xs
            ghost
            slate
            :disabled="browser.path === '/'"
            @click="openBrowser(parentOf(browser.path))"
          />
          <span class="flex-1 font-mono truncate text-n-slate-12">{{
            browser.path
          }}</span>
          <Button
            :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.USE_FOLDER')"
            xs
            @click="useFolder(browser.path)"
          />
          <Button icon="i-lucide-x" xs ghost slate @click="browser = null" />
        </div>
        <span v-if="browser.loading" class="px-1 text-xs text-n-slate-10">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.LOADING') }}
        </span>
        <span v-else-if="browser.error" class="px-1 text-xs text-n-ruby-11">
          {{ browser.error }}
        </span>
        <span
          v-else-if="!browser.folders.length"
          class="px-1 text-xs text-n-slate-10"
        >
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.NO_SUBFOLDERS') }}
        </span>
        <div class="flex flex-col overflow-y-auto max-h-48">
          <button
            v-for="folder in browser.folders"
            :key="folder.path"
            type="button"
            class="flex items-center gap-1.5 px-1.5 py-1 text-xs text-left rounded-md hover:bg-n-alpha-1 text-n-slate-12"
            @click="openBrowser(folder.path)"
          >
            <Icon
              icon="i-lucide-folder"
              class="size-3.5 shrink-0 text-n-amber-10"
            />
            <span class="truncate">{{ folder.name }}</span>
          </button>
        </div>
      </div>
    </div>
    <TemplateField
      v-model="data.query"
      :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.QUERY')"
      placeholder="NF {{numero_nf}}"
      :hint="
        t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.QUERY_HINT', {
          example: 'NF {{numero_nf}}',
        })
      "
      :maxlength="500"
    />
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.EXTENSIONS') }}
      </span>
      <div class="flex flex-wrap gap-1">
        <button
          v-for="ext in EXTENSIONS"
          :key="ext"
          type="button"
          class="px-2 py-0.5 text-xs border rounded-full"
          :class="
            (data.extensions || []).includes(ext)
              ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
              : 'border-n-weak text-n-slate-11'
          "
          @click="toggleExtension(ext)"
        >
          .{{ ext }}
        </button>
      </div>
      <span class="text-xs text-n-slate-10">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.EXTENSIONS_HINT') }}
      </span>
    </div>
    <label
      class="flex items-center justify-between gap-3 text-sm text-n-slate-12"
    >
      {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.LIMIT') }}
      <input
        v-model.number="data.limit"
        type="number"
        min="1"
        max="10"
        class="!mb-0 !h-8 !w-20 text-sm"
        @blur="clampNumber('limit', 1, 10, 5)"
      />
    </label>
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.PICK') }}
      </span>
      <label
        v-for="pick in ['ask', 'first']"
        :key="pick"
        class="flex items-start gap-2 text-sm text-n-slate-12"
      >
        <input
          v-model="data.pick"
          type="radio"
          :value="pick"
          class="mt-1 !mb-0"
        />
        <span class="flex flex-col">
          {{ t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.PICKS.${pick}`) }}
          <span class="text-xs text-n-slate-10">
            {{ t(`OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.PICK_HINTS.${pick}`) }}
          </span>
        </span>
      </label>
    </div>
    <template v-if="data.pick === 'ask'">
      <TemplateField
        v-model="data.text"
        multiline
        :rows="2"
        :label="t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.LIST_TEXT')"
        :placeholder="
          t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.LIST_TEXT_PLACEHOLDER')
        "
        :maxlength="1000"
      />
      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.BUTTON') }}
        </span>
        <input
          v-model="data.button_label"
          type="text"
          maxlength="20"
          class="!mb-0 !h-8 text-sm"
        />
      </label>
      <label
        class="flex items-center justify-between gap-3 text-sm text-n-slate-12"
      >
        {{ t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.ATTEMPTS') }}
        <input
          v-model.number="data.max_attempts"
          type="number"
          min="1"
          max="5"
          class="!mb-0 !h-8 !w-20 text-sm"
          @blur="clampNumber('max_attempts', 1, 5, 2)"
        />
      </label>
    </template>
    <VariableName
      v-model="data.variable"
      fallback="documento"
      :hint="
        t('OUTSIDER_TOOLS.BOT.INTEGRATIONS.DOCS.VARIABLE_HINT', {
          name: `{{${data.variable || 'documento'}.nome}}`,
        })
      "
    />
    <BlockTester :node="node" />
  </div>
</template>
