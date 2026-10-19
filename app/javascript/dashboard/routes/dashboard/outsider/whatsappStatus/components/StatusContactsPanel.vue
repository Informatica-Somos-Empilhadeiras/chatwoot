<script setup>
// OUTSIDER: aba "Status dos contatos": busca por nome ou número, filtros por tipo e por
// região ou estado (pelo DDD), em grade ou em lista.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import StatusContactList from './StatusContactList.vue';
import { areaOfPhone, buildAreaTree } from '../areas';
import { loadContactsLayout, saveContactsLayout } from '../helpers';

const props = defineProps({
  authors: { type: Array, default: () => [] },
  me: { type: Object, default: null },
  myStatuses: { type: Array, default: () => [] },
  seen: { type: Object, default: () => ({}) },
  canPublish: { type: Boolean, default: false },
  isLoading: { type: Boolean, default: false },
  inboxId: { type: Number, required: true },
});

// openAuthor(stories, startIndex): o visualizador passa de um contato para o outro na ordem da tela
const emit = defineEmits(['openAuthor', 'openMine', 'publish']);

const { t } = useI18n();

const query = ref('');
const typeFilter = ref('all');
const areaFilter = ref('all');
const layout = ref(loadContactsLayout());

watch(layout, saveContactsLayout);
watch(
  () => props.inboxId,
  () => {
    query.value = '';
    typeFilter.value = 'all';
    areaFilter.value = 'all';
  }
);

const typeOptions = computed(() => [
  { value: 'all', label: t('OUTSIDER_WHATSAPP_STATUS.MINE.ALL_TYPES') },
  { value: 'text', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.TEXT') },
  { value: 'image', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.IMAGE') },
  { value: 'video', label: t('OUTSIDER_WHATSAPP_STATUS.TYPES.VIDEO') },
]);

const areaOf = author => areaOfPhone(author.phone || author.jid);

const tree = computed(() => {
  const counts = {};
  props.authors.forEach(author => {
    const area = areaOf(author);
    counts[area] = (counts[area] || 0) + 1;
  });
  return buildAreaTree(counts);
});

const withCount = (label, count) => `${label} (${count})`;

const areaGroups = computed(() => {
  const { regions, others, unknown } = tree.value;
  const rest = [
    others.count && {
      value: 'others',
      label: withCount(t('OUTSIDER_WHATSAPP_STATUS.PICKER.OTHERS'), others.count),
    },
    unknown.count && {
      value: 'unknown',
      label: withCount(
        t('OUTSIDER_WHATSAPP_STATUS.PICKER.UNKNOWN'),
        unknown.count
      ),
    },
  ].filter(Boolean);
  return [
    {
      label: t('OUTSIDER_WHATSAPP_STATUS.PICKER.ALL'),
      options: [
        {
          value: 'all',
          label: withCount(
            t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.ALL_AREAS'),
            props.authors.length
          ),
        },
      ],
    },
    ...regions.map(region => ({
      label: t(`OUTSIDER_WHATSAPP_STATUS.PICKER.REGIONS.${region.key}`),
      options: [
        {
          value: `region:${region.key}`,
          label: withCount(
            t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.WHOLE_REGION'),
            region.count
          ),
        },
        ...region.states.map(state => ({
          value: `state:${state.uf}`,
          label: withCount(state.name, state.count),
        })),
      ],
    })),
    ...(rest.length
      ? [
          {
            label: t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.OTHER_AREAS'),
            options: rest,
          },
        ]
      : []),
  ];
});

// depois de atualizar, a região escolhida pode não ter mais ninguém
watch(areaGroups, groups => {
  const values = groups.flatMap(group => group.options.map(o => o.value));
  if (!values.includes(areaFilter.value)) areaFilter.value = 'all';
});

// as áreas (DDDs, 'foreign', 'unknown') do filtro escolhido; null é sem filtro
const selectedAreas = computed(() => {
  const [kind, key] = areaFilter.value.split(':');
  const { regions, others, unknown } = tree.value;
  if (kind === 'region') return regions.find(r => r.key === key)?.areas ?? [];
  if (kind === 'state') {
    return regions.flatMap(r => r.states).find(s => s.uf === key)?.areas ?? [];
  }
  if (kind === 'others') return others.areas;
  if (kind === 'unknown') return unknown.areas;
  return null;
});

const normalize = text =>
  (text || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();

// no WhatsApp, muitos celulares estão sem o 9 (ex.: +55 62 9988-7766), então o número
// digitado também vale sem o 9 depois do DDD
const matchesQuery = (author, words, digits) => {
  if (words.every(word => normalize(author.name).includes(word))) return true;
  if (digits.length < 3) return false;
  const phone = (author.phone || '').replace(/\D/g, '');
  const withoutNine = digits.replace(/^((?:55)?[1-9]\d)?9(\d{8})$/, '$1$2');
  return phone.includes(digits) || phone.includes(withoutNine);
};

const isFiltered = computed(
  () =>
    !!query.value.trim() ||
    typeFilter.value !== 'all' ||
    areaFilter.value !== 'all'
);

// com filtro de tipo, cada contato fica só com os status daquele tipo, e a ordem segue o
// último status que aparece
const filtered = computed(() => {
  const words = normalize(query.value).split(/\s+/).filter(Boolean);
  const digits = query.value.replace(/\D/g, '');
  const areas = selectedAreas.value;
  return props.authors
    .filter(author => !areas || areas.includes(areaOf(author)))
    .filter(author => !words.length || matchesQuery(author, words, digits))
    .map(author =>
      typeFilter.value === 'all'
        ? author
        : {
            ...author,
            statuses: author.statuses.filter(
              status => status.type === typeFilter.value
            ),
          }
    )
    .filter(author => author.statuses.length)
    .sort((a, b) => b.statuses.at(-1).timestamp - a.statuses.at(-1).timestamp);
});

const isViewed = author =>
  author.statuses.every(status => props.seen[status.id]);
const recent = computed(() => filtered.value.filter(a => !isViewed(a)));
const viewed = computed(() => filtered.value.filter(isViewed));

const openAuthor = author => {
  const stories = [...recent.value, ...viewed.value];
  emit('openAuthor', stories, stories.indexOf(author));
};
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex flex-wrap items-center flex-1 min-w-0 gap-2">
        <Input
          v-model="query"
          type="search"
          :placeholder="t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.SEARCH')"
          :custom-input-class="['h-9 ltr:!pl-8 rtl:!pr-8']"
          class="w-full sm:w-64"
        >
          <template #prefix>
            <Icon
              icon="i-lucide-search"
              class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
            />
          </template>
        </Input>
        <Select v-model="typeFilter" :options="typeOptions" />
        <Select v-model="areaFilter" :groups="areaGroups" />
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
    <StatusContactList
      :me="me"
      :my-statuses="myStatuses"
      :recent="recent"
      :viewed="viewed"
      :seen="seen"
      :can-publish="canPublish"
      :is-loading="isLoading"
      :layout="layout"
      :inbox-id="inboxId"
      :is-filtered="isFiltered"
      @open-author="openAuthor"
      @open-mine="emit('openMine')"
      @publish="emit('publish')"
    />
  </div>
</template>
