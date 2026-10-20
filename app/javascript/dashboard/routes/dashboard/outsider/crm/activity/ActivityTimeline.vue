<script setup>
// OUTSIDER: linha do tempo do negócio, do mais novo para o mais antigo: notas internas do CRM e o
// que mudou (criação, etapa, situação, responsável, tarefas). A nota fica só no CRM: não vira
// mensagem do Chatwoot e o cliente nunca vê.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import LoadError from './LoadError.vue';
import { crmState } from '../crmStore';
import { errorMessage, formatDateTime } from '../helpers';

const props = defineProps({
  opportunity: { type: Object, required: true },
  // número da conversa aberta: a nota escrita aqui guarda de onde veio
  conversationDisplayId: { type: Number, default: null },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const KIND_ICONS = {
  note: 'i-lucide-sticky-note',
  created: 'i-lucide-sparkles',
  stage_changed: 'i-lucide-arrow-right-left',
  status_changed: 'i-lucide-flag',
  owner_changed: 'i-lucide-user-round-cog',
  task_created: 'i-lucide-list-plus',
  task_completed: 'i-lucide-circle-check',
  forwarded: 'i-lucide-forward',
  received: 'i-lucide-inbox',
  message_linked: 'i-lucide-message-square',
  automation: 'i-lucide-bot',
};

// texto de cada regra de automação (metadata.rule)
const AUTOMATION_TEXTS = {
  won_label: 'AUTOMATION_LABEL',
  lost_label: 'AUTOMATION_LABEL',
  close_tasks: 'AUTOMATION_CLOSE_TASKS',
  stalled_task: 'AUTOMATION_STALLED_TASK',
  custom: 'AUTOMATION_RULE',
};

// o que uma regra montada pelo administrador fez (ou deixou de fazer), na linha de detalhe
const ruleDetail = meta =>
  [
    meta.tasks && t('OUTSIDER_CRM.TIMELINE.RULE_TASKS', { count: meta.tasks }),
    meta.owner && t('OUTSIDER_CRM.TIMELINE.RULE_OWNER', { name: meta.owner }),
    meta.label && t('OUTSIDER_CRM.TIMELINE.RULE_LABEL', { label: meta.label }),
    meta.note && t('OUTSIDER_CRM.TIMELINE.RULE_NOTE'),
    ...(meta.skipped || []).map(code =>
      t(`OUTSIDER_CRM.TIMELINE.RULE_SKIPPED.${code.toUpperCase()}`)
    ),
  ]
    .filter(Boolean)
    .join(' · ');

// encaminhamento: a observação de quem encaminhou aparece como a nota, em âmbar
const FORWARD_KINDS = ['forwarded', 'received'];

const items = ref([]);
const hasMore = ref(false);
const isLoading = ref(false);
const isLoadingMore = ref(false);
const loadError = ref('');
const body = ref('');
const isSaving = ref(false);
const confirmingId = ref(null);

const version = computed(() => crmState.activityVersion[props.opportunity.id]);

const load = async (more = false) => {
  if (more) isLoadingMore.value = true;
  else isLoading.value = !items.value.length;
  try {
    const params = more ? { before_id: items.value.at(-1)?.id } : {};
    const { data } = await CrmAPI.getActivities(props.opportunity.id, params);
    items.value = more ? [...items.value, ...data.payload] : data.payload;
    hasMore.value = data.meta.has_more;
    loadError.value = '';
  } catch (error) {
    if (more) useAlert(errorMessage(t, error));
    else loadError.value = errorMessage(t, error);
  } finally {
    isLoading.value = false;
    isLoadingMore.value = false;
  }
};

const saveNote = async () => {
  const text = body.value.trim();
  if (!text || isSaving.value) return;
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.createNote(
      props.opportunity.id,
      text,
      props.conversationDisplayId
    );
    items.value = [data, ...items.value];
    body.value = '';
    useAlert(t('OUTSIDER_CRM.TIMELINE.NOTE_SAVED'));
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

const onKeydown = event => {
  if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) saveNote();
};

const removeNote = async item => {
  confirmingId.value = null;
  try {
    await CrmAPI.deleteActivity(props.opportunity.id, item.id);
    items.value = items.value.filter(entry => entry.id !== item.id);
    useAlert(t('OUTSIDER_CRM.TIMELINE.NOTE_DELETED'));
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const statusLabel = status =>
  status ? t(`OUTSIDER_CRM.STATUS.${String(status).toUpperCase()}`) : '—';

const describe = item => {
  const name = item.user?.name || t('OUTSIDER_CRM.TIMELINE.SYSTEM');
  const meta = item.metadata || {};
  switch (item.kind) {
    case 'note':
      return t('OUTSIDER_CRM.TIMELINE.NOTE', { name });
    case 'created':
      return t('OUTSIDER_CRM.TIMELINE.CREATED', { name, stage: meta.stage });
    case 'stage_changed':
      return t('OUTSIDER_CRM.TIMELINE.STAGE_CHANGED', {
        name,
        from: meta.from || '—',
        to: meta.to || '—',
      });
    case 'status_changed':
      return t('OUTSIDER_CRM.TIMELINE.STATUS_CHANGED', {
        name,
        from: statusLabel(meta.from),
        to: statusLabel(meta.to),
      });
    case 'owner_changed':
      return t('OUTSIDER_CRM.TIMELINE.OWNER_CHANGED', {
        name,
        from: meta.from || '—',
        to: meta.to || '—',
      });
    case 'task_created':
      return t('OUTSIDER_CRM.TIMELINE.TASK_CREATED', {
        name,
        title: meta.title,
      });
    case 'task_completed':
      return t('OUTSIDER_CRM.TIMELINE.TASK_COMPLETED', {
        name,
        title: meta.title,
      });
    case 'forwarded':
      return t('OUTSIDER_CRM.TIMELINE.FORWARDED', {
        name,
        unit: meta.to_unit || '—',
        code: meta.to_code || '',
      });
    case 'received':
      return t('OUTSIDER_CRM.TIMELINE.RECEIVED', {
        name,
        unit: meta.from_unit || '—',
        code: meta.from_code || '',
      });
    case 'automation':
      return t(
        `OUTSIDER_CRM.TIMELINE.${
          meta.missing
            ? 'AUTOMATION_LABEL_MISSING'
            : AUTOMATION_TEXTS[meta.rule] || 'AUTOMATION'
        }`,
        {
          label: meta.label,
          count: meta.count,
          days: meta.days,
          stage: meta.stage,
          rule: meta.rule_name,
        }
      );
    default:
      return t(`OUTSIDER_CRM.TIMELINE.${item.kind.toUpperCase()}`, { name });
  }
};

const detail = item => {
  const meta = item.metadata || {};
  if (item.kind === 'automation' && meta.rule === 'custom') {
    return ruleDetail(meta);
  }
  if (item.kind === 'status_changed' && meta.lost_reason) {
    return t('OUTSIDER_CRM.TIMELINE.LOST_REASON', { reason: meta.lost_reason });
  }
  if (item.kind === 'forwarded' || item.kind === 'received') {
    return [
      meta.reason && t('OUTSIDER_CRM.HISTORY.REASON', { reason: meta.reason }),
      meta.attempt &&
        t('OUTSIDER_CRM.HISTORY.ATTEMPT', {
          current: meta.attempt,
          max: meta.max,
        }),
      item.kind === 'forwarded' &&
        meta.owner &&
        t('OUTSIDER_CRM.TIMELINE.FORWARD_OWNER', { name: meta.owner }),
    ]
      .filter(Boolean)
      .join(' · ');
  }
  if (item.kind === 'task_created' && meta.due_at) {
    const due = formatDateTime(meta.due_at, t);
    return meta.assignee
      ? t('OUTSIDER_CRM.TIMELINE.TASK_DUE_FOR', {
          date: due,
          name: meta.assignee,
        })
      : t('OUTSIDER_CRM.TIMELINE.TASK_DUE', { date: due });
  }
  return '';
};

watch(
  () => [props.opportunity.id, version.value],
  () => load()
);
onMounted(() => load());
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-if="opportunity.status !== 'forwarded'"
      class="flex flex-col gap-2 p-3 rounded-lg bg-n-violet-2 outline outline-1 -outline-offset-1 outline-n-violet-5"
    >
      <span
        class="flex items-center gap-1.5 text-xs font-medium text-n-violet-11"
      >
        <Icon icon="i-lucide-lock" class="size-3" />
        {{ t('OUTSIDER_CRM.TIMELINE.NOTE_HINT') }}
      </span>
      <textarea
        v-model="body"
        rows="2"
        maxlength="20000"
        class="!mb-0 w-full px-3 py-2 text-sm rounded-lg resize-y reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-violet-8"
        :placeholder="t('OUTSIDER_CRM.TIMELINE.NOTE_PLACEHOLDER')"
        @keydown="onKeydown"
      />
      <div class="flex justify-end">
        <Button
          type="button"
          size="sm"
          color="slate"
          icon="i-lucide-sticky-note"
          :label="t('OUTSIDER_CRM.TIMELINE.SAVE_NOTE')"
          :is-loading="isSaving"
          :disabled="!body.trim()"
          @click="saveNote"
        />
      </div>
    </div>

    <div v-if="isLoading" class="flex justify-center p-4 text-n-slate-10">
      <Spinner :size="18" />
    </div>

    <LoadError v-else-if="loadError" :message="loadError" @retry="load()" />

    <ol v-else class="flex flex-col mb-0 list-none">
      <li
        v-for="item in items"
        :key="item.id"
        class="relative flex gap-3 pb-4 last:pb-0 group"
      >
        <span
          class="absolute w-px left-3.5 top-8 bottom-0 bg-n-weak group-last:hidden"
        />
        <span
          class="z-10 flex items-center justify-center rounded-full size-7 shrink-0"
          :class="
            item.kind === 'note'
              ? 'bg-n-violet-3 text-n-violet-11'
              : FORWARD_KINDS.includes(item.kind)
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          <Icon
            :icon="KIND_ICONS[item.kind] || 'i-lucide-dot'"
            class="size-3.5"
          />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1 pt-1">
          <div class="flex flex-wrap items-baseline gap-x-2 text-sm">
            <span class="text-n-slate-12">{{ describe(item) }}</span>
            <span class="text-xs text-n-slate-10">
              {{ formatDateTime(item.created_at, t) }}
            </span>
          </div>
          <p
            v-if="item.kind === 'note'"
            class="px-3 py-2 mb-0 text-sm break-words whitespace-pre-wrap rounded-lg bg-n-violet-2 text-n-slate-12"
          >
            {{ item.body }}
          </p>
          <p
            v-else-if="FORWARD_KINDS.includes(item.kind) && item.body"
            class="px-3 py-2 mb-0 text-sm break-words whitespace-pre-wrap rounded-lg bg-n-amber-2 text-n-slate-12"
          >
            {{ item.body }}
          </p>
          <span v-if="detail(item)" class="text-xs text-n-slate-11">
            {{ detail(item) }}
          </span>
          <div
            v-if="item.metadata?.conversation_display_id || item.can_delete"
            class="flex items-center gap-3 text-xs"
          >
            <router-link
              v-if="item.metadata?.conversation_display_id"
              :to="
                accountScopedRoute('inbox_conversation', {
                  conversation_id: item.metadata.conversation_display_id,
                })
              "
              class="text-n-blue-11 hover:underline"
            >
              {{
                t('OUTSIDER_CRM.TIMELINE.FROM_CONVERSATION', {
                  id: item.metadata.conversation_display_id,
                })
              }}
            </router-link>
            <template v-if="item.can_delete">
              <button
                v-if="confirmingId !== item.id"
                type="button"
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="confirmingId = item.id"
              >
                {{ t('OUTSIDER_CRM.TIMELINE.DELETE_NOTE') }}
              </button>
              <template v-else>
                <button
                  type="button"
                  class="font-medium text-n-ruby-11 hover:underline"
                  @click="removeNote(item)"
                >
                  {{ t('OUTSIDER_CRM.TIMELINE.CONFIRM_DELETE') }}
                </button>
                <button
                  type="button"
                  class="text-n-slate-10 hover:underline"
                  @click="confirmingId = null"
                >
                  {{ t('OUTSIDER_CRM.CANCEL') }}
                </button>
              </template>
            </template>
          </div>
        </div>
      </li>
    </ol>

    <Button
      v-if="hasMore"
      type="button"
      size="sm"
      variant="ghost"
      color="slate"
      class="self-center"
      :label="t('OUTSIDER_CRM.TIMELINE.LOAD_MORE')"
      :is-loading="isLoadingMore"
      @click="load(true)"
    />
  </div>
</template>
