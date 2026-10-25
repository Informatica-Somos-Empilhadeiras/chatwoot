<script setup>
// OUTSIDER: Configurações > Telefonia (Entrega 22; ver app/services/outsider/voice/settings.rb). Os dados que a
// operadora manda (colados no quadro de texto ou digitados), os números por estado, os ramais e as regras de
// toque. Mostra também se a central está conectada, registrada na operadora e quais ramais estão online.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SettingsSection from './SettingsSection.vue';
import { errorMessage } from '../../helpers';
import { STATES, stateForNumber } from '../../../voice/brazil';
import { formatPhone } from '../../../voice/format';
import { parseOperatorText } from '../../../voice/operatorText';

const FIRST_EXTENSION = 201;

const { t } = useI18n();

const form = ref(null);
const status = ref({});
const install = ref({});
const people = ref([]);
const password = ref('');
const ipsText = ref('');
const pasteText = ref('');
const pasteResult = ref('');
const errors = ref([]);
const isLoading = ref(true);
const isSaving = ref(false);

const stateOptions = STATES.map(state => ({ value: state, label: state }));
const optionsFor = (keys, prefix) =>
  keys.map(key => ({ value: key, label: t(`${prefix}.${key}`) }));
const transportOptions = ['udp', 'tcp'].map(key => ({
  value: key,
  label: key.toUpperCase(),
}));
const authOptions = computed(() =>
  optionsFor(['register', 'ip'], 'OUTSIDER_VOICE.SETTINGS.TRUNK.AUTH_OPTIONS')
);
const dialOptions = computed(() =>
  optionsFor(
    ['ddd', 'zero_ddd', 'country'],
    'OUTSIDER_VOICE.SETTINGS.TRUNK.DIAL_FORMATS'
  )
);

const hasError = key => errors.value.includes(key);

const centralUrl = computed(
  () =>
    `http://127.0.0.1:3000/outsider/voice/central/${install.value.account_id}`
);

const peopleById = computed(() =>
  Object.fromEntries(people.value.map(person => [String(person.id), person]))
);

const connectedNames = computed(() =>
  (status.value.extensions || [])
    .map(extension => {
      const entry = Object.entries(form.value.agents).find(
        ([, agent]) => agent.extension === extension
      );
      const name = entry && peopleById.value[entry[0]]?.name;
      return name ? `${extension} (${name})` : extension;
    })
    .join(', ')
);

const registrationLabel = computed(() => {
  const key = status.value.registration || 'NONE';
  const path = `OUTSIDER_VOICE.SETTINGS.STATUS.REGISTRATION.${key}`;
  return t(path) === path
    ? t('OUTSIDER_VOICE.SETTINGS.STATUS.REGISTRATION.NONE')
    : t(path);
});

const centralLabel = computed(() => {
  if (status.value.online) return t('OUTSIDER_VOICE.SETTINGS.STATUS.ONLINE');
  if (!status.value.seen_at) return t('OUTSIDER_VOICE.SETTINGS.STATUS.NEVER');
  return t('OUTSIDER_VOICE.SETTINGS.STATUS.OFFLINE', {
    time: new Date(status.value.seen_at).toLocaleString(),
  });
});

const apply = data => {
  const settings = JSON.parse(JSON.stringify(data.settings));
  settings.numbers = settings.numbers.map(row => ({
    ...row,
    number: formatPhone(row.number),
  }));
  data.people.forEach(person => {
    settings.agents[person.id] ||= { extension: '', state: '', enabled: false };
    settings.agents[person.id].state ||= '';
  });
  form.value = settings;
  ipsText.value = settings.trunk.ips.join('\n');
  password.value = '';
  status.value = data.status;
  install.value = data.install;
  people.value = data.people;
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await VoiceAPI.getSettings();
    apply(data);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

// ligar o ramal de quem ainda não tem número: o próximo livre a partir do 201
const toggleAgent = agent => {
  agent.enabled = !agent.enabled;
  if (!agent.enabled || agent.extension) return;
  const used = Object.values(form.value.agents).map(row => row.extension);
  let next = FIRST_EXTENSION;
  while (used.includes(String(next))) next += 1;
  agent.extension = String(next);
};

const addNumber = (number = '') => {
  form.value.numbers.push({
    number: formatPhone(number),
    state: stateForNumber(number),
    label: '',
  });
};

const suggestState = row => {
  row.state ||= stateForNumber(row.number);
};

const fillFromText = () => {
  const { trunk, numbers } = parseOperatorText(pasteText.value);
  const found = [
    'host',
    'port',
    'transport',
    'username',
    'auth_username',
    'password',
    'ips',
  ].filter(key => (key === 'ips' ? trunk.ips.length : trunk[key]));
  if (!found.length && !numbers.length) {
    pasteResult.value = t('OUTSIDER_VOICE.SETTINGS.PASTE.NOTHING');
    return;
  }
  const { password: pasted, ips, ...rest } = trunk;
  Object.assign(form.value.trunk, rest);
  if (pasted) password.value = pasted;
  if (ips.length) ipsText.value = ips.join('\n');
  const known = form.value.numbers.map(row => row.number.replace(/\D/g, ''));
  numbers
    .filter(number => !known.some(digits => digits.endsWith(number)))
    .forEach(number => addNumber(number));
  pasteResult.value = t('OUTSIDER_VOICE.SETTINGS.PASTE.FILLED', {
    fields: [...found, ...(numbers.length ? ['numbers'] : [])]
      .map(key => t(`OUTSIDER_VOICE.SETTINGS.PASTE.FIELDS.${key}`))
      .join(', '),
  });
};

const payload = () => {
  const { password_set: passwordSet, ...trunk } = form.value.trunk;
  return {
    ...form.value,
    trunk: {
      ...trunk,
      password: password.value,
      ips: ipsText.value.split(/[\s,;]+/).filter(Boolean),
    },
    agents: Object.fromEntries(
      Object.entries(form.value.agents).filter(
        ([, agent]) => agent.extension || agent.enabled
      )
    ),
  };
};

const save = async () => {
  isSaving.value = true;
  errors.value = [];
  try {
    const { data } = await VoiceAPI.updateSettings(payload());
    apply(data);
    useAlert(t('OUTSIDER_VOICE.SETTINGS.SAVED'));
  } catch (error) {
    errors.value = error?.response?.data?.fields || [];
    useAlert(
      errors.value.length
        ? t('OUTSIDER_VOICE.SETTINGS.INVALID')
        : errorMessage(t, error)
    );
  } finally {
    isSaving.value = false;
  }
};

onMounted(load);
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_VOICE.SETTINGS.TITLE')"
    :description="t('OUTSIDER_VOICE.SETTINGS.DESCRIPTION')"
  >
    <template #actions>
      <Button
        size="sm"
        :label="t('OUTSIDER_CRM.SAVE')"
        :is-loading="isSaving"
        :disabled="isLoading"
        data-testid="voice-settings-save"
        @click="save"
      />
    </template>

    <Spinner v-if="isLoading" :size="20" class="text-n-slate-10" />
    <template v-else>
      <!-- central: ligada, conectada, registrada e ramais online -->
      <div
        class="flex flex-col gap-3 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <label class="flex items-start gap-3 cursor-pointer">
          <Switch v-model="form.enabled" class="mt-0.5" />
          <span class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.SETTINGS.ENABLED') }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_VOICE.SETTINGS.ENABLED_HELP') }}
            </span>
          </span>
        </label>
        <ul
          class="flex flex-col gap-1.5 pt-3 mb-0 text-sm list-none border-t border-n-weak"
          data-testid="voice-central-status"
        >
          <li class="flex items-center gap-2">
            <span
              class="rounded-full size-2 shrink-0"
              :class="status.online ? 'bg-n-teal-9' : 'bg-n-ruby-9'"
            />
            <span class="text-n-slate-12">{{ centralLabel }}</span>
          </li>
          <li v-if="status.online" class="flex items-center gap-2">
            <span
              class="rounded-full size-2 shrink-0"
              :class="
                status.registration === 'Registered'
                  ? 'bg-n-teal-9'
                  : 'bg-n-amber-9'
              "
            />
            <span class="text-n-slate-12">{{ registrationLabel }}</span>
          </li>
          <li v-if="status.online" class="flex items-center gap-2">
            <span class="rounded-full size-2 shrink-0 bg-n-slate-8" />
            <span class="text-n-slate-11">
              {{
                connectedNames
                  ? t('OUTSIDER_VOICE.SETTINGS.STATUS.EXTENSIONS', {
                      list: connectedNames,
                    })
                  : t('OUTSIDER_VOICE.SETTINGS.STATUS.NO_EXTENSIONS')
              }}
            </span>
          </li>
          <li class="flex items-center gap-2">
            <span
              class="rounded-full size-2 shrink-0"
              :class="install.token_set ? 'bg-n-teal-9' : 'bg-n-ruby-9'"
            />
            <span class="text-n-slate-11">
              {{
                install.token_set
                  ? t('OUTSIDER_VOICE.SETTINGS.STATUS.TOKEN_OK')
                  : t('OUTSIDER_VOICE.SETTINGS.STATUS.TOKEN_MISSING')
              }}
            </span>
          </li>
          <li class="flex flex-wrap items-center gap-2 text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.SETTINGS.STATUS.CENTRAL_URL') }}
            <code
              class="px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-12 break-all"
            >
              {{ centralUrl }}
            </code>
          </li>
        </ul>
      </div>

      <!-- operadora: colar o texto ou preencher -->
      <div
        class="flex flex-col gap-4 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="flex flex-col gap-1">
          <h4 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.SETTINGS.PASTE.TITLE') }}
          </h4>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.SETTINGS.PASTE.DESCRIPTION') }}
          </p>
        </div>
        <div class="flex flex-col gap-2">
          <textarea
            v-model="pasteText"
            rows="4"
            :placeholder="t('OUTSIDER_VOICE.SETTINGS.PASTE.PLACEHOLDER')"
            class="w-full !mb-0 px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand"
            data-testid="voice-paste"
          />
          <div class="flex flex-wrap items-center gap-3">
            <Button
              size="sm"
              variant="faded"
              color="slate"
              icon="i-lucide-wand-sparkles"
              :label="t('OUTSIDER_VOICE.SETTINGS.PASTE.APPLY')"
              :disabled="!pasteText.trim()"
              data-testid="voice-paste-apply"
              @click="fillFromText"
            />
            <span
              v-if="pasteResult"
              class="text-xs text-n-slate-11"
              data-testid="voice-paste-result"
            >
              {{ pasteResult }}
            </span>
          </div>
        </div>

        <div class="grid gap-3 pt-4 border-t sm:grid-cols-2 border-n-weak">
          <Input
            v-model="form.trunk.host"
            :label="t('OUTSIDER_VOICE.SETTINGS.TRUNK.HOST')"
            placeholder="sip.operadora.com.br"
            :message-type="hasError('trunk.host') ? 'error' : 'info'"
          />
          <div class="grid grid-cols-2 gap-3">
            <Input
              v-model="form.trunk.port"
              type="number"
              :label="t('OUTSIDER_VOICE.SETTINGS.TRUNK.PORT')"
              :message-type="hasError('trunk.port') ? 'error' : 'info'"
            />
            <label class="flex flex-col gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('OUTSIDER_VOICE.SETTINGS.TRUNK.TRANSPORT') }}
              </span>
              <Select
                v-model="form.trunk.transport"
                :options="transportOptions"
              />
            </label>
          </div>
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.SETTINGS.TRUNK.AUTH') }}
            </span>
            <Select v-model="form.trunk.auth" :options="authOptions" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.SETTINGS.TRUNK.DIAL_FORMAT') }}
            </span>
            <Select v-model="form.dial_format" :options="dialOptions" />
          </label>
          <template v-if="form.trunk.auth === 'register'">
            <Input
              v-model="form.trunk.username"
              :label="t('OUTSIDER_VOICE.SETTINGS.TRUNK.USERNAME')"
              autocomplete="off"
            />
            <Input
              v-model="form.trunk.auth_username"
              :label="t('OUTSIDER_VOICE.SETTINGS.TRUNK.AUTH_USERNAME')"
              autocomplete="off"
            />
            <Input
              v-model="password"
              type="password"
              autocomplete="new-password"
              :label="t('OUTSIDER_VOICE.SETTINGS.TRUNK.PASSWORD')"
              :message="
                form.trunk.password_set
                  ? t('OUTSIDER_VOICE.SETTINGS.TRUNK.PASSWORD_SET')
                  : ''
              "
            />
          </template>
          <label class="flex flex-col gap-1 sm:col-span-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_VOICE.SETTINGS.TRUNK.IPS') }}
            </span>
            <textarea
              v-model="ipsText"
              rows="2"
              placeholder="200.150.10.20"
              class="w-full !mb-0 px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 focus:outline-n-brand"
              :class="
                hasError('trunk.ips') ? 'outline-n-ruby-9' : 'outline-n-weak'
              "
            />
            <span class="text-xs text-n-slate-11">
              {{ t('OUTSIDER_VOICE.SETTINGS.TRUNK.IPS_HELP') }}
            </span>
          </label>
        </div>
      </div>

      <!-- números por estado -->
      <div
        class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="flex flex-col gap-1 px-4 py-3 border-b border-n-weak">
          <h4 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.SETTINGS.NUMBERS.TITLE') }}
          </h4>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.SETTINGS.NUMBERS.DESCRIPTION') }}
          </p>
        </div>
        <p
          v-if="!form.numbers.length"
          class="px-4 py-3 mb-0 text-sm border-b text-n-slate-11 border-n-weak"
        >
          {{ t('OUTSIDER_VOICE.SETTINGS.NUMBERS.EMPTY') }}
        </p>
        <div
          v-for="(row, index) in form.numbers"
          :key="index"
          class="flex flex-wrap items-center gap-2 px-4 py-2 border-b border-n-weak"
          data-testid="voice-number-row"
        >
          <Input
            v-model="row.number"
            inputmode="tel"
            class="w-44"
            :placeholder="t('OUTSIDER_VOICE.SETTINGS.NUMBERS.NUMBER')"
            :message-type="
              hasError(`numbers.${index}.number`) ? 'error' : 'info'
            "
            @blur="suggestState(row)"
          />
          <Select
            v-model="row.state"
            :options="stateOptions"
            :placeholder="t('OUTSIDER_VOICE.SETTINGS.NUMBERS.STATE')"
            :error="hasError(`numbers.${index}.state`) ? ' ' : ''"
          />
          <Input
            v-model="row.label"
            class="flex-1 min-w-[8rem]"
            :placeholder="t('OUTSIDER_VOICE.SETTINGS.NUMBERS.LABEL')"
          />
          <Button
            icon="i-lucide-trash-2"
            size="sm"
            variant="ghost"
            color="slate"
            :title="t('OUTSIDER_VOICE.SETTINGS.NUMBERS.REMOVE')"
            @click="form.numbers.splice(index, 1)"
          />
        </div>
        <div class="px-4 py-2">
          <Button
            icon="i-lucide-plus"
            size="sm"
            variant="ghost"
            :label="t('OUTSIDER_VOICE.SETTINGS.NUMBERS.ADD')"
            @click="addNumber()"
          />
        </div>
      </div>

      <!-- ramais -->
      <div
        class="overflow-hidden outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="flex flex-col gap-1 px-4 py-3 border-b border-n-weak">
          <h4 class="mb-0 text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_VOICE.SETTINGS.AGENTS.TITLE') }}
          </h4>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('OUTSIDER_VOICE.SETTINGS.AGENTS.DESCRIPTION') }}
          </p>
        </div>
        <div
          v-for="person in people"
          :key="person.id"
          class="flex flex-wrap items-center justify-between gap-3 px-4 py-2 border-b border-n-weak last:border-0"
          data-testid="voice-agent-row"
        >
          <span class="flex items-center min-w-0 gap-2">
            <Avatar
              :name="person.name"
              :src="person.thumbnail"
              :size="24"
              rounded-full
            />
            <span class="text-sm truncate text-n-slate-12">
              {{ person.name }}
            </span>
          </span>
          <span class="flex items-center gap-2">
            <Input
              v-model="form.agents[person.id].extension"
              inputmode="numeric"
              maxlength="3"
              class="w-20"
              :placeholder="t('OUTSIDER_VOICE.SETTINGS.AGENTS.EXTENSION')"
              :message-type="
                hasError(`agents.${person.id}.extension`) ? 'error' : 'info'
              "
            />
            <Select
              v-model="form.agents[person.id].state"
              :options="stateOptions"
              :placeholder="t('OUTSIDER_VOICE.SETTINGS.AGENTS.STATE')"
            />
            <Switch
              :model-value="form.agents[person.id].enabled"
              @update:model-value="toggleAgent(form.agents[person.id])"
            />
          </span>
        </div>
      </div>

      <!-- toque e endereços -->
      <div
        class="flex flex-col gap-4 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_VOICE.SETTINGS.RINGING.TITLE') }}
        </h4>
        <div class="grid gap-3 sm:grid-cols-2">
          <Input
            v-model="form.ring_seconds"
            type="number"
            min="10"
            max="60"
            :label="t('OUTSIDER_VOICE.SETTINGS.RINGING.RING_SECONDS')"
            :message="t('OUTSIDER_VOICE.SETTINGS.RINGING.RING_HELP')"
            :message-type="hasError('ring_seconds') ? 'error' : 'info'"
          />
          <label class="flex items-start gap-3 cursor-pointer sm:pt-6">
            <Switch v-model="form.owner_first" class="mt-0.5" />
            <span class="text-sm text-n-slate-12">
              {{ t('OUTSIDER_VOICE.SETTINGS.RINGING.OWNER_FIRST') }}
            </span>
          </label>
          <Input
            v-model="form.ws_url"
            :label="t('OUTSIDER_VOICE.SETTINGS.RINGING.WS_URL')"
            placeholder="wss://voz.suaempresa.com.br/ws"
            :message="t('OUTSIDER_VOICE.SETTINGS.RINGING.WS_URL_HELP')"
            :message-type="hasError('ws_url') ? 'error' : 'info'"
          />
          <Input
            v-model="form.public_ip"
            :label="t('OUTSIDER_VOICE.SETTINGS.RINGING.PUBLIC_IP')"
            placeholder="69.6.250.129"
            :message="t('OUTSIDER_VOICE.SETTINGS.RINGING.PUBLIC_IP_HELP')"
            :message-type="hasError('public_ip') ? 'error' : 'info'"
          />
        </div>
      </div>
    </template>
  </SettingsSection>
</template>
