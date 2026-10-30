<script setup>
// OUTSIDER: painel da direita do editor do bot: as configurações do bloco escolhido. Mexe direto no
// bloco (v-model no node.data); o editor guarda o histórico para desfazer.
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  NODE_TYPES,
  MAX_OPTIONS,
  MAX_BUTTONS,
  VARIABLES,
  newId,
} from './nodeTypes';

const props = defineProps({
  node: { type: Object, required: true },
  warnings: { type: Array, default: () => [] },
});

const emit = defineEmits(['delete', 'duplicate', 'close']);

const { t } = useI18n();
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');
const labels = useMapGetter('labels/getLabels');

const data = computed(() => props.node.data);
const meta = computed(() => NODE_TYPES[props.node.type]);

const TRIGGERS = ['unassigned_message', 'new_conversation', 'keyword'];
const STYLES = ['list', 'buttons', 'text'];
const CONTACT_FIELDS = ['', 'name', 'email', 'company_name', 'city'];
const PRIORITIES = ['', 'low', 'medium', 'high', 'urgent'];
const DAYS = ['1', '2', '3', '4', '5', '6', '0'];
const TIMEZONES = [
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Cuiaba',
  'America/Belem',
  'America/Fortaleza',
  'America/Recife',
  'America/Rio_Branco',
  'America/Noronha',
];

const splitWords = value =>
  value
    .split(/[,;\n]/)
    .map(word => word.trim())
    .filter(Boolean);

// o texto digitado fica num rascunho (senão a vírgula some ao digitar); a lista vai para o bloco
const keywordsDraft = ref('');
const routeDrafts = reactive({});
watch(
  () => props.node,
  () => {
    keywordsDraft.value = (data.value.keywords || []).join(', ');
    Object.keys(routeDrafts).forEach(key => delete routeDrafts[key]);
  },
  { immediate: true }
);
const keywordsText = computed({
  get: () => keywordsDraft.value,
  set: value => {
    keywordsDraft.value = value;
    data.value.keywords = splitWords(value);
  },
});

const maxOptions = computed(() =>
  data.value.style === 'buttons' ? MAX_BUTTONS : MAX_OPTIONS
);

const addOption = () => {
  data.value.options.push({
    id: newId('opt'),
    label: t('OUTSIDER_TOOLS.BOT.INSPECTOR.NEW_OPTION', {
      number: data.value.options.length + 1,
    }),
    description: '',
  });
};

const moveItem = (list, index, offset) => {
  const target = index + offset;
  if (target < 0 || target >= list.length) return;
  const [item] = list.splice(index, 1);
  list.splice(target, 0, item);
};

const addRoute = () => {
  data.value.routes.push({ id: newId('rt'), label: '', keywords: [] });
};

const routeKeywordsText = route =>
  routeDrafts[route.id] ?? (route.keywords || []).join(', ');
const setRouteKeywords = (route, value) => {
  routeDrafts[route.id] = value;
  route.keywords = splitWords(value);
};

const toggleLabel = title => {
  const list = data.value.labels || [];
  data.value.labels = list.includes(title)
    ? list.filter(item => item !== title)
    : [...list, title];
};

const insertVariable = (key, variable) => {
  data.value[key] = `${data.value[key] || ''}${variable}`;
};

// número: guarda o que foi digitado e só acerta o limite ao sair do campo
const numberValue = key =>
  computed({
    get: () => data.value[key],
    set: value => {
      const number = Number(value);
      data.value[key] = value === '' || !Number.isFinite(number) ? '' : number;
    },
  });
const clamp = (key, min, max) => {
  const number = Number(data.value[key]);
  data.value[key] = Number.isFinite(number)
    ? Math.min(Math.max(Math.round(number), min), max)
    : min;
};
const cooldown = numberValue('cooldown_hours');
const timeout = numberValue('timeout_minutes');
const delay = numberValue('delay_seconds');
const attempts = numberValue('max_attempts');

const idOrNull = value => (value ? Number(value) : null);
</script>

<template>
  <aside
    class="flex flex-col w-[22rem] max-w-full h-full border-l border-n-weak bg-n-solid-1"
  >
    <header class="flex items-center gap-2 px-4 py-3 border-b border-n-weak">
      <span
        class="flex items-center justify-center rounded-md size-7 shrink-0 text-white"
        :class="meta.color"
      >
        <Icon :icon="meta.icon" class="size-4" />
      </span>
      <div class="flex flex-col min-w-0">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t(`OUTSIDER_TOOLS.BOT.TYPES.${node.type}`) }}
        </span>
        <span class="text-xs truncate text-n-slate-11">
          {{ t(`OUTSIDER_TOOLS.BOT.TYPE_HINTS.${node.type}`) }}
        </span>
      </div>
      <Button
        icon="i-lucide-x"
        xs
        ghost
        slate
        class="ml-auto"
        @click="emit('close')"
      />
    </header>

    <div class="flex flex-col flex-1 gap-4 p-4 overflow-y-auto">
      <div
        v-if="warnings.length"
        class="flex flex-col gap-1 p-2.5 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
      >
        <span
          v-for="warning in warnings"
          :key="warning"
          class="flex items-start gap-1.5"
        >
          <Icon
            icon="i-lucide-triangle-alert"
            class="size-3.5 mt-px shrink-0"
          />
          {{ warning }}
        </span>
      </div>

      <!-- Início -->
      <template v-if="node.type === 'start'">
        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.TRIGGER') }}
          </span>
          <label
            v-for="trigger in TRIGGERS"
            :key="trigger"
            class="flex items-start gap-2 p-2.5 border rounded-lg cursor-pointer"
            :class="
              data.trigger === trigger
                ? 'border-n-brand bg-n-brand/5'
                : 'border-n-weak hover:bg-n-alpha-1'
            "
          >
            <input
              v-model="data.trigger"
              type="radio"
              :value="trigger"
              class="mt-1 !mb-0"
            />
            <span class="flex flex-col">
              <span class="text-sm text-n-slate-12">
                {{ t(`OUTSIDER_TOOLS.BOT.TRIGGERS.${trigger}.TITLE`) }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t(`OUTSIDER_TOOLS.BOT.TRIGGERS.${trigger}.HINT`) }}
              </span>
            </span>
          </label>
        </div>
        <Input
          v-if="data.trigger === 'keyword'"
          v-model="keywordsText"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.KEYWORDS')"
          :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.KEYWORDS_PLACEHOLDER')"
          :message="t('OUTSIDER_TOOLS.BOT.INSPECTOR.KEYWORDS_HINT')"
        />
        <Input
          v-if="data.trigger === 'unassigned_message'"
          v-model="cooldown"
          type="number"
          min="0"
          max="720"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.COOLDOWN')"
          :message="t('OUTSIDER_TOOLS.BOT.INSPECTOR.COOLDOWN_HINT')"
          @blur="clamp('cooldown_hours', 0, 720)"
        />
        <Input
          v-model="timeout"
          type="number"
          min="5"
          max="1440"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.TIMEOUT')"
          :message="t('OUTSIDER_TOOLS.BOT.INSPECTOR.TIMEOUT_HINT')"
          @blur="clamp('timeout_minutes', 5, 1440)"
        />
        <label class="flex items-start justify-between gap-3">
          <span class="flex flex-col">
            <span class="text-sm text-n-slate-12">
              {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.SET_PENDING') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.SET_PENDING_HINT') }}
            </span>
          </span>
          <Switch v-model="data.set_pending" />
        </label>
        <label class="flex items-start justify-between gap-3">
          <span class="flex flex-col">
            <span class="text-sm text-n-slate-12">
              {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.ONLY_UNASSIGNED') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.ONLY_UNASSIGNED_HINT') }}
            </span>
          </span>
          <Switch v-model="data.only_unassigned" />
        </label>
      </template>

      <!-- textos (mensagem, menu, pergunta, passar para a equipe, fim) -->
      <div
        v-if="
          ['message', 'menu', 'question', 'handoff', 'end'].includes(node.type)
        "
        class="flex flex-col gap-1.5"
      >
        <TextArea
          v-model="data.text"
          :label="
            t(`OUTSIDER_TOOLS.BOT.INSPECTOR.TEXT_${node.type.toUpperCase()}`)
          "
          :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.TEXT_PLACEHOLDER')"
          :max-length="4096"
          auto-height
          custom-text-area-class="min-h-[5rem]"
        />
        <div class="flex flex-wrap gap-1">
          <button
            v-for="variable in VARIABLES"
            :key="variable"
            type="button"
            class="px-1.5 py-0.5 text-[11px] rounded-md bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12"
            @click="insertVariable('text', variable)"
          >
            {{ variable }}
          </button>
        </div>
        <span class="text-xs text-n-slate-10">
          {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.FORMAT_HINT') }}
        </span>
      </div>

      <!-- Mensagem -->
      <Input
        v-if="node.type === 'message'"
        v-model="delay"
        type="number"
        min="0"
        max="30"
        :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.DELAY')"
        :message="t('OUTSIDER_TOOLS.BOT.INSPECTOR.DELAY_HINT')"
        @blur="clamp('delay_seconds', 0, 30)"
      />

      <!-- Menu -->
      <template v-if="node.type === 'menu'">
        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.STYLE') }}
          </span>
          <div class="grid grid-cols-3 gap-1.5">
            <button
              v-for="style in STYLES"
              :key="style"
              type="button"
              class="flex flex-col items-center gap-1 px-2 py-2 text-xs border rounded-lg"
              :class="
                data.style === style
                  ? 'border-n-brand bg-n-brand/5 text-n-slate-12'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
              "
              @click="data.style = style"
            >
              <Icon
                :icon="
                  {
                    list: 'i-lucide-list',
                    buttons: 'i-lucide-rectangle-horizontal',
                    text: 'i-lucide-list-ordered',
                  }[style]
                "
                class="size-4"
              />
              {{ t(`OUTSIDER_TOOLS.BOT.STYLES.${style}`) }}
            </button>
          </div>
          <span class="text-xs text-n-slate-11">
            {{ t(`OUTSIDER_TOOLS.BOT.STYLE_HINTS.${data.style}`) }}
          </span>
        </div>
        <Input
          v-if="data.style !== 'text'"
          v-model="data.title"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.MENU_TITLE')"
          :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.OPTIONAL')"
        />
        <Input
          v-if="data.style === 'list'"
          v-model="data.button_label"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.BUTTON_LABEL')"
          :message="t('OUTSIDER_TOOLS.BOT.INSPECTOR.BUTTON_LABEL_HINT')"
        />
        <Input
          v-model="data.footer"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.FOOTER')"
          :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.OPTIONAL')"
        />
        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{
              t('OUTSIDER_TOOLS.BOT.INSPECTOR.OPTIONS', {
                count: data.options.length,
                max: maxOptions,
              })
            }}
          </span>
          <div
            v-for="(option, index) in data.options"
            :key="option.id"
            class="flex flex-col gap-1.5 p-2 border rounded-lg border-n-weak"
          >
            <div class="flex items-center gap-1">
              <span class="w-5 text-xs text-center text-n-slate-10">
                {{ index + 1 }}
              </span>
              <input
                v-model="option.label"
                maxlength="24"
                class="flex-1 min-w-0 !mb-0 !h-8 text-sm"
                :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.OPTION_LABEL')"
              />
              <Button
                icon="i-lucide-arrow-up"
                xs
                ghost
                slate
                :disabled="index === 0"
                @click="moveItem(data.options, index, -1)"
              />
              <Button
                icon="i-lucide-arrow-down"
                xs
                ghost
                slate
                :disabled="index === data.options.length - 1"
                @click="moveItem(data.options, index, 1)"
              />
              <Button
                icon="i-lucide-trash-2"
                xs
                ghost
                ruby
                @click="data.options.splice(index, 1)"
              />
            </div>
            <input
              v-if="data.style === 'list'"
              v-model="option.description"
              maxlength="72"
              class="!mb-0 !h-8 text-xs ltr:ml-6 rtl:mr-6"
              :placeholder="
                t('OUTSIDER_TOOLS.BOT.INSPECTOR.OPTION_DESCRIPTION')
              "
            />
          </div>
          <Button
            :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.ADD_OPTION')"
            icon="i-lucide-plus"
            xs
            faded
            :disabled="data.options.length >= MAX_OPTIONS"
            @click="addOption"
          />
        </div>
        <TextArea
          v-model="data.invalid_text"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.INVALID_TEXT')"
          :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.INVALID_PLACEHOLDER')"
          :max-length="1000"
          auto-height
        />
        <Input
          v-model="attempts"
          type="number"
          min="1"
          max="5"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.MAX_ATTEMPTS')"
          :message="t('OUTSIDER_TOOLS.BOT.INSPECTOR.MAX_ATTEMPTS_HINT')"
          @blur="clamp('max_attempts', 1, 5)"
        />
      </template>

      <!-- Pergunta (texto livre / chatbot) -->
      <template v-if="node.type === 'question'">
        <Input
          v-model="data.variable"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.VARIABLE')"
          :message="
            t('OUTSIDER_TOOLS.BOT.INSPECTOR.VARIABLE_HINT', {
              variable: `{{${data.variable || 'resposta'}}}`,
            })
          "
        />
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.CONTACT_FIELD') }}
          </span>
          <select v-model="data.contact_field" class="!mb-0">
            <option v-for="field in CONTACT_FIELDS" :key="field" :value="field">
              {{ t(`OUTSIDER_TOOLS.BOT.CONTACT_FIELDS.${field || 'none'}`) }}
            </option>
          </select>
        </label>
        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.ROUTES') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.ROUTES_HINT') }}
          </span>
          <div
            v-for="(route, index) in data.routes"
            :key="route.id"
            class="flex flex-col gap-1.5 p-2 border rounded-lg border-n-weak"
          >
            <div class="flex items-center gap-1">
              <input
                v-model="route.label"
                maxlength="40"
                class="flex-1 min-w-0 !mb-0 !h-8 text-sm"
                :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.ROUTE_LABEL')"
              />
              <Button
                icon="i-lucide-trash-2"
                xs
                ghost
                ruby
                @click="data.routes.splice(index, 1)"
              />
            </div>
            <input
              :value="routeKeywordsText(route)"
              class="!mb-0 !h-8 text-xs"
              :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.ROUTE_KEYWORDS')"
              @input="setRouteKeywords(route, $event.target.value)"
            />
          </div>
          <Button
            :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.ADD_ROUTE')"
            icon="i-lucide-plus"
            xs
            faded
            :disabled="data.routes.length >= MAX_OPTIONS"
            @click="addRoute"
          />
        </div>
      </template>

      <!-- Horário -->
      <template v-if="node.type === 'condition'">
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.TIMEZONE') }}
          </span>
          <select v-model="data.timezone" class="!mb-0">
            <option v-for="zone in TIMEZONES" :key="zone" :value="zone">
              {{ zone.replace('America/', '').replace('_', ' ') }}
            </option>
          </select>
        </label>
        <div class="flex flex-col gap-1.5">
          <div
            v-for="day in DAYS"
            :key="day"
            class="flex items-center gap-2 text-sm"
          >
            <label class="flex items-center w-24 gap-2 shrink-0">
              <input
                v-model="data.hours[day].enabled"
                type="checkbox"
                class="!mb-0"
              />
              {{ t(`OUTSIDER_TOOLS.BOT.DAYS.${day}`) }}
            </label>
            <template v-if="data.hours[day].enabled">
              <input
                v-model="data.hours[day].start"
                type="time"
                class="!mb-0 !h-8 !w-24 text-sm"
              />
              <span class="text-n-slate-10">–</span>
              <input
                v-model="data.hours[day].end"
                type="time"
                class="!mb-0 !h-8 !w-24 text-sm"
              />
            </template>
            <span v-else class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.CLOSED') }}
            </span>
          </div>
        </div>
      </template>

      <!-- Ação e Passar para a equipe -->
      <template v-if="['action', 'handoff'].includes(node.type)">
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.TEAM') }}
          </span>
          <select
            :value="data.team_id || ''"
            class="!mb-0"
            @change="data.team_id = idOrNull($event.target.value)"
          >
            <option value="">
              {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.KEEP') }}
            </option>
            <option v-for="team in teams" :key="team.id" :value="team.id">
              {{ team.name }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.AGENT') }}
          </span>
          <select
            :value="data.assignee_id || ''"
            class="!mb-0"
            @change="data.assignee_id = idOrNull($event.target.value)"
          >
            <option value="">
              {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.NOBODY') }}
            </option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>
        </label>
      </template>
      <template v-if="node.type === 'action'">
        <div class="flex flex-col gap-1.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.LABELS') }}
          </span>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="label in labels"
              :key="label.id"
              type="button"
              class="flex items-center gap-1 px-2 py-1 text-xs border rounded-full"
              :class="
                (data.labels || []).includes(label.title)
                  ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                  : 'border-n-weak text-n-slate-11'
              "
              @click="toggleLabel(label.title)"
            >
              <span
                class="rounded-full size-2"
                :style="{ backgroundColor: label.color }"
              />
              {{ label.title }}
            </button>
            <span v-if="!labels.length" class="text-xs text-n-slate-10">
              {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.NO_LABELS') }}
            </span>
          </div>
        </div>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.PRIORITY') }}
          </span>
          <select
            :value="data.priority || ''"
            class="!mb-0"
            @change="data.priority = $event.target.value || null"
          >
            <option
              v-for="priority in PRIORITIES"
              :key="priority"
              :value="priority"
            >
              {{
                priority
                  ? t(`OUTSIDER_TOOLS.BOT.PRIORITIES.${priority}`)
                  : t('OUTSIDER_TOOLS.BOT.INSPECTOR.KEEP')
              }}
            </option>
          </select>
        </label>
        <TextArea
          v-model="data.note"
          :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.NOTE')"
          :placeholder="t('OUTSIDER_TOOLS.BOT.INSPECTOR.NOTE_PLACEHOLDER')"
          :max-length="2000"
          auto-height
        />
      </template>

      <!-- Fim -->
      <label
        v-if="node.type === 'end'"
        class="flex items-start justify-between gap-3"
      >
        <span class="flex flex-col">
          <span class="text-sm text-n-slate-12">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.RESOLVE') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_TOOLS.BOT.INSPECTOR.RESOLVE_HINT') }}
          </span>
        </span>
        <Switch v-model="data.resolve" />
      </label>
    </div>

    <footer
      v-if="node.type !== 'start'"
      class="flex gap-2 px-4 py-3 border-t border-n-weak"
    >
      <Button
        :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.DUPLICATE')"
        icon="i-lucide-copy"
        xs
        faded
        slate
        @click="emit('duplicate')"
      />
      <Button
        :label="t('OUTSIDER_TOOLS.BOT.INSPECTOR.DELETE')"
        icon="i-lucide-trash-2"
        xs
        faded
        ruby
        @click="emit('delete')"
      />
    </footer>
  </aside>
</template>
