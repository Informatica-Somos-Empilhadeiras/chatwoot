<script setup>
// OUTSIDER: quem viu, quem curtiu e quem respondeu um dos meus status.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import WhatsappStatusAPI from 'dashboard/api/outsider/whatsappStatus';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StatusThumbnail from './StatusThumbnail.vue';
import { errorMessage, formatPhone, timeLabel, typeLabel } from '../helpers';

const props = defineProps({
  inboxId: { type: Number, default: null },
});

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const dialogRef = ref(null);
const status = ref(null);
const activeTab = ref('likes');
// quem viu é buscado só quando a aba abre
const viewers = ref(null);
const isLoadingViewers = ref(false);

const hasViews = computed(() => status.value?.views != null);

const tabs = computed(() => [
  ...(hasViews.value
    ? [
        {
          key: 'views',
          label: t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.VIEWS'),
          count: status.value.views,
        },
      ]
    : []),
  {
    key: 'likes',
    label: t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.LIKES'),
    count: status.value?.reactions.length,
  },
  {
    key: 'replies',
    label: t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.REPLIES'),
    count: status.value?.replies.length,
  },
]);

const contactRoute = contactId =>
  accountScopedRoute('contacts_edit', { contactId });

const loadViewers = async () => {
  const current = status.value;
  isLoadingViewers.value = true;
  try {
    const { data } = await WhatsappStatusAPI.getViewers(
      props.inboxId,
      current.id
    );
    if (status.value === current) viewers.value = data.payload;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoadingViewers.value = false;
  }
};

const changeTab = tab => {
  activeTab.value = tab.key;
  if (tab.key === 'views' && viewers.value === null) loadViewers();
};

const open = (selected, tab = 'likes') => {
  status.value = selected;
  viewers.value = null;
  activeTab.value = tab === 'views' && selected.views == null ? 'likes' : tab;
  dialogRef.value.open();
  if (activeTab.value === 'views') loadViewers();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.TITLE')"
    width="lg"
    overflow-y-auto
    :show-confirm-button="false"
    :cancel-button-label="t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.CLOSE')"
  >
    <div v-if="status" class="flex flex-col gap-4">
      <div class="flex items-center gap-3">
        <StatusThumbnail
          :status="status"
          class="flex-shrink-0 rounded-lg size-12"
        />
        <div class="flex flex-col min-w-0">
          <span class="text-sm truncate text-n-slate-12">
            {{ status.text || typeLabel(t, status.type) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ timeLabel(t, status.timestamp) }}
          </span>
        </div>
      </div>

      <TabBar
        :key="status.id"
        :tabs="tabs"
        :initial-active-tab="tabs.findIndex(tab => tab.key === activeTab)"
        @tab-changed="changeTab"
      />

      <template v-if="activeTab === 'views'">
        <div v-if="isLoadingViewers" class="flex justify-center py-4">
          <Spinner class="text-n-slate-10" />
        </div>
        <ul v-else-if="viewers?.length" class="flex flex-col list-none">
          <li
            v-for="viewer in viewers"
            :key="viewer.jid"
            class="flex items-center gap-3 py-2"
          >
            <Avatar
              :name="viewer.name || ''"
              :src="viewer.avatar_url"
              :size="32"
              rounded-full
            />
            <div class="flex flex-col flex-1 min-w-0">
              <router-link
                v-if="viewer.contact_id"
                :to="contactRoute(viewer.contact_id)"
                class="text-sm truncate text-n-slate-12 hover:underline"
              >
                {{ viewer.name }}
              </router-link>
              <span
                v-else
                class="text-sm truncate"
                :class="viewer.phone ? 'text-n-slate-12' : 'text-n-slate-10'"
              >
                {{
                  viewer.phone
                    ? formatPhone(viewer.phone)
                    : t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.UNKNOWN_VIEWER')
                }}
              </span>
              <span
                v-if="viewer.contact_id && viewer.phone"
                class="text-xs text-n-slate-11"
              >
                {{ formatPhone(viewer.phone) }}
              </span>
            </div>
          </li>
        </ul>
        <p v-else class="py-4 mb-0 text-sm text-center text-n-slate-11">
          {{ t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.NO_VIEWS') }}
        </p>
      </template>

      <ul
        v-else-if="activeTab === 'likes' && status.reactions.length"
        class="flex flex-col list-none"
      >
        <li
          v-for="(reaction, index) in status.reactions"
          :key="index"
          class="flex items-center gap-3 py-2"
        >
          <Avatar
            :name="reaction.name"
            :src="reaction.avatar_url"
            :size="32"
            rounded-full
          />
          <div class="flex flex-col flex-1 min-w-0">
            <router-link
              v-if="reaction.contact_id"
              :to="contactRoute(reaction.contact_id)"
              class="text-sm truncate text-n-slate-12 hover:underline"
            >
              {{ reaction.name }}
            </router-link>
            <span v-else class="text-sm truncate text-n-slate-12">
              {{ reaction.name }}
            </span>
            <span v-if="reaction.phone" class="text-xs text-n-slate-11">
              {{ formatPhone(reaction.phone) }}
            </span>
          </div>
          <span class="text-xl">{{ reaction.emoji }}</span>
          <span class="text-xs text-n-slate-10">
            {{ timeLabel(t, reaction.timestamp) }}
          </span>
        </li>
      </ul>

      <ul
        v-else-if="activeTab === 'replies' && status.replies.length"
        class="flex flex-col list-none"
      >
        <li
          v-for="(reply, index) in status.replies"
          :key="index"
          class="flex items-start gap-3 py-2"
        >
          <Avatar
            :name="reply.name"
            :src="reply.avatar_url"
            :size="32"
            rounded-full
          />
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <div class="flex items-center gap-2">
              <router-link
                :to="contactRoute(reply.contact_id)"
                class="text-sm truncate text-n-slate-12 hover:underline"
              >
                {{ reply.name }}
              </router-link>
              <span class="text-xs text-n-slate-10">
                {{ timeLabel(t, reply.timestamp) }}
              </span>
            </div>
            <p
              class="mb-0 text-sm break-words whitespace-pre-line text-n-slate-11"
            >
              {{ reply.content }}
            </p>
            <router-link
              :to="
                accountScopedRoute('inbox_conversation', {
                  conversation_id: reply.conversation_id,
                })
              "
              class="flex items-center gap-1 text-xs w-fit text-n-blue-11 hover:underline"
            >
              <Icon icon="i-lucide-message-circle" class="size-3.5" />
              {{ t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.OPEN_CONVERSATION') }}
            </router-link>
          </div>
        </li>
      </ul>

      <p v-else class="py-4 mb-0 text-sm text-center text-n-slate-11">
        {{
          activeTab === 'likes'
            ? t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.NO_LIKES')
            : t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.NO_REPLIES')
        }}
      </p>

      <p class="mb-0 text-xs text-n-slate-10">
        {{ t('OUTSIDER_WHATSAPP_STATUS.INTERACTIONS.NOTE') }}
      </p>
    </div>
  </Dialog>
</template>
