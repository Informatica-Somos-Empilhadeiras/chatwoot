<script setup>
// OUTSIDER: a equipe no período (Entrega 24), no painel do gestor com a equipe toda: ligações de cada vendedor
// (com a barra do tamanho em relação a quem mais ligou), feitas, taxa de contato, recebidas atendidas e
// tempos. Clicar escolhe o vendedor no painel. Ordena por qualquer coluna. Entrega 25: o custo das ligações
// e a filial de cada vendedor.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatDuration, formatMoney, formatTalkTime } from '../format';

const props = defineProps({
  agents: { type: Array, required: true },
});

const emit = defineEmits(['pick']);

const { t } = useI18n();

const COLUMNS = [
  { key: 'total' },
  { key: 'outbound' },
  {
    key: 'contact_rate',
    format: value =>
      value === null ? '—' : `${String(value).replace('.', ',')}%`,
  },
  { key: 'inbound_answered' },
  { key: 'talk_seconds', format: formatTalkTime },
  { key: 'average_talk', format: formatDuration },
  { key: 'cost', format: value => formatMoney(value) },
];

const sortBy = ref('total');

const rows = computed(() =>
  [...props.agents].sort(
    (a, b) => (b[sortBy.value] ?? -1) - (a[sortBy.value] ?? -1)
  )
);
const max = computed(() =>
  Math.max(1, ...props.agents.map(agent => agent.total))
);
const show = (column, agent) =>
  column.format ? column.format(agent[column.key]) : agent[column.key];
</script>

<template>
  <div class="overflow-x-auto">
    <table class="w-full text-sm">
      <thead>
        <tr class="text-xs text-n-slate-11">
          <th class="py-2 font-normal text-left ltr:pr-3 rtl:pl-3">
            {{ t('OUTSIDER_VOICE.WALLBOARD.RANKING.SELLER') }}
          </th>
          <th
            v-for="column in COLUMNS"
            :key="column.key"
            class="px-2 py-2 font-normal text-right align-bottom"
          >
            <button
              type="button"
              class="inline-flex items-center gap-1 hover:text-n-slate-12"
              :class="{ 'text-n-slate-12 font-medium': sortBy === column.key }"
              @click="sortBy = column.key"
            >
              {{
                t(
                  `OUTSIDER_VOICE.WALLBOARD.RANKING.${column.key.toUpperCase()}`
                )
              }}
              <Icon
                v-if="sortBy === column.key"
                icon="i-lucide-arrow-down"
                class="size-3"
              />
            </button>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="agent in rows"
          :key="agent.id"
          class="border-t cursor-pointer border-n-weak hover:bg-n-alpha-1"
          data-testid="wallboard-ranking-row"
          @click="emit('pick', agent.id)"
        >
          <td class="py-2 ltr:pr-3 rtl:pl-3">
            <span class="flex items-center gap-2 min-w-40">
              <Avatar
                :name="agent.name"
                :src="agent.thumbnail"
                :size="24"
                rounded-full
              />
              <span class="flex flex-col flex-1 min-w-0 gap-1">
                <span class="flex items-baseline min-w-0 gap-1.5">
                  <span class="truncate text-n-slate-12">{{ agent.name }}</span>
                  <span
                    v-if="agent.branch"
                    class="text-xs truncate text-n-slate-11"
                  >
                    {{ agent.branch }}
                  </span>
                </span>
                <span class="h-1 rounded-full bg-n-alpha-2">
                  <span
                    class="block h-full rounded-full bg-n-blue-9"
                    :style="{ width: `${(agent.total * 100) / max}%` }"
                  />
                </span>
              </span>
            </span>
          </td>
          <td
            v-for="column in COLUMNS"
            :key="column.key"
            class="px-2 py-2 text-right tabular-nums text-n-slate-12"
          >
            {{ show(column, agent) }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
