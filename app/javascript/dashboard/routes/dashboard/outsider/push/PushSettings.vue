<script setup>
// OUTSIDER: Configurações > Notificações. O aviso novo (push) vem tudo ligado; cada pessoa desliga o que não quiser,
// vê os aparelhos em que ativou e manda um push de teste. Administradores veem a equipe: quem está com o push ativo,
// quem nunca ativou (botão Lembrar) e quem bloqueou no navegador.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import OutsiderPushAPI from 'dashboard/api/outsider/push';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TeamsLogo from '../teams/TeamsLogo.vue';
import PushBanner from './PushBanner.vue';
import PushToggle from './PushToggle.vue';
import {
  activatePush,
  isAppleMobile,
  isThisDevice,
  loadPush,
  pushState,
  syncDevice,
} from './pushDevice';

const { t } = useI18n();

const SECTIONS = [
  {
    key: 'whatsapp',
    icon: 'i-lucide-message-circle',
    tone: 'green',
    items: ['wa_assigned', 'wa_unassigned', 'wa_groups'],
  },
  {
    key: 'teams',
    icon: 'i-lucide-users-round',
    tone: 'purple',
    items: ['teams_chats', 'teams_mentions', 'teams_replies', 'teams_groups'],
  },
  {
    key: 'chatwoot',
    icon: 'i-lucide-bell',
    tone: 'purple',
    items: ['chatwoot'],
  },
  {
    key: 'phone',
    icon: 'i-lucide-phone-missed',
    tone: 'green',
    items: ['calls_missed'],
    voice: true,
  },
  {
    key: 'privacy',
    icon: 'i-lucide-lock',
    tone: 'slate',
    items: ['hide_content'],
  },
];

// opções com uma linha de explicação embaixo
const WITH_HELP = new Set([
  'wa_assigned',
  'wa_unassigned',
  'wa_groups',
  'teams_mentions',
  'teams_replies',
  'hide_content',
  'calls_missed',
]);

const isLoading = ref(true);
const isActivating = ref(false);
const isTesting = ref(false);
const showHelp = ref(false);
const reminded = ref(new Set());

const info = computed(() => pushState.info);
// "Telefone" só para quem tem ramal ligado na Telefonia
const sections = computed(() =>
  SECTIONS.filter(section => !section.voice || info.value?.voice)
);
const prefs = computed(() => info.value?.prefs || {});
const activeHere = computed(
  () =>
    pushState.permission === 'granted' &&
    (info.value?.devices || []).some(device => isThisDevice(device))
);

const load = async () => {
  try {
    await loadPush();
    await syncDevice();
  } catch {
    // a tela mostra o que conseguiu carregar
  } finally {
    isLoading.value = false;
  }
};

const toggle = async key => {
  const next = { ...prefs.value, [key]: !prefs.value[key] };
  pushState.info = { ...info.value, prefs: next };
  try {
    const { data } = await OutsiderPushAPI.update({ [key]: next[key] });
    pushState.info = data;
  } catch {
    pushState.info = { ...info.value, prefs: { ...next, [key]: !next[key] } };
    useAlert(t('OUTSIDER_PUSH.ERROR'));
  }
};

const activate = async () => {
  isActivating.value = true;
  try {
    const ok = await activatePush();
    useAlert(
      ok
        ? t('OUTSIDER_PUSH.BANNER.DONE')
        : t('OUTSIDER_PUSH.BANNER.NOT_ALLOWED')
    );
  } catch {
    useAlert(t('OUTSIDER_PUSH.BANNER.FAILED'));
  } finally {
    isActivating.value = false;
  }
};

const test = async () => {
  isTesting.value = true;
  try {
    const { data } = await OutsiderPushAPI.test();
    useAlert(
      data.sent
        ? t('OUTSIDER_PUSH.DEVICES.TEST_SENT', { count: data.sent })
        : t('OUTSIDER_PUSH.DEVICES.TEST_NONE')
    );
  } catch {
    useAlert(t('OUTSIDER_PUSH.ERROR'));
  } finally {
    isTesting.value = false;
  }
};

const remove = async device => {
  try {
    const { data } = await OutsiderPushAPI.unregister(device.id);
    pushState.info = data;
  } catch {
    useAlert(t('OUTSIDER_PUSH.ERROR'));
  }
};

const remind = async person => {
  try {
    await OutsiderPushAPI.remind(person.id);
    reminded.value = new Set([...reminded.value, person.id]);
    useAlert(t('OUTSIDER_PUSH.TEAM.REMINDED', { name: person.name }));
  } catch {
    useAlert(t('OUTSIDER_PUSH.ERROR'));
  }
};

const dateOf = iso => (iso ? new Date(iso).toLocaleDateString('pt-BR') : '');

const statusTone = status =>
  ({
    active: 'bg-n-teal-3 text-n-teal-11',
    blocked: 'bg-n-ruby-3 text-n-ruby-11',
    never: 'bg-n-amber-3 text-n-amber-11',
  })[status];

onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="t('OUTSIDER_PUSH.TITLE')"
        :description="t('OUTSIDER_PUSH.DESCRIPTION')"
      >
        <template #title>
          <h1 class="flex items-center gap-2.5 text-heading-1 text-n-slate-12">
            <Icon icon="i-lucide-bell" class="size-6" />
            {{ t('OUTSIDER_PUSH.TITLE') }}
          </h1>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div v-if="info" class="pb-8">
        <PushBanner inline />
        <p
          v-if="!info.enabled"
          class="flex items-start gap-2.5 p-3 mb-4 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
        >
          <Icon icon="i-lucide-triangle-alert" class="size-4 mt-0.5 shrink-0" />
          {{ t('OUTSIDER_PUSH.DISABLED') }}
        </p>
        <div class="grid gap-4 lg:grid-cols-[1.1fr_1fr] items-start">
          <!-- o que me avisa -->
          <section
            class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
            data-testid="push-prefs"
          >
            <h3
              class="flex items-center gap-2 mb-0.5 text-[15px] font-semibold text-n-slate-12"
            >
              <Icon icon="i-lucide-bell" class="size-4" />
              {{ t('OUTSIDER_PUSH.PREFS.TITLE') }}
            </h3>
            <p class="mb-2 text-sm text-n-slate-11">
              {{ t('OUTSIDER_PUSH.PREFS.HELP') }}
            </p>
            <div v-for="section in sections" :key="section.key" class="mt-3">
              <div
                class="flex items-center gap-1.5 mb-1 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
              >
                <TeamsLogo v-if="section.key === 'teams'" :size="14" />
                <Icon v-else :icon="section.icon" class="size-3.5" />
                {{ t(`OUTSIDER_PUSH.SECTIONS.${section.key.toUpperCase()}`) }}
              </div>
              <div
                v-for="key in section.items"
                :key="key"
                class="flex items-center gap-3 py-2.5 border-b border-n-weak last:border-b-0"
              >
                <span class="flex-1 min-w-0">
                  <span class="block text-sm text-n-slate-12">
                    {{ t(`OUTSIDER_PUSH.PREFS.${key.toUpperCase()}`) }}
                  </span>
                  <span
                    v-if="WITH_HELP.has(key)"
                    class="block text-xs text-n-slate-11"
                  >
                    {{ t(`OUTSIDER_PUSH.PREFS.${key.toUpperCase()}_HELP`) }}
                  </span>
                </span>
                <PushToggle
                  :model-value="!!prefs[key]"
                  :tone="section.tone"
                  :data-push-pref="key"
                  @toggle="toggle(key)"
                />
              </div>
            </div>
          </section>

          <div class="flex flex-col gap-4">
            <!-- meus aparelhos -->
            <section
              class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
              data-testid="push-devices"
            >
              <h3
                class="flex items-center gap-2 mb-2 text-[15px] font-semibold text-n-slate-12"
              >
                <Icon icon="i-lucide-smartphone" class="size-4" />
                {{ t('OUTSIDER_PUSH.DEVICES.TITLE') }}
              </h3>
              <p
                v-if="!info.devices.length"
                class="mb-2 text-sm text-n-slate-11"
              >
                {{ t('OUTSIDER_PUSH.DEVICES.EMPTY') }}
              </p>
              <div
                v-for="device in info.devices"
                :key="device.id"
                class="flex items-center gap-3 py-2"
              >
                <span
                  class="grid rounded-lg size-9 place-items-center shrink-0 bg-n-alpha-2 text-n-slate-11"
                >
                  <Icon
                    :icon="
                      /Android|iPhone/.test(device.label)
                        ? 'i-lucide-smartphone'
                        : 'i-lucide-monitor'
                    "
                    class="size-[18px]"
                  />
                </span>
                <span class="flex-1 min-w-0">
                  <span
                    class="block text-sm font-semibold truncate text-n-slate-12"
                  >
                    {{
                      isThisDevice(device)
                        ? t('OUTSIDER_PUSH.DEVICES.THIS')
                        : device.label
                    }}
                  </span>
                  <span class="block text-xs truncate text-n-slate-11">
                    {{
                      isThisDevice(device)
                        ? t('OUTSIDER_PUSH.DEVICES.SINCE', {
                            label: device.label,
                            date: dateOf(device.activated_at),
                          })
                        : t('OUTSIDER_PUSH.DEVICES.ACTIVATED', {
                            date: dateOf(device.activated_at),
                          })
                    }}
                  </span>
                </span>
                <span
                  class="flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded-full bg-n-teal-3 text-n-teal-11"
                >
                  <Icon icon="i-lucide-check" class="size-3" />
                  {{ t('OUTSIDER_PUSH.DEVICES.ACTIVE') }}
                </span>
                <button
                  type="button"
                  class="grid rounded-lg size-8 place-items-center text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-ruby-3"
                  :title="t('OUTSIDER_PUSH.DEVICES.REMOVE')"
                  @click="remove(device)"
                >
                  <Icon icon="i-lucide-trash-2" class="size-4" />
                </button>
              </div>
              <p
                v-if="pushState.permission === 'denied'"
                class="flex items-start gap-2 p-2.5 mt-2 mb-0 text-sm rounded-xl bg-n-ruby-3 text-n-ruby-11"
              >
                <Icon icon="i-lucide-bell-off" class="size-4 mt-0.5 shrink-0" />
                {{ t('OUTSIDER_PUSH.BANNER.BLOCKED_TEXT') }}
              </p>
              <p
                v-else-if="!pushState.supported"
                class="flex items-start gap-2 p-2.5 mt-2 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-11"
              >
                <Icon icon="i-lucide-info" class="size-4 mt-0.5 shrink-0" />
                {{
                  isAppleMobile()
                    ? t('OUTSIDER_PUSH.DEVICES.IPHONE_HOME')
                    : t('OUTSIDER_PUSH.DEVICES.UNSUPPORTED')
                }}
              </p>
              <div class="flex flex-wrap items-center gap-2 mt-3">
                <button
                  v-if="pushState.supported && !activeHere"
                  type="button"
                  class="flex items-center gap-1.5 px-3.5 py-1.5 text-sm font-semibold text-white rounded-lg bg-n-brand disabled:opacity-60"
                  :disabled="isActivating || pushState.permission === 'denied'"
                  data-testid="push-activate"
                  @click="activate"
                >
                  <Icon icon="i-lucide-bell-ring" class="size-4" />
                  {{ t('OUTSIDER_PUSH.DEVICES.ACTIVATE_HERE') }}
                </button>
                <Button
                  sm
                  slate
                  faded
                  icon="i-lucide-send"
                  :label="t('OUTSIDER_PUSH.DEVICES.TEST')"
                  :is-loading="isTesting"
                  :disabled="!info.devices.length"
                  @click="test"
                />
                <button
                  type="button"
                  class="flex items-center gap-1.5 px-2 py-1.5 text-sm font-medium text-n-blue-11 hover:underline"
                  @click="showHelp = !showHelp"
                >
                  <Icon icon="i-lucide-circle-help" class="size-4" />
                  {{ t('OUTSIDER_PUSH.DEVICES.HOW_PHONE') }}
                </button>
              </div>
              <div
                v-if="showHelp"
                class="p-3 mt-3 text-sm border rounded-xl border-n-weak bg-n-surface-1 text-n-slate-11"
              >
                <b class="block mb-1 text-n-slate-12">Android</b>
                <p class="mb-2">{{ t('OUTSIDER_PUSH.HELP.ANDROID') }}</p>
                <b class="block mb-1 text-n-slate-12">iPhone</b>
                <p class="mb-0">{{ t('OUTSIDER_PUSH.HELP.IPHONE') }}</p>
              </div>
            </section>

            <!-- equipe (administradores) -->
            <section
              v-if="info.admin"
              class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
              data-testid="push-team"
            >
              <div class="flex items-center gap-2">
                <Icon icon="i-lucide-users" class="size-4 text-n-slate-12" />
                <h3 class="mb-0 text-[15px] font-semibold text-n-slate-12">
                  {{ t('OUTSIDER_PUSH.TEAM.TITLE') }}
                </h3>
                <span
                  class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-alpha-2 text-n-slate-11"
                >
                  {{ t('OUTSIDER_PUSH.TEAM.ADMINS_ONLY') }}
                </span>
              </div>
              <p class="mt-1 mb-2 text-sm text-n-slate-11">
                {{ t('OUTSIDER_PUSH.TEAM.HELP') }}
              </p>
              <table class="w-full text-sm border-collapse">
                <thead>
                  <tr class="text-xs text-left text-n-slate-11">
                    <th class="px-1 py-2 font-semibold">
                      {{ t('OUTSIDER_PUSH.TEAM.COL_PERSON') }}
                    </th>
                    <th class="px-1 py-2 font-semibold">
                      {{ t('OUTSIDER_PUSH.TEAM.COL_DEVICES') }}
                    </th>
                    <th class="px-1 py-2 font-semibold">
                      {{ t('OUTSIDER_PUSH.TEAM.COL_STATUS') }}
                    </th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="person in info.team"
                    :key="person.id"
                    class="border-t border-n-weak"
                  >
                    <td class="px-1 py-2">
                      <span class="flex items-center gap-2 min-w-0">
                        <Avatar :name="person.name" :size="26" rounded-full />
                        <span class="truncate text-n-slate-12">
                          {{ person.name }}
                        </span>
                      </span>
                    </td>
                    <td class="px-1 py-2 text-n-slate-12">
                      {{ person.devices }}
                    </td>
                    <td class="px-1 py-2">
                      <span
                        class="px-2 py-0.5 text-xs font-semibold rounded-full whitespace-nowrap"
                        :class="statusTone(person.status)"
                      >
                        {{
                          t(`OUTSIDER_PUSH.TEAM.${person.status.toUpperCase()}`)
                        }}
                      </span>
                    </td>
                    <td class="px-1 py-2 text-right">
                      <button
                        v-if="person.status === 'never'"
                        type="button"
                        class="px-2.5 py-1 text-xs font-semibold rounded-lg bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 disabled:opacity-50"
                        :disabled="reminded.has(person.id)"
                        @click="remind(person)"
                      >
                        {{
                          reminded.has(person.id)
                            ? t('OUTSIDER_PUSH.TEAM.REMIND_SENT')
                            : t('OUTSIDER_PUSH.TEAM.REMIND')
                        }}
                      </button>
                      <span
                        v-else-if="person.status === 'blocked'"
                        v-tooltip.left="t('OUTSIDER_PUSH.BANNER.BLOCKED_TEXT')"
                        class="px-2.5 py-1 text-xs font-semibold rounded-lg whitespace-nowrap cursor-help bg-n-alpha-2 text-n-slate-12"
                      >
                        {{ t('OUTSIDER_PUSH.TEAM.HOW_FIX') }}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </section>
          </div>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
