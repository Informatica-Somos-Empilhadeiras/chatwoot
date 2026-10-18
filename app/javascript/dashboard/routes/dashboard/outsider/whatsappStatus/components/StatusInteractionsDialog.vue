<script setup>
// OUTSIDER: quem curtiu e quem respondeu um dos meus status.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import StatusThumbnail from './StatusThumbnail.vue';
import { formatPhone, timeLabel, typeLabel } from '../helpers';

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const dialogRef = ref(null);
const status = ref(null);
const activeTab = ref('likes');

const tabs = computed(() => [
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

const open = selected => {
  status.value = selected;
  activeTab.value = 'likes';
  dialogRef.value.open();
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
        :tabs="tabs"
        :initial-active-tab="activeTab === 'likes' ? 0 : 1"
        @tab-changed="tab => (activeTab = tab.key)"
      />

      <ul
        v-if="activeTab === 'likes' && status.reactions.length"
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
