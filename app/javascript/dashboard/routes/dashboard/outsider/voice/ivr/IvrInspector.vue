<script setup>
// OUTSIDER: painel da direita do editor da URA (Entrega 26): o que o bloco escolhido faz. Mexe direto no bloco do
// desenho (como o painel do bot); salvar manda o desenho todo, que o servidor limpa (Outsider::Voice::IvrGraph).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PromptField from './PromptField.vue';
import {
  DIGITS,
  MAX_OPTIONS,
  NODE_TYPES,
  TARGETS,
  newId,
  warningsOf,
} from './ivrNodes';

const props = defineProps({
  node: { type: Object, required: true },
  edges: { type: Array, required: true },
  flowId: { type: [Number, String], required: true },
  audios: { type: Array, default: () => [] },
  // { numbers, people, branches, natural_voice, voices }
  options: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['close', 'delete', 'duplicate', 'audioUploaded']);

const { t } = useI18n();

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

const data = computed(() => props.node.data);
const meta = computed(() => NODE_TYPES[props.node.type]);
const warnings = computed(() => warningsOf(props.node, props.edges, t));
const freeDigits = computed(() =>
  DIGITS.filter(
    digit => !(data.value.options || []).some(option => option.digit === digit)
  )
);

const addOption = () => {
  if (!freeDigits.value.length) return;
  data.value.options.push({
    id: newId('opt'),
    digit: freeDigits.value[0],
    label: '',
  });
};

const toggleUser = id => {
  const list = data.value.user_ids;
  const index = list.indexOf(id);
  if (index >= 0) list.splice(index, 1);
  else list.push(id);
};

const number = (field, min, max) => ({
  value: data.value[field],
  min,
  max,
  onChange: event => {
    const value = Number(event.target.value);
    data.value[field] = Number.isFinite(value)
      ? Math.min(Math.max(Math.round(value), min), max)
      : min;
  },
});
</script>

<template>
  <aside
    class="flex flex-col w-[22rem] max-w-full h-full border-l shrink-0 border-n-weak bg-n-solid-2"
    data-testid="ivr-inspector"
  >
    <header
      class="flex items-center gap-2 px-4 py-3 border-b border-n-weak shrink-0"
    >
      <span
        class="flex items-center justify-center text-white rounded-md size-7 shrink-0"
        :class="meta.color"
      >
        <Icon :icon="meta.icon" class="size-4" />
      </span>
      <span class="flex flex-col flex-1 min-w-0">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t(`OUTSIDER_VOICE.IVR.TYPES.${node.type}`) }}
        </span>
        <span class="text-xs truncate text-n-slate-11">
          {{ t(`OUTSIDER_VOICE.IVR.HINTS.${node.type}`) }}
        </span>
      </span>
      <Button
        v-if="node.type !== 'start'"
        xs
        ghost
        slate
        icon="i-lucide-copy"
        :title="t('OUTSIDER_VOICE.IVR.EDITOR.DUPLICATE')"
        @click="emit('duplicate')"
      />
      <Button
        v-if="node.type !== 'start'"
        xs
        ghost
        ruby
        icon="i-lucide-trash-2"
        :title="t('OUTSIDER_VOICE.IVR.EDITOR.DELETE_BLOCK')"
        @click="emit('delete')"
      />
      <Button xs ghost slate icon="i-lucide-x" @click="emit('close')" />
    </header>

    <div class="flex flex-col flex-1 min-h-0 gap-4 p-4 overflow-y-auto">
      <ul
        v-if="warnings.length"
        class="flex flex-col gap-1 px-3 py-2 mb-0 text-xs list-none rounded-lg bg-n-amber-3 text-n-amber-11"
      >
        <li v-for="warning in warnings" :key="warning">{{ warning }}</li>
      </ul>

      <!-- Início -->
      <template v-if="node.type === 'start'">
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.START_HELP') }}
        </p>
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.VOICE') }}
          </span>
          <select
            v-model="data.voice"
            class="!mb-0"
            :disabled="!options.natural_voice"
          >
            <option
              v-for="voice in options.voices || []"
              :key="voice"
              :value="voice"
            >
              {{ voice }}
            </option>
          </select>
          <span class="text-xs text-n-slate-11">
            {{
              options.natural_voice
                ? t('OUTSIDER_VOICE.IVR.INSPECTOR.VOICE_NATURAL')
                : t('OUTSIDER_VOICE.IVR.INSPECTOR.VOICE_CENTRAL')
            }}
          </span>
        </label>
      </template>

      <!-- Falar, Menu, Pedir dígitos, Transferir, Recado e Encerrar: o que a URA fala -->
      <template v-if="['menu', 'collect'].includes(node.type)">
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.LABEL') }}
          </span>
          <input
            v-model="data.label"
            maxlength="40"
            class="!mb-0"
            :placeholder="t('OUTSIDER_VOICE.IVR.INSPECTOR.LABEL_PLACEHOLDER')"
          />
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.LABEL_HELP') }}
          </span>
        </label>
      </template>

      <PromptField
        v-if="
          node.type !== 'start' &&
          node.type !== 'hours' &&
          node.type !== 'caller'
        "
        v-model="data.prompt"
        :label="
          node.type === 'transfer'
            ? t('OUTSIDER_VOICE.IVR.INSPECTOR.PROMPT_BEFORE_TRANSFER')
            : node.type === 'hangup'
              ? t('OUTSIDER_VOICE.IVR.INSPECTOR.PROMPT_BEFORE_HANGUP')
              : t('OUTSIDER_VOICE.IVR.INSPECTOR.PROMPT')
        "
        :flow-id="flowId"
        :audios="audios"
        @uploaded="emit('audioUploaded', $event)"
      />

      <!-- Menu -->
      <template v-if="node.type === 'menu'">
        <div class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.OPTIONS') }}
          </span>
          <div
            v-for="(option, index) in data.options"
            :key="option.id"
            class="flex items-center gap-1.5"
          >
            <select v-model="option.digit" class="!mb-0 !w-16 shrink-0">
              <option
                v-for="digit in [option.digit, ...freeDigits]"
                :key="digit"
                :value="digit"
              >
                {{ digit }}
              </option>
            </select>
            <input
              v-model="option.label"
              maxlength="40"
              class="flex-1 min-w-0 !mb-0"
              :placeholder="t('OUTSIDER_VOICE.IVR.INSPECTOR.OPTION_LABEL')"
            />
            <Button
              xs
              ghost
              ruby
              icon="i-lucide-trash-2"
              @click="data.options.splice(index, 1)"
            />
          </div>
          <Button
            xs
            faded
            icon="i-lucide-plus"
            class="self-start"
            :label="t('OUTSIDER_VOICE.IVR.INSPECTOR.ADD_OPTION')"
            :disabled="data.options.length >= MAX_OPTIONS || !freeDigits.length"
            @click="addOption"
          />
        </div>
      </template>

      <!-- Pedir dígitos -->
      <template v-if="node.type === 'collect'">
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.VARIABLE') }}
          </span>
          <input
            v-model="data.variable"
            maxlength="30"
            class="!mb-0 font-mono"
          />
        </label>
        <div class="grid grid-cols-2 gap-2">
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.MIN_DIGITS') }}
            </span>
            <input
              type="number"
              class="!mb-0"
              v-bind="number('min_digits', 1, 20)"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.MAX_DIGITS') }}
            </span>
            <input
              type="number"
              class="!mb-0"
              v-bind="number('max_digits', 1, 20)"
            />
          </label>
        </div>
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.COLLECT_HELP') }}
        </span>
      </template>

      <template v-if="['menu', 'collect'].includes(node.type)">
        <div class="grid grid-cols-2 gap-2">
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.TIMEOUT') }}
            </span>
            <input
              type="number"
              class="!mb-0"
              v-bind="number('timeout', 2, 30)"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.ATTEMPTS') }}
            </span>
            <input
              type="number"
              class="!mb-0"
              v-bind="number('max_attempts', 1, 5)"
            />
          </label>
        </div>
        <PromptField
          v-model="data.invalid_prompt"
          :label="t('OUTSIDER_VOICE.IVR.INSPECTOR.INVALID_PROMPT')"
          :placeholder="t('OUTSIDER_VOICE.IVR.INSPECTOR.INVALID_PLACEHOLDER')"
          :flow-id="flowId"
          :audios="audios"
          @uploaded="emit('audioUploaded', $event)"
        />
      </template>

      <!-- Horário de atendimento -->
      <template v-if="node.type === 'hours'">
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
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
                class="!mb-0 !h-8 !w-auto"
              />
              <span class="text-n-slate-11">–</span>
              <input
                v-model="data.hours[day].end"
                type="time"
                class="!mb-0 !h-8 !w-auto"
              />
            </template>
          </div>
        </div>
      </template>

      <!-- Quem está ligando -->
      <p v-if="node.type === 'caller'" class="mb-0 text-sm text-n-slate-11">
        {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.CALLER_HELP') }}
      </p>

      <!-- Transferir -->
      <template v-if="node.type === 'transfer'">
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.TARGET') }}
          </span>
          <select v-model="data.target" class="!mb-0">
            <option v-for="target in TARGETS" :key="target" :value="target">
              {{ t(`OUTSIDER_VOICE.IVR.TARGETS.${target}`) }}
            </option>
          </select>
          <span class="text-xs text-n-slate-11">
            {{ t(`OUTSIDER_VOICE.IVR.TARGET_HELP.${data.target}`) }}
          </span>
        </label>
        <div v-if="data.target === 'users'" class="flex flex-col gap-1">
          <label
            v-for="person in options.people || []"
            :key="person.id"
            class="flex items-center gap-2 text-sm text-n-slate-12"
          >
            <input
              type="checkbox"
              class="!mb-0"
              :checked="data.user_ids.includes(person.id)"
              @change="toggleUser(person.id)"
            />
            {{ person.name }}
            <span class="text-xs text-n-slate-11">{{ person.extension }}</span>
          </label>
          <p
            v-if="!(options.people || []).length"
            class="mb-0 text-xs text-n-slate-11"
          >
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.NO_PEOPLE') }}
          </p>
        </div>
        <select
          v-if="data.target === 'branch'"
          v-model="data.branch_id"
          class="!mb-0"
        >
          <option :value="null" disabled>
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.PICK_BRANCH') }}
          </option>
          <option
            v-for="branch in options.branches || []"
            :key="branch.id"
            :value="branch.id"
          >
            {{ branch.name }}
          </option>
        </select>
        <input
          v-if="data.target === 'number'"
          v-model="data.number"
          type="tel"
          maxlength="15"
          class="!mb-0"
          :placeholder="t('OUTSIDER_VOICE.IVR.INSPECTOR.NUMBER_PLACEHOLDER')"
        />
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.RING_SECONDS') }}
          </span>
          <input
            type="number"
            class="!mb-0"
            v-bind="number('ring_seconds', 10, 120)"
          />
        </label>
      </template>

      <!-- Recado -->
      <template v-if="node.type === 'voicemail'">
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.MAX_SECONDS') }}
          </span>
          <input
            type="number"
            class="!mb-0"
            v-bind="number('max_seconds', 10, 300)"
          />
        </label>
        <span class="text-xs text-n-slate-11">
          {{ t('OUTSIDER_VOICE.IVR.INSPECTOR.VOICEMAIL_HELP') }}
        </span>
      </template>
    </div>
  </aside>
</template>
