<script setup>
// OUTSIDER: página Status do WhatsApp (ver app/controllers/api/v1/accounts/outsider/whatsapp_statuses_controller.rb).
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappStatusAPI from 'dashboard/api/outsider/whatsappStatus';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import StatusContactList from '../components/StatusContactList.vue';
import MyStatusPanel from '../components/MyStatusPanel.vue';
import StatusViewer from '../components/StatusViewer.vue';
import StatusPublishDialog from '../components/StatusPublishDialog.vue';
import StatusInteractionsDialog from '../components/StatusInteractionsDialog.vue';
import StatusPermissionsPanel from '../components/StatusPermissionsPanel.vue';
import {
  clearMediaCache,
  errorMessage,
  isActive,
  loadSeen,
  markSeen,
  saveSeen,
} from '../helpers';

const { t } = useI18n();

const isLoadingInboxes = ref(true);
const configured = ref(true);
const isAdmin = ref(false);
const permissions = ref([]);
const inboxes = ref([]);
const inboxId = ref(null);
const activeTab = ref('contacts');
const isLoading = ref(false);
const feed = ref({ me: null, authors: [] });
const mine = ref({ me: null, statuses: [] });
const period = ref(7);
const seen = ref(loadSeen());
const viewer = ref(null);
const publishDialogRef = ref(null);
const interactionsDialogRef = ref(null);

// { publish: true, ... } com o que este usuário pode fazer além de ver
const can = computed(() =>
  Object.fromEntries(permissions.value.map(permission => [permission, true]))
);

const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const me = computed(() => feed.value.me || mine.value.me);
const myName = computed(
  () => me.value?.name || t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.MY_STATUS')
);
// os meus que ainda estão no ar, do mais antigo para o mais novo (como o WhatsApp mostra)
const myActive = computed(() => mine.value.statuses.filter(isActive).reverse());

const isViewed = author =>
  author.statuses.every(status => seen.value[status.id]);
const recent = computed(() =>
  feed.value.authors.filter(author => !isViewed(author))
);
const viewed = computed(() => feed.value.authors.filter(isViewed));

const tabs = computed(() => [
  {
    key: 'contacts',
    label: t('OUTSIDER_WHATSAPP_STATUS.TABS.CONTACTS'),
    count: feed.value.authors.length,
  },
  {
    key: 'mine',
    label: t('OUTSIDER_WHATSAPP_STATUS.TABS.MINE'),
    count: mine.value.statuses.length,
  },
  ...(isAdmin.value
    ? [
        {
          key: 'permissions',
          label: t('OUTSIDER_WHATSAPP_STATUS.TABS.PERMISSIONS'),
        },
      ]
    : []),
]);

const loadFeed = async inbox => {
  const { data } = await WhatsappStatusAPI.getContacts(inbox);
  if (inbox === inboxId.value) feed.value = data;
};

const loadMine = async inbox => {
  const { data } = await WhatsappStatusAPI.getMine(inbox, period.value);
  if (inbox === inboxId.value) mine.value = data;
};

const load = async (...loaders) => {
  isLoading.value = true;
  try {
    await Promise.all(loaders.map(loader => loader(inboxId.value)));
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const refresh = () => load(loadFeed, loadMine);
const refreshMine = () => load(loadMine);

watch(inboxId, () => {
  feed.value = { me: null, authors: [] };
  mine.value = { me: null, statuses: [] };
  refresh();
});

watch(period, refreshMine);

onMounted(async () => {
  try {
    const { data } = await WhatsappStatusAPI.getInboxes();
    configured.value = data.configured;
    isAdmin.value = data.administrator;
    permissions.value = data.permissions;
    inboxes.value = data.payload;
    if (data.configured) inboxId.value = data.payload[0]?.id ?? null;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoadingInboxes.value = false;
  }
});

onBeforeUnmount(clearMediaCache);

const myStory = statuses => ({
  name: myName.value,
  avatar_url: me.value?.avatar_url,
  statuses,
});

const openAuthor = author => {
  const stories = [...recent.value, ...viewed.value];
  viewer.value = {
    stories,
    startIndex: stories.indexOf(author),
    isMine: false,
  };
};

const openMine = () => {
  viewer.value = {
    stories: [myStory(myActive.value)],
    startIndex: 0,
    isMine: true,
  };
};

const viewStatus = status => {
  viewer.value = { stories: [myStory([status])], startIndex: 0, isMine: true };
};

const onSeen = id => {
  seen.value = markSeen(seen.value, id);
  saveSeen(seen.value);
};

const openPublish = () => publishDialogRef.value.open();
const openInteractions = status => interactionsDialogRef.value.open(status);
</script>

<template>
  <section class="flex w-full h-full overflow-hidden bg-n-surface-1">
    <div class="flex flex-col w-full h-full">
      <header class="px-6">
        <div
          class="flex flex-wrap items-center justify-between w-full max-w-5xl gap-3 py-6 mx-auto"
        >
          <div class="flex items-center min-w-0 gap-3">
            <span class="text-xl font-medium truncate text-n-slate-12">
              {{ t('OUTSIDER_WHATSAPP_STATUS.TITLE') }}
            </span>
            <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
          </div>
          <div v-if="inboxId" class="flex items-center gap-2">
            <Select
              v-if="inboxes.length > 1"
              v-model="inboxId"
              :options="inboxOptions"
            />
            <Button
              v-tooltip.top="t('OUTSIDER_WHATSAPP_STATUS.REFRESH')"
              icon="i-lucide-refresh-cw"
              size="sm"
              variant="ghost"
              color="slate"
              :disabled="isLoading"
              @click="refresh"
            />
            <Button
              v-if="can.publish"
              icon="i-lucide-plus"
              size="sm"
              :label="t('OUTSIDER_WHATSAPP_STATUS.PUBLISH_BUTTON')"
              @click="openPublish"
            />
          </div>
        </div>
      </header>

      <main class="flex-1 px-6 overflow-y-auto">
        <div class="w-full max-w-5xl pb-8 mx-auto">
          <div v-if="isLoadingInboxes" class="flex justify-center p-8">
            <Spinner class="text-n-slate-10" />
          </div>
          <div
            v-else-if="!configured || !inboxId"
            class="flex flex-col items-center gap-3 p-10 text-center rounded-xl bg-n-alpha-1"
          >
            <Icon
              icon="i-lucide-circle-dashed"
              class="size-10 text-n-slate-9"
            />
            <p class="max-w-md mb-0 text-sm text-n-slate-11">
              <template v-if="!configured">
                {{
                  isAdmin
                    ? t('OUTSIDER_WHATSAPP_STATUS.STATES.NOT_CONFIGURED_ADMIN')
                    : t('OUTSIDER_WHATSAPP_STATUS.STATES.NOT_CONFIGURED')
                }}
              </template>
              <template v-else>
                {{ t('OUTSIDER_WHATSAPP_STATUS.STATES.NO_INBOXES') }}
              </template>
            </p>
          </div>
          <template v-else>
            <div class="p-px mb-6 overflow-x-auto">
              <TabBar
                :tabs="tabs"
                :initial-active-tab="
                  tabs.findIndex(tab => tab.key === activeTab)
                "
                @tab-changed="tab => (activeTab = tab.key)"
              />
            </div>
            <div v-if="activeTab === 'contacts'" class="flex gap-6">
              <StatusContactList
                class="w-full lg:flex-shrink-0 lg:w-96"
                :me="me"
                :my-statuses="myActive"
                :recent="recent"
                :viewed="viewed"
                :seen="seen"
                :can-publish="can.publish"
                :is-loading="isLoading"
                @open-author="openAuthor"
                @open-mine="openMine"
                @publish="openPublish"
              />
              <div
                class="flex-col items-center justify-center flex-1 hidden gap-3 p-10 text-center lg:flex rounded-xl bg-n-alpha-1 min-h-[24rem]"
              >
                <Icon
                  icon="i-lucide-circle-dashed"
                  class="size-12 text-n-slate-9"
                />
                <h3 class="text-base font-medium text-n-slate-12">
                  {{ t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.HINT_TITLE') }}
                </h3>
                <p class="max-w-sm mb-0 text-sm text-n-slate-11">
                  {{ t('OUTSIDER_WHATSAPP_STATUS.CONTACTS.HINT') }}
                </p>
              </div>
            </div>
            <MyStatusPanel
              v-else-if="activeTab === 'mine'"
              v-model:period="period"
              :statuses="mine.statuses"
              :is-loading="isLoading"
              :can="can"
              :inbox-id="inboxId"
              @view="viewStatus"
              @interactions="openInteractions"
              @republished="refreshMine"
            />
            <StatusPermissionsPanel v-else />
          </template>
        </div>
      </main>
    </div>

    <StatusViewer
      v-if="viewer"
      :stories="viewer.stories"
      :start-index="viewer.startIndex"
      :seen="seen"
      :inbox-id="inboxId"
      :is-mine="viewer.isMine"
      @close="viewer = null"
      @seen="onSeen"
      @interactions="openInteractions"
    />
    <StatusPublishDialog
      v-if="inboxId"
      ref="publishDialogRef"
      :inbox-id="inboxId"
      @published="refreshMine"
    />
    <StatusInteractionsDialog ref="interactionsDialogRef" />
  </section>
</template>
