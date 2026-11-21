<script setup>
// OUTSIDER: o PDF à esquerda e o envio ao cliente à direita. Do orçamento já no ERP (o PDF oficial, com os impostos que
// o ERP calculou, e o histórico de envios) ou de outra fonte, como o relatório da OS (ErpOrderSendDialog), que passa
// source = { pdf, delivery, contacts(q), deliver(payload), labels }. E-mail: vários endereços (já vêm o do contato e,
// no orçamento, os do cliente no ERP), assunto e mensagem com o texto padrão das Configurações. WhatsApp: na conversa
// do contato (ou de outro, pela busca) numa caixa de WhatsApp, com a mensagem.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { formatDate } from '../erpStore';
import { blobError, budgetErrorMessage } from './budgetHelpers';

const props = defineProps({
  budget: { type: Object, default: null },
  source: { type: Object, default: null },
});

const emit = defineEmits(['sent', 'meta']);

const { t } = useI18n();
const pdfUrl = ref('');
const pdfLoading = ref(true);
const pdfFailure = ref('');
const loading = ref(true);
const failure = ref('');
const sending = ref(false);
const channel = ref('email');
const delivery = ref(null);
const emails = ref([]);
const emailDraft = ref('');
const subject = ref('');
const emailBody = ref('');
const whatsappText = ref('');
const contact = ref(null);
const inboxId = ref(null);
const searching = ref(false);
const contactQuery = ref('');
const contactResults = ref([]);

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// sem source, o orçamento (props.budget)
const api = computed(
  () =>
    props.source || {
      pdf: () => ErpAPI.budgetPdf(props.budget.id),
      delivery: () => ErpAPI.budgetDelivery(props.budget.id),
      contacts: q => ErpAPI.budgetContacts(props.budget.id, q),
      deliver: payload => ErpAPI.deliverBudget(props.budget.id, payload),
    }
);
const labels = computed(
  () =>
    props.source?.labels || {
      pdfTitle: t('OUTSIDER_ERP.BUDGET.PDF.TITLE'),
      hint: t('OUTSIDER_ERP.BUDGET.SEND.HISTORY_HINT'),
      emailDone: t('OUTSIDER_ERP.BUDGET.SEND.EMAIL_DONE'),
      whatsappDone: t('OUTSIDER_ERP.BUDGET.SEND.WHATSAPP_DONE'),
    }
);

const loadPdf = async () => {
  pdfLoading.value = true;
  pdfFailure.value = '';
  try {
    const response = await api.value.pdf();
    pdfUrl.value = URL.createObjectURL(
      new Blob([response.data], { type: 'application/pdf' })
    );
  } catch (error) {
    pdfFailure.value = budgetErrorMessage(t, await blobError(error));
  } finally {
    pdfLoading.value = false;
  }
};

const loadDelivery = async () => {
  loading.value = true;
  failure.value = '';
  try {
    const { data } = await api.value.delivery();
    delivery.value = data;
    emails.value = [...(data.recipients.emails || [])];
    subject.value = data.texts.subject;
    emailBody.value = data.texts.body;
    whatsappText.value = data.texts.whatsapp;
    contact.value = data.recipients.contact;
    inboxId.value = data.recipients.inbox_id || data.recipients.inboxes[0]?.id;
    const canWhatsapp =
      contact.value?.phone_number && data.recipients.inboxes.length;
    channel.value = canWhatsapp && !emails.value.length ? 'whatsapp' : 'email';
    emit('meta', { status: data.status, total: data.total });
  } catch (error) {
    failure.value = budgetErrorMessage(t, error);
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  loadPdf();
  loadDelivery();
});
onBeforeUnmount(() => pdfUrl.value && URL.revokeObjectURL(pdfUrl.value));

// "a@b.com, c@d.com" colado ou digitado vira um chip por endereço
const addEmails = () => {
  const list = emailDraft.value.split(/[\s,;]+/).filter(Boolean);
  const valid = list.filter(item => EMAIL.test(item));
  const known = emails.value.map(item => item.toLowerCase());
  valid.forEach(item => {
    if (!known.includes(item.toLowerCase())) emails.value.push(item);
  });
  emailDraft.value = list.filter(item => !EMAIL.test(item)).join(' ');
};

const onEmailKey = event => {
  if ([',', ';', ' '].includes(event.key) || event.key === 'Enter') {
    event.preventDefault();
    addEmails();
  } else if (event.key === 'Backspace' && !emailDraft.value) {
    emails.value.pop();
  }
};

const searchContacts = debounce(async () => {
  try {
    const { data } = await api.value.contacts(contactQuery.value);
    contactResults.value = data.contacts || [];
  } catch {
    contactResults.value = [];
  }
}, 300);

const pickContact = row => {
  contact.value = row;
  if (row.default_inbox_id) inboxId.value = row.default_inbox_id;
  searching.value = false;
  contactQuery.value = '';
  contactResults.value = [];
};

const canSend = computed(() => {
  if (channel.value === 'email')
    return (
      delivery.value?.recipients.mail_server &&
      (emails.value.length || EMAIL.test(emailDraft.value.trim())) &&
      subject.value.trim()
    );
  return contact.value?.phone_number && inboxId.value;
});

const send = async () => {
  if (channel.value === 'email') addEmails();
  sending.value = true;
  try {
    const payload =
      channel.value === 'email'
        ? {
            channel: 'email',
            to: emails.value,
            subject: subject.value,
            message: emailBody.value,
          }
        : {
            channel: 'whatsapp',
            contact_id: contact.value.id,
            inbox_id: inboxId.value,
            message: whatsappText.value,
          };
    const { data } = await api.value.deliver(payload);
    useAlert(
      channel.value === 'email'
        ? labels.value.emailDone
        : labels.value.whatsappDone
    );
    emit('sent', data.budget);
  } catch (error) {
    useAlert(budgetErrorMessage(t, error));
  } finally {
    sending.value = false;
  }
};

const sendIcon = row =>
  row.channel === 'email' ? 'i-lucide-mail' : 'i-lucide-message-circle';
const sendStatusClass = status =>
  ({
    delivered: 'text-n-teal-11',
    failed: 'text-n-ruby-11',
  })[status] || 'text-n-slate-10';

const INPUT =
  '!mb-0 w-full h-9 px-2.5 text-sm rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
const LABEL =
  'flex flex-col gap-1 text-[11px] font-medium tracking-wide uppercase text-n-slate-10';
const TEXTAREA =
  '!mb-0 w-full px-2.5 py-2 text-sm normal-case rounded-lg reset-base bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-slate-6 focus:outline-n-brand';
</script>

<template>
  <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:h-full">
    <!-- PDF oficial -->
    <div
      class="relative flex flex-col overflow-hidden border min-h-[24rem] rounded-xl border-n-weak bg-n-alpha-1"
    >
      <div
        v-if="pdfLoading"
        class="absolute inset-0 flex items-center justify-center"
      >
        <Spinner class="text-n-slate-10" />
      </div>
      <p v-else-if="pdfFailure" class="p-4 mb-0 text-sm text-n-ruby-11">
        {{ pdfFailure }}
        <button type="button" class="underline" @click="loadPdf">
          {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
        </button>
      </p>
      <iframe
        v-if="pdfUrl"
        :src="pdfUrl"
        :title="labels.pdfTitle"
        class="flex-1 w-full border-0 min-h-[24rem]"
      />
    </div>

    <!-- envio -->
    <section
      class="flex flex-col gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-1 lg:overflow-y-auto [&>*]:shrink-0"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h4 class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('OUTSIDER_ERP.BUDGET.SEND.TITLE') }}
        </h4>
        <div class="flex gap-1 p-0.5 rounded-lg bg-n-alpha-2">
          <button
            v-for="key in ['whatsapp', 'email']"
            :key="key"
            type="button"
            class="flex items-center gap-1.5 px-3 py-1 text-sm rounded-md"
            :class="
              channel === key
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11'
            "
            @click="channel = key"
          >
            <Icon
              :icon="
                key === 'email' ? 'i-lucide-mail' : 'i-lucide-message-circle'
              "
              class="size-4"
            />
            {{ t(`OUTSIDER_ERP.BUDGET.SEND.${key.toUpperCase()}`) }}
          </button>
        </div>
      </div>

      <div v-if="loading" class="flex justify-center p-4">
        <Spinner class="text-n-slate-10" />
      </div>
      <p v-else-if="failure" class="mb-0 text-sm text-n-ruby-11">
        {{ failure }}
        <button type="button" class="underline" @click="loadDelivery">
          {{ t('OUTSIDER_ERP.CONTACT.RETRY') }}
        </button>
      </p>

      <template v-else-if="channel === 'email'">
        <p
          v-if="!delivery.recipients.mail_server"
          class="p-2 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
        >
          {{ t('OUTSIDER_ERP.BUDGET.SEND.NO_MAIL_SERVER') }}
        </p>
        <div :class="LABEL">
          {{ t('OUTSIDER_ERP.BUDGET.SEND.TO') }}
          <div
            class="flex flex-wrap items-center gap-1.5 p-1.5 rounded-lg bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-slate-6 focus-within:outline-n-brand"
          >
            <span
              v-for="(address, index) in emails"
              :key="address"
              class="inline-flex items-center gap-1 px-2 py-0.5 text-sm normal-case rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{ address }}
              <button
                type="button"
                :aria-label="t('OUTSIDER_ERP.BUDGET.SEND.REMOVE_EMAIL')"
                @click="emails.splice(index, 1)"
              >
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </span>
            <input
              v-model="emailDraft"
              type="text"
              :placeholder="t('OUTSIDER_ERP.BUDGET.SEND.ADD_EMAIL')"
              class="!mb-0 flex-1 min-w-[10rem] h-7 px-1 text-sm normal-case reset-base bg-transparent text-n-slate-12"
              @keydown="onEmailKey"
              @blur="addEmails"
            />
          </div>
          <span class="text-xs font-normal normal-case text-n-slate-10">
            {{ t('OUTSIDER_ERP.BUDGET.SEND.TO_HINT') }}
          </span>
        </div>
        <label :class="LABEL">
          {{ t('OUTSIDER_ERP.BUDGET.SEND.SUBJECT') }}
          <input
            v-model="subject"
            maxlength="200"
            :class="INPUT"
            class="normal-case"
          />
        </label>
        <label :class="LABEL">
          {{ t('OUTSIDER_ERP.BUDGET.SEND.MESSAGE') }}
          <textarea
            v-model="emailBody"
            rows="8"
            maxlength="4000"
            :class="TEXTAREA"
            class="!h-44 resize-y"
          />
        </label>
      </template>

      <template v-else>
        <div :class="LABEL">
          {{ t('OUTSIDER_ERP.BUDGET.SEND.CONTACT') }}
          <div
            class="flex items-center gap-3 px-3 py-2 normal-case rounded-lg bg-n-alpha-1"
          >
            <Icon icon="i-lucide-user" class="size-4 text-n-slate-10" />
            <span class="flex flex-col flex-1 min-w-0">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ contact?.name || t('OUTSIDER_ERP.BUDGET.SEND.NO_CONTACT') }}
              </span>
              <span
                class="text-xs font-normal"
                :class="
                  contact?.phone_number ? 'text-n-slate-10' : 'text-n-ruby-11'
                "
              >
                {{
                  contact?.phone_number ||
                  t('OUTSIDER_ERP.BUDGET.SEND.NO_PHONE')
                }}
              </span>
            </span>
            <button
              type="button"
              class="text-sm font-medium text-n-brand hover:underline"
              @click="searching = !searching"
            >
              {{ t('OUTSIDER_ERP.BUDGET.CUSTOMER.CHANGE') }}
            </button>
          </div>
          <div v-if="searching" class="flex flex-col gap-1 normal-case">
            <input
              v-model="contactQuery"
              :placeholder="t('OUTSIDER_ERP.BUDGET.SEND.SEARCH_CONTACT')"
              :class="INPUT"
              @input="searchContacts"
            />
            <button
              v-for="row in contactResults"
              :key="row.id"
              type="button"
              class="flex flex-col px-2 py-1.5 text-left rounded-lg hover:bg-n-alpha-2 disabled:opacity-50"
              :disabled="!row.phone_number"
              @click="pickContact(row)"
            >
              <span class="text-sm text-n-slate-12">{{ row.name }}</span>
              <span class="text-xs font-normal text-n-slate-10">
                {{ row.phone_number || t('OUTSIDER_ERP.BUDGET.SEND.NO_PHONE') }}
                <template v-if="row.company_name">
                  · {{ row.company_name }}</template
                >
              </span>
            </button>
          </div>
        </div>
        <label :class="LABEL">
          {{ t('OUTSIDER_ERP.BUDGET.SEND.INBOX') }}
          <span
            v-if="!delivery.recipients.inboxes.length"
            class="text-sm font-normal normal-case text-n-ruby-11"
          >
            {{ t('OUTSIDER_ERP.BUDGET.SEND.NO_INBOX') }}
          </span>
          <select
            v-else
            v-model.number="inboxId"
            :class="INPUT"
            class="normal-case !pr-7 bg-[right_-1.25rem_center]"
          >
            <option
              v-for="inbox in delivery.recipients.inboxes"
              :key="inbox.id"
              :value="inbox.id"
            >
              {{ inbox.name }}
            </option>
          </select>
        </label>
        <label :class="LABEL">
          {{ t('OUTSIDER_ERP.BUDGET.SEND.MESSAGE') }}
          <textarea
            v-model="whatsappText"
            rows="4"
            maxlength="4000"
            :class="TEXTAREA"
            class="!h-32 resize-y"
          />
        </label>
      </template>

      <div
        v-if="delivery"
        class="flex items-center gap-2 px-3 py-2 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12"
      >
        <Icon icon="i-lucide-paperclip" class="size-4 text-n-slate-10" />
        <span class="truncate">{{ delivery.filename }}</span>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2 mt-auto">
        <span class="text-xs text-n-slate-10">
          {{ labels.hint }}
        </span>
        <Button
          :label="
            t(
              channel === 'email'
                ? 'OUTSIDER_ERP.BUDGET.SEND.SEND_EMAIL'
                : 'OUTSIDER_ERP.BUDGET.SEND.SEND_WHATSAPP'
            )
          "
          :icon="
            channel === 'email' ? 'i-lucide-send' : 'i-lucide-message-circle'
          "
          :is-loading="sending"
          :disabled="loading || !canSend"
          @click="send"
        />
      </div>

      <div
        v-if="budget?.sends?.length"
        class="flex flex-col gap-1.5 pt-3 border-t border-n-weak"
      >
        <span
          class="text-xs font-medium tracking-wide uppercase text-n-slate-10"
        >
          {{ t('OUTSIDER_ERP.BUDGET.SEND.HISTORY') }}
        </span>
        <div
          v-for="row in budget.sends"
          :key="row.id"
          class="flex items-start gap-2 text-xs text-n-slate-11"
        >
          <Icon :icon="sendIcon(row)" class="mt-0.5 size-3.5 shrink-0" />
          <span class="flex-1 min-w-0 break-words">
            {{ row.recipients.join(', ') }}
            <span class="text-n-slate-10">
              · {{ formatDate(row.created_at) }} · {{ row.user }}
            </span>
            <span v-if="row.error" class="block text-n-ruby-11">{{
              row.error
            }}</span>
          </span>
          <span :class="sendStatusClass(row.status)">
            {{
              t(`OUTSIDER_ERP.BUDGET.SEND.STATUS.${row.status.toUpperCase()}`)
            }}
          </span>
        </div>
      </div>
    </section>
  </div>
</template>
