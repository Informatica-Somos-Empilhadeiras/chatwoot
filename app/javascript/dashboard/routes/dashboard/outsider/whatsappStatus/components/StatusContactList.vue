<script setup>
// OUTSIDER: status dos contatos como no WhatsApp: o meu no topo, depois Recentes e Vistos,
// em grade (prévia de cada contato) ou em lista.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import StatusRing from './StatusRing.vue';
import StatusContactCard from './StatusContactCard.vue';
import StatusThumbnail from './StatusThumbnail.vue';
import { timeLabel } from '../helpers';

const props = defineProps({
  me: { type: Object, default: null },
  // meus status no ar, do mais antigo para o mais novo
  myStatuses: { type: Array, default: () => [] },
  recent: { type: Array, default: () => [] },
  viewed: { type: Array, default: () => [] },
  seen: { type: Object, default: () => ({}) },
  canPublish: { type: Boolean, default: false },
  isLoading: { type: Boolean, default: false },
  // 'cards' ou 'list'
  layout: { type: String, default: 'cards' },
  inboxId: { type: Number, required: true },
  // com busca ou filtro, a lista vazia tem outra mensagem
  isFiltered: { type: Boolean, default: false },
});

const emit = defineEmits(['openAuthor', 'openMine', 'publish']);

const { t } = useI18n();

const sections = computed(() =>
  [
    {
      key: 'recent',
      title: t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.RECENT'),
      authors: props.recent,
    },
    {
      key: 'viewed',
      title: t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.SEEN'),
      authors: props.viewed,
    },
  ].filter(section => section.authors.length)
);

const myDescription = computed(() => {
  const count = props.myStatuses.length;
  if (!count) return t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.MY_STATUS_EMPTY');
  return t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.MY_STATUS_COUNT', {
    count,
    time: timeLabel(t, props.myStatuses[count - 1].timestamp),
  });
});
</script>

<template>
  <div class="flex flex-col gap-5">
    <div
      class="flex items-center gap-2 p-2 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <button
        type="button"
        class="flex items-center flex-1 min-w-0 gap-3 p-1 rounded-lg text-start enabled:hover:bg-n-alpha-2 disabled:cursor-default disabled:opacity-100"
        :disabled="!myStatuses.length"
        @click="emit('openMine')"
      >
        <StatusRing
          :name="me?.name || t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.MY_STATUS')"
          :src="me?.avatar_url"
          :seen-flags="myStatuses.map(() => false)"
        />
        <span class="flex flex-col min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.MY_STATUS') }}
          </span>
          <span class="text-xs truncate text-n-slate-11">
            {{ myDescription }}
          </span>
        </span>
      </button>
      <Button
        v-if="canPublish"
        v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.PUBLISH_BUTTON')"
        icon="i-lucide-plus"
        size="sm"
        variant="faded"
        @click="emit('publish')"
      />
    </div>

    <section v-for="section in sections" :key="section.key">
      <h3 class="px-2 mb-2 text-xs font-medium uppercase text-n-teal-11">
        {{ section.title }}
      </h3>
      <ul
        v-if="layout === 'cards'"
        class="grid grid-cols-2 gap-3 list-none sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5"
      >
        <li v-for="author in section.authors" :key="author.jid">
          <StatusContactCard
            :author="author"
            :seen="seen"
            :inbox-id="inboxId"
            @click="emit('openAuthor', author)"
          />
        </li>
      </ul>
      <ul v-else class="grid grid-cols-1 list-none gap-x-4 gap-y-1 md:grid-cols-2">
        <li v-for="author in section.authors" :key="author.jid">
          <button
            type="button"
            class="flex items-center w-full gap-3 p-1 rounded-lg text-start hover:bg-n-alpha-2"
            @click="emit('openAuthor', author)"
          >
            <StatusRing
              :name="author.name"
              :src="author.avatar_url"
              :seen-flags="author.statuses.map(status => !!seen[status.id])"
            />
            <span class="flex flex-col flex-1 min-w-0">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ author.name }}
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{ timeLabel(t, author.statuses.at(-1).timestamp) }}
              </span>
            </span>
            <StatusThumbnail
              :status="author.statuses.at(-1)"
              class="flex-shrink-0 rounded-md size-11"
            />
          </button>
        </li>
      </ul>
    </section>

    <p
      v-if="!sections.length && !isLoading"
      class="px-2 text-sm text-n-slate-11"
    >
      {{
        isFiltered
          ? t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.EMPTY_FILTER')
          : t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.EMPTY')
      }}
    </p>
  </div>
</template>
