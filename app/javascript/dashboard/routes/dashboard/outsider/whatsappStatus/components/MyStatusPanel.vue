<script setup>
// OUTSIDER: painel "Meus status": resumo, lista ou cards, e ações em lote.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MyStatusRow from './MyStatusRow.vue';
import MyStatusCard from './MyStatusCard.vue';
import StatusRepublishDialog from './StatusRepublishDialog.vue';
import {
  downloadMedia,
  hasMedia,
  isActive,
  loadLayout,
  saveLayout,
  statusesCsv,
} from '../helpers';

const props = defineProps({
  statuses: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  can: { type: Object, default: () => ({}) },
  inboxId: { type: Number, required: true },
});

const emit = defineEmits(['view', 'edit', 'interactions', 'republished']);

const period = defineModel('period', { type: Number, default: 7 });

const { t, locale } = useI18n();

const layout = ref(loadLayout());
const typeFilter = ref('all');
const sortBy = ref('recent');
const selectedIds = ref([]);
const downloadingIds = ref([]);
const republishDialogRef = ref(null);

const periodOptions = computed(() => [
  { value: 1, label: t('OUTSIDER_WHATSAPP_STATUS.MINE.PERIOD_1') },
  { value: 7, label: t('OUTSIDER_WHATSAPP_STATUS.MINE.PERIOD_7') },
  { value: 30, label: t('OUTSIDER_WHATSAPP_STATUS.MINE.PERIOD_30') },
]);

const typeOptions = computed(() => [
  { value: 'all', label: t('OUTSIDER_WHATSAPP_STATUS.MINE.ALL_TYPES') },
  { value: 'text', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.TEXT') },
  { value: 'image', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.IMAGE') },
  { value: 'video', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.VIDEO') },
]);

// a Evolution sem o ajuste das visualizações manda views null
const hasViews = computed(() =>
  props.statuses.some(status => status.views != null)
);

const sortOptions = computed(() => [
  { value: 'recent', label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SORT_RECENT') },
  ...(hasViews.value
    ? [{ value: 'views', label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SORT_VIEWS') }]
    : []),
  { value: 'likes', label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SORT_LIKES') },
  { value: 'replies', label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SORT_REPLIES') },
]);

const visible = computed(() => {
  const list = props.statuses.filter(
    status => typeFilter.value === 'all' || status.type === typeFilter.value
  );
  // a lista já vem do mais novo para o mais antigo
  if (sortBy.value === 'views') {
    return [...list].sort((a, b) => (b.views || 0) - (a.views || 0));
  }
  if (sortBy.value === 'likes') {
    return [...list].sort((a, b) => b.reactions.length - a.reactions.length);
  }
  if (sortBy.value === 'replies') {
    return [...list].sort((a, b) => b.replies.length - a.replies.length);
  }
  return list;
});

const average = (total, count) =>
  new Intl.NumberFormat(locale.value.replace('_', '-'), {
    maximumFractionDigits: 1,
  }).format(count ? total / count : 0);

const summary = computed(() => {
  const count = props.statuses.length;
  const likes = props.statuses.reduce(
    (total, status) => total + status.reactions.length,
    0
  );
  const replies = props.statuses.reduce(
    (total, status) => total + status.replies.length,
    0
  );
  const views = props.statuses.reduce(
    (total, status) => total + (status.views || 0),
    0
  );
  return [
    {
      key: 'published',
      icon: 'i-lucide-circle-dashed',
      label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.PUBLISHED'),
      value: count,
      hint: periodOptions.value.find(option => option.value === period.value)
        ?.label,
    },
    {
      key: 'active',
      icon: 'i-lucide-clock',
      label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.ACTIVE'),
      value: props.statuses.filter(isActive).length,
      hint: t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.ACTIVE_HINT'),
    },
    {
      key: 'views',
      icon: 'i-lucide-eye',
      label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.VIEWS'),
      value: hasViews.value || !count ? views : '—',
      hint:
        hasViews.value || !count
          ? t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.AVERAGE', {
              value: average(views, count),
            })
          : t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.VIEWS_UNAVAILABLE'),
    },
    {
      key: 'likes',
      icon: 'i-lucide-heart',
      label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.LIKES'),
      value: likes,
      hint: t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.AVERAGE', {
        value: average(likes, count),
      }),
    },
    {
      key: 'replies',
      icon: 'i-lucide-message-circle-reply',
      label: t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.REPLIES'),
      value: replies,
      hint: t('OUTSIDER_WHATSAPP_STATUS.MINE.SUMMARY.AVERAGE', {
        value: average(replies, count),
      }),
    },
  ];
});

// sem nenhuma ação em lote liberada, a seleção não serve para nada
const selectable = computed(
  () => props.can.republish || props.can.download || props.can.export
);

const selected = computed(() =>
  visible.value.filter(status => selectedIds.value.includes(status.id))
);
const allSelected = computed(
  () =>
    visible.value.length > 0 && selected.value.length === visible.value.length
);

watch([period, typeFilter, () => props.statuses], () => {
  selectedIds.value = [];
});

watch(layout, saveLayout);

const toggle = id => {
  selectedIds.value = selectedIds.value.includes(id)
    ? selectedIds.value.filter(selectedId => selectedId !== id)
    : [...selectedIds.value, id];
};

const toggleAll = () => {
  selectedIds.value = allSelected.value
    ? []
    : visible.value.map(status => status.id);
};

const republish = statuses => republishDialogRef.value.open(statuses);

const download = async status => {
  downloadingIds.value = [...downloadingIds.value, status.id];
  try {
    await downloadMedia(props.inboxId, status);
    return true;
  } catch {
    return false;
  } finally {
    downloadingIds.value = downloadingIds.value.filter(id => id !== status.id);
  }
};

const downloadOne = async status => {
  if (!(await download(status))) {
    useAlert(t('OUTSIDER_WHATSAPP_STATUS.MINE.DOWNLOAD_ERROR', { count: 1 }));
  }
};

const downloadSelected = async () => {
  const items = selected.value.filter(
    status => hasMedia(status) && !status.deleted
  );
  if (!items.length) {
    useAlert(t('OUTSIDER_WHATSAPP_STATUS.MINE.NO_MEDIA'));
    return;
  }
  // uma de cada vez, para o navegador não barrar os downloads
  const failed = await items.reduce(async (chain, status) => {
    const count = await chain;
    return (await download(status)) ? count : count + 1;
  }, Promise.resolve(0));
  if (failed) {
    useAlert(
      t('OUTSIDER_WHATSAPP_STATUS.MINE.DOWNLOAD_ERROR', { count: failed })
    );
  }
};

const exportCsv = () =>
  downloadCsvFile(
    `status-whatsapp-${format(new Date(), 'yyyy-MM-dd')}.csv`,
    statusesCsv(t, selected.value)
  );
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-5">
      <div
        v-for="card in summary"
        :key="card.key"
        class="flex flex-col gap-1 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <span class="flex items-center gap-2 text-sm text-n-slate-11">
          <Icon :icon="card.icon" class="flex-shrink-0 size-4" />
          {{ card.label }}
        </span>
        <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
          {{ card.value }}
        </span>
        <span class="text-xs text-n-slate-10">{{ card.hint }}</span>
      </div>
    </div>

    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex flex-wrap items-center gap-2">
        <Select v-model="period" :options="periodOptions" />
        <Select v-model="typeFilter" :options="typeOptions" />
        <Select v-model="sortBy" :options="sortOptions" />
      </div>
      <div class="flex items-center gap-1 p-1 rounded-lg bg-n-alpha-1">
        <Button
          v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.MINE.LIST')"
          icon="i-lucide-list"
          size="sm"
          color="slate"
          :variant="layout === 'list' ? 'solid' : 'ghost'"
          @click="layout = 'list'"
        />
        <Button
          v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.MINE.CARDS')"
          icon="i-lucide-layout-grid"
          size="sm"
          color="slate"
          :variant="layout === 'cards' ? 'solid' : 'ghost'"
          @click="layout = 'cards'"
        />
      </div>
    </div>

    <div
      v-if="selectable"
      class="flex flex-wrap items-center gap-3 px-4 py-2 rounded-xl min-h-12 bg-n-alpha-1"
    >
      <Checkbox
        :model-value="allSelected"
        :indeterminate="selected.length > 0 && !allSelected"
        :disabled="!visible.length"
        @update:model-value="toggleAll"
      />
      <span class="text-sm text-n-slate-11">
        {{
          selected.length
            ? t('OUTSIDER_WHATSAPP_STATUS.MINE.SELECTED', {
                count: selected.length,
              })
            : t('OUTSIDER_WHATSAPP_STATUS.MINE.SELECT_ALL')
        }}
      </span>
      <template v-if="selected.length">
        <Button
          v-if="can.republish"
          size="sm"
          variant="faded"
          icon="i-lucide-repeat-2"
          :label="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.REPUBLISH')"
          @click="republish(selected)"
        />
        <Button
          v-if="can.download"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-download"
          :label="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.DOWNLOAD')"
          :is-loading="downloadingIds.length > 0"
          @click="downloadSelected"
        />
        <Button
          v-if="can.export"
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-file-spreadsheet"
          :label="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.EXPORT_CSV')"
          @click="exportCsv"
        />
        <Button
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          :label="t('OUTSIDER_WHATSAPP_STATUS.ACTIONS.CLEAR_SELECTION')"
          @click="selectedIds = []"
        />
      </template>
    </div>

    <div v-if="isLoading && !statuses.length" class="flex justify-center p-8">
      <Spinner class="text-n-slate-10" />
    </div>
    <p
      v-else-if="!visible.length"
      class="p-8 mb-0 text-sm text-center text-n-slate-11"
    >
      {{
        statuses.length
          ? t('OUTSIDER_WHATSAPP_STATUS.MINE.EMPTY_FILTER')
          : t('OUTSIDER_WHATSAPP_STATUS.MINE.EMPTY')
      }}
    </p>
    <div
      v-else-if="layout === 'list'"
      class="flex flex-col overflow-hidden divide-y divide-n-weak outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <MyStatusRow
        v-for="status in visible"
        :key="status.id"
        :status="status"
        :selected="selectedIds.includes(status.id)"
        :can="can"
        :selectable="selectable"
        :downloading="downloadingIds.includes(status.id)"
        @toggle="toggle(status.id)"
        @view="emit('view', status)"
        @edit="emit('edit', status)"
        @interactions="emit('interactions', status)"
        @republish="republish([status])"
        @download="downloadOne(status)"
      />
    </div>
    <div v-else class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
      <MyStatusCard
        v-for="status in visible"
        :key="status.id"
        :status="status"
        :selected="selectedIds.includes(status.id)"
        :can="can"
        :selectable="selectable"
        :downloading="downloadingIds.includes(status.id)"
        :inbox-id="inboxId"
        @toggle="toggle(status.id)"
        @view="emit('view', status)"
        @edit="emit('edit', status)"
        @interactions="emit('interactions', status)"
        @republish="republish([status])"
        @download="downloadOne(status)"
      />
    </div>

    <StatusRepublishDialog
      ref="republishDialogRef"
      :inbox-id="inboxId"
      @republished="emit('republished')"
    />
  </div>
</template>
