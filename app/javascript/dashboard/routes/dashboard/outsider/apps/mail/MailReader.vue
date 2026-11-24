<script setup>
// OUTSIDER: um e-mail aberto nos Aplicativos: assunto, de/para, os anexos (abrem no visualizador do Chatwoot ou baixam),
// o corpo num quadro isolado (sem scripts; links abrem em outra aba) e as ações: Responder, Responder a todos,
// Encaminhar, Não lido, Sinalizar, Mover, Excluir e Abrir no Outlook. Se o remetente é um contato do Chatwoot, aparecem
// "Abrir conversa" e "Ver contato".
import { computed, onBeforeUnmount, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AppsAPI from 'dashboard/api/outsider/apps';
import { openFileViewer } from 'dashboard/components-next/outsider/fileViewer/fileViewerStore';
import { formatSize } from 'dashboard/components-next/outsider/mediaViewer/mediaHelpers';
import { errorText } from '../appsErrors';
import { providerOf, textKey } from '../providers';
import { initialsOf, avatarTone, fullDate, peopleText } from './mailHelpers';

const props = defineProps({
  provider: { type: String, required: true },
  messageId: { type: String, required: true },
  folders: { type: Array, default: () => [] },
});

const emit = defineEmits(['back', 'changed', 'reply']);
const { t } = useI18n();
const route = useRoute();

const message = ref(null);
const isLoading = ref(true);
const error = ref('');
const frame = ref(null);
const frameHeight = ref(320);
const showMove = ref(false);

const accountId = computed(() => route.params.accountId);
// o Gmail não deixa pôr e-mail em Enviados (movable: false); rascunho também não é destino
const moveTargets = computed(() =>
  props.folders.filter(
    folder => !['drafts'].includes(folder.kind) && folder.movable !== false
  )
);
const tk = path => textKey(props.provider, path);
const flagIcon = computed(
  () => providerOf(props.provider).mail.flagIcon || 'i-lucide-flag'
);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await AppsAPI.mailMessage(props.provider, props.messageId);
    message.value = data;
  } catch (e) {
    error.value = errorText(e, t);
  } finally {
    isLoading.value = false;
  }
};

// o quadro cresce até o tamanho do e-mail (sem barra de rolagem dentro de outra)
let observer = null;
const fit = () => {
  const doc = frame.value?.contentDocument;
  if (!doc?.body) return;
  frameHeight.value = Math.max(doc.documentElement.scrollHeight, 120) + 8;
};
const onFrameLoad = () => {
  fit();
  const doc = frame.value?.contentDocument;
  if (!doc?.body || typeof ResizeObserver === 'undefined') return;
  observer?.disconnect();
  observer = new ResizeObserver(fit);
  observer.observe(doc.body);
};
onBeforeUnmount(() => observer?.disconnect());

const srcdoc = computed(() => {
  const html = message.value?.html || '';
  const style =
    '<style>body{margin:0;padding:4px 2px;font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#1f2328;' +
    'word-wrap:break-word;overflow-wrap:anywhere}img{max-width:100%;height:auto}table{max-width:100%}</style>';
  return html.includes('<head>')
    ? html.replace('<head>', `<head>${style}`)
    : `${style}${html}`;
});

const update = async changes => {
  try {
    const { data } = await AppsAPI.updateMail(
      props.provider,
      props.messageId,
      changes
    );
    message.value = {
      ...message.value,
      unread: data.unread,
      flagged: data.flagged,
    };
    emit('changed', {
      id: props.messageId,
      changes: { unread: data.unread, flagged: data.flagged },
    });
  } catch (e) {
    useAlert(errorText(e, t));
  }
};

const move = async destination => {
  showMove.value = false;
  try {
    await AppsAPI.moveMail(props.provider, props.messageId, destination);
    useAlert(
      destination === 'deleteditems'
        ? t(tk('MAIL.DELETED'))
        : t('OUTSIDER_APPS.MAIL.MOVED')
    );
    emit('changed', { id: props.messageId, removed: true });
  } catch (e) {
    useAlert(errorText(e, t));
  }
};

const extension = name =>
  String(name || '')
    .split('.')
    .pop()
    .toLowerCase();

const openAttachment = attachment => {
  const ext = extension(attachment.name);
  const image = (attachment.content_type || '').startsWith('image/');
  const pdf = ext === 'pdf' || attachment.content_type === 'application/pdf';
  if (!image && !pdf) {
    window.open(`${attachment.url}&download=1`, '_blank', 'noopener');
    return;
  }
  openFileViewer({
    name: attachment.name,
    extension: ext,
    size: attachment.size,
    kind: image ? 'image' : 'pdf',
    viewUrl: attachment.url,
    downloadUrl: `${attachment.url}&download=1`,
  });
};

load();
</script>

<template>
  <article class="flex flex-col flex-1 min-w-0" data-apps-mail-reader>
    <div v-if="isLoading" class="flex justify-center flex-1 py-10">
      <Spinner :size="20" />
    </div>
    <p v-else-if="error" class="px-6 py-10 text-sm text-center text-n-ruby-11">
      {{ error }}
    </p>
    <template v-else-if="message">
      <header
        class="flex items-start gap-3 px-4 py-3 border-b md:px-6 border-n-weak"
      >
        <button
          type="button"
          class="mt-1 md:hidden text-n-slate-11"
          :aria-label="t('OUTSIDER_APPS.BACK')"
          @click="emit('back')"
        >
          <Icon icon="i-lucide-chevron-left" class="size-6" />
        </button>
        <div class="flex-1 min-w-0">
          <h2
            class="mb-1 text-lg font-semibold leading-snug break-words text-n-slate-12"
            data-apps-mail-subject
          >
            {{ message.subject || t('OUTSIDER_APPS.MAIL.NO_SUBJECT') }}
          </h2>
          <div class="flex items-center gap-2">
            <span
              class="grid text-xs font-semibold rounded-full size-8 place-items-center shrink-0"
              :class="avatarTone(message.from?.email || message.from?.name)"
            >
              {{ initialsOf(message.from?.name || message.from?.email) }}
            </span>
            <div class="min-w-0 text-xs text-n-slate-11">
              <p class="mb-0 truncate">
                <b class="text-sm text-n-slate-12">{{ message.from?.name }}</b>
                <span v-if="message.from?.email">
                  &lt;{{ message.from.email }}&gt;</span
                >
              </p>
              <p class="mb-0 truncate">
                {{ t('OUTSIDER_APPS.MAIL.TO') }}: {{ peopleText(message.to) }}
                <template v-if="message.cc?.length">
                  · {{ t('OUTSIDER_APPS.MAIL.CC') }}:
                  {{ peopleText(message.cc) }}
                </template>
              </p>
              <p class="mb-0">{{ fullDate(message.date) }}</p>
            </div>
          </div>
        </div>
      </header>

      <div
        class="flex flex-wrap items-center gap-1.5 px-4 py-2 border-b md:px-6 border-n-weak"
      >
        <button
          type="button"
          class="oa-ghost"
          data-apps-mail-reply
          @click="emit('reply', 'reply', message)"
        >
          <Icon icon="i-lucide-reply" class="size-4" />
          {{ t('OUTSIDER_APPS.MAIL.REPLY') }}
        </button>
        <button
          type="button"
          class="oa-ghost"
          @click="emit('reply', 'reply_all', message)"
        >
          <Icon icon="i-lucide-reply-all" class="size-4" />
          <span class="hidden xl:inline">{{
            t('OUTSIDER_APPS.MAIL.REPLY_ALL')
          }}</span>
        </button>
        <button
          type="button"
          class="oa-ghost"
          @click="emit('reply', 'forward', message)"
        >
          <Icon icon="i-lucide-forward" class="size-4" />
          <span class="hidden xl:inline">{{
            t('OUTSIDER_APPS.MAIL.FORWARD')
          }}</span>
        </button>
        <span class="flex-1" />
        <button
          type="button"
          class="oa-ghost"
          :title="t('OUTSIDER_APPS.MAIL.MARK_UNREAD')"
          @click="update({ read: false })"
        >
          <Icon icon="i-lucide-mail" class="size-4" />
        </button>
        <button
          type="button"
          class="oa-ghost"
          :class="{ '!text-n-ruby-11': message.flagged }"
          :title="t(tk(message.flagged ? 'MAIL.UNFLAG' : 'MAIL.FLAG'))"
          @click="update({ flagged: !message.flagged })"
        >
          <Icon :icon="flagIcon" class="size-4" />
        </button>
        <span class="relative">
          <button
            type="button"
            class="oa-ghost"
            :title="t('OUTSIDER_APPS.MAIL.MOVE')"
            @click="showMove = !showMove"
          >
            <Icon icon="i-lucide-folder-input" class="size-4" />
          </button>
          <ul
            v-if="showMove"
            class="absolute right-0 z-30 w-56 p-1 mt-1 overflow-y-auto border shadow-lg max-h-72 rounded-xl bg-n-surface-1 border-n-weak"
          >
            <li v-for="folder in moveTargets" :key="folder.id">
              <button
                type="button"
                class="w-full px-3 py-1.5 text-sm text-left rounded-lg hover:bg-n-alpha-1 text-n-slate-12 truncate"
                @click="move(folder.id)"
              >
                {{ folder.name }}
              </button>
            </li>
          </ul>
        </span>
        <button
          type="button"
          class="oa-ghost is-danger"
          :title="t(tk('MAIL.DELETE'))"
          data-apps-mail-delete
          @click="move('deleteditems')"
        >
          <Icon icon="i-lucide-trash-2" class="size-4" />
        </button>
        <a
          v-if="message.web_link"
          :href="message.web_link"
          target="_blank"
          rel="noopener noreferrer"
          class="oa-ghost"
          :title="t(tk('MAIL.OPEN_WEB'))"
        >
          <Icon icon="i-lucide-external-link" class="size-4" />
        </a>
      </div>

      <div class="flex-1 min-h-0 px-4 py-4 overflow-y-auto md:px-6">
        <div
          v-if="message.chatwoot"
          class="flex flex-wrap gap-2 mb-3"
          data-apps-mail-contact
        >
          <RouterLink
            v-if="message.chatwoot.conversation_id"
            class="oa-ghost"
            :to="{
              name: 'inbox_conversation',
              params: {
                accountId,
                conversation_id: message.chatwoot.conversation_id,
              },
            }"
          >
            <Icon icon="i-lucide-message-circle" class="size-4" />
            {{ t('OUTSIDER_APPS.MAIL.OPEN_CONVERSATION') }}
          </RouterLink>
          <RouterLink
            class="oa-ghost"
            :to="{
              name: 'contacts_edit',
              params: { accountId, contactId: message.chatwoot.contact_id },
            }"
          >
            <Icon icon="i-lucide-contact" class="size-4" />
            {{
              t('OUTSIDER_APPS.MAIL.OPEN_CONTACT', {
                name: message.chatwoot.name,
              })
            }}
          </RouterLink>
        </div>

        <div
          v-if="message.attachments?.length"
          class="flex flex-wrap gap-2 mb-4"
          data-apps-mail-attachments
        >
          <div
            v-for="attachment in message.attachments"
            :key="attachment.id"
            class="flex items-center gap-1 pr-2 border rounded-xl border-n-weak max-w-[260px]"
          >
            <button
              type="button"
              class="flex items-center flex-1 min-w-0 gap-2 py-2 pl-3 text-left rounded-xl hover:bg-n-alpha-1"
              @click="openAttachment(attachment)"
            >
              <Icon
                :icon="
                  (attachment.content_type || '').startsWith('image/')
                    ? 'i-lucide-image'
                    : 'i-lucide-file-text'
                "
                class="size-5 text-n-slate-11 shrink-0"
              />
              <span class="min-w-0">
                <span class="block text-sm truncate text-n-slate-12">{{
                  attachment.name
                }}</span>
                <span class="block text-[11px] text-n-slate-10">{{
                  formatSize(attachment.size)
                }}</span>
              </span>
            </button>
            <a
              :href="`${attachment.url}&download=1`"
              class="p-1 text-n-slate-10 hover:text-n-slate-12"
              :title="t('OUTSIDER_APPS.DOWNLOAD')"
            >
              <Icon icon="i-lucide-download" class="size-4" />
            </a>
          </div>
        </div>

        <iframe
          ref="frame"
          class="oa-mail-frame"
          :style="{ height: `${frameHeight}px` }"
          sandbox="allow-same-origin allow-popups allow-popups-to-escape-sandbox"
          referrerpolicy="no-referrer"
          :srcdoc="srcdoc"
          :title="message.subject || ''"
          data-apps-mail-body
          @load="onFrameLoad"
        />
      </div>
    </template>
  </article>
</template>
