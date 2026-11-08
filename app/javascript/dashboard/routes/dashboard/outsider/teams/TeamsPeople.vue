<script setup>
// OUTSIDER: "Colaboradores conectados" em Configurações > Microsoft Teams (só administradores). Mostra quem conectou o
// próprio Teams e se está funcionando; o conteúdo das conversas fica só com cada pessoa. O administrador pode
// desconectar alguém (por exemplo, quem saiu da empresa); quem estiver em amarelo resolve entrando de novo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TeamsGraphAPI from 'dashboard/api/outsider/teamsGraph';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { agoText, errorText } from './helpers';

const props = defineProps({ links: { type: Array, default: () => [] } });
const emit = defineEmits(['changed']);

const { t } = useI18n();

const rows = computed(() =>
  [...props.links].sort((a, b) => {
    const order = { reconnect: 0, active: 1, disconnected: 2 };
    return (
      (order[a.status] ?? 3) - (order[b.status] ?? 3) ||
      (a.user_name || '').localeCompare(b.user_name || '')
    );
  })
);
const connectedCount = computed(
  () => props.links.filter(link => link.status !== 'disconnected').length
);

const situation = link => {
  if (link.status === 'disconnected')
    return { text: 'PERSON_OFF', tone: 'bg-n-alpha-2 text-n-slate-11' };
  if (link.status === 'reconnect')
    return { text: 'PERSON_RECONNECT', tone: 'bg-n-amber-3 text-n-amber-11' };
  if (link.problem)
    return { text: 'PERSON_PROBLEM', tone: 'bg-n-amber-3 text-n-amber-11' };
  return { text: 'PERSON_OK', tone: 'bg-n-teal-3 text-n-teal-11' };
};

const disconnect = async link => {
  if (
    // eslint-disable-next-line no-alert
    !window.confirm(
      t('OUTSIDER_TEAMS_GRAPH.PERSON_DISCONNECT_CONFIRM', {
        name: link.user_name || link.display_name,
      })
    )
  )
    return;
  try {
    await TeamsGraphAPI.disconnectPerson(link.id);
    emit('changed');
  } catch (error) {
    useAlert(errorText(error, t));
  }
};
</script>

<template>
  <section
    class="p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-2xl bg-n-solid-2"
    data-testid="teams-people"
  >
    <div class="flex items-center gap-2">
      <Icon icon="i-lucide-users" class="size-5 text-n-slate-12" />
      <h3 class="mb-0 text-[15px] font-semibold text-n-slate-12">
        {{ t('OUTSIDER_TEAMS_GRAPH.PEOPLE_TITLE') }}
      </h3>
      <span class="px-2 py-0.5 text-xs font-semibold rounded-full tms-soft">
        {{ connectedCount }}
      </span>
    </div>
    <p class="mt-1 mb-3 text-sm text-n-slate-11">
      {{ t('OUTSIDER_TEAMS_GRAPH.PEOPLE_HELP') }}
    </p>

    <p v-if="!rows.length" class="py-3 mb-0 text-sm text-n-slate-11">
      {{ t('OUTSIDER_TEAMS_GRAPH.PEOPLE_EMPTY') }}
    </p>
    <div v-else class="overflow-x-auto">
      <table class="w-full text-sm border-collapse min-w-[640px]">
        <thead>
          <tr class="text-xs font-semibold text-left text-n-slate-11">
            <th class="px-2 py-2 font-semibold">
              {{ t('OUTSIDER_TEAMS_GRAPH.COL_PERSON') }}
            </th>
            <th class="px-2 py-2 font-semibold">
              {{ t('OUTSIDER_TEAMS_GRAPH.COL_ACCOUNT') }}
            </th>
            <th class="px-2 py-2 font-semibold">
              {{ t('OUTSIDER_TEAMS_GRAPH.COL_CHATS') }}
            </th>
            <th class="px-2 py-2 font-semibold">
              {{ t('OUTSIDER_TEAMS_GRAPH.COL_CHANNELS') }}
            </th>
            <th class="px-2 py-2 font-semibold">
              {{ t('OUTSIDER_TEAMS_GRAPH.COL_STATUS') }}
            </th>
            <th class="px-2 py-2 font-semibold">
              {{ t('OUTSIDER_TEAMS_GRAPH.COL_LAST') }}
            </th>
            <th class="w-10" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="link in rows"
            :key="link.id"
            class="border-t border-n-weak"
            :class="link.status === 'disconnected' ? 'opacity-60' : ''"
          >
            <td class="px-2 py-2.5">
              <span class="flex items-center gap-2.5 min-w-0">
                <Avatar
                  :name="link.user_name || link.display_name || '?'"
                  :size="28"
                  rounded-full
                />
                <span class="font-semibold truncate text-n-slate-12">
                  {{ link.user_name || link.display_name }}
                </span>
              </span>
            </td>
            <td class="px-2 py-2.5 truncate max-w-[220px] text-n-slate-11">
              {{ link.email || link.display_name }}
            </td>
            <td class="px-2 py-2.5 text-n-slate-12">
              {{
                link.sync_chats
                  ? t('OUTSIDER_TEAMS_GRAPH.YES')
                  : t('OUTSIDER_TEAMS_GRAPH.NO')
              }}
            </td>
            <td class="px-2 py-2.5 text-n-slate-12">
              {{ link.channels_count }}
            </td>
            <td class="px-2 py-2.5">
              <span
                class="px-2 py-0.5 text-xs font-semibold rounded-full whitespace-nowrap"
                :class="situation(link).tone"
              >
                {{ t(`OUTSIDER_TEAMS_GRAPH.${situation(link).text}`) }}
              </span>
            </td>
            <td class="px-2 py-2.5 whitespace-nowrap text-n-slate-11">
              {{
                link.last_activity_at
                  ? agoText(link.last_activity_at, t)
                  : t('OUTSIDER_TEAMS_GRAPH.NEVER')
              }}
            </td>
            <td class="px-2 py-2.5 text-right">
              <button
                v-if="link.status !== 'disconnected'"
                type="button"
                class="grid rounded-lg size-8 place-items-center text-n-ruby-11 hover:bg-n-ruby-3"
                :title="t('OUTSIDER_TEAMS_GRAPH.PERSON_DISCONNECT')"
                @click="disconnect(link)"
              >
                <Icon icon="i-lucide-unplug" class="size-4" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
