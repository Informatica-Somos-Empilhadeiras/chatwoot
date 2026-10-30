<script setup>
// OUTSIDER: "Adicionar novo contato" da busca. Já vem preenchido com o que foi buscado (telefone,
// e-mail ou nome). O telefone aceita qualquer formato: sem "+", entra o +55 do Brasil.
import { reactive, ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { DuplicateContactException } from 'shared/helpers/CustomErrors';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const emit = defineEmits(['created']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const isSaving = ref(false);
const errorMessage = ref('');
const form = reactive({ name: '', phone: '', email: '', company: '' });

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// "(62) 99999-0000" -> "+5562999990000"; "+1 415..." fica como está
const normalizePhone = value => {
  const raw = String(value || '').trim();
  const digits = raw.replace(/\D/g, '');
  if (!digits) return '';
  if (raw.startsWith('+')) return `+${digits}`;
  if (digits.startsWith('55') && digits.length >= 12) return `+${digits}`;
  return `+55${digits.replace(/^0+/, '')}`;
};

const phoneValue = computed(() => normalizePhone(form.phone));
const phoneInvalid = computed(
  () => !!form.phone && !/^\+\d{10,15}$/.test(phoneValue.value)
);
const emailInvalid = computed(
  () => !!form.email && !EMAIL.test(form.email.trim())
);
const canSave = computed(
  () =>
    !!(form.name.trim() || phoneValue.value || form.email.trim()) &&
    !phoneInvalid.value &&
    !emailInvalid.value
);

const open = query => {
  const text = String(query || '').trim();
  const digits = text.replace(/\D/g, '');
  Object.assign(form, { name: '', phone: '', email: '', company: '' });
  errorMessage.value = '';
  if (text.includes('@')) form.email = text;
  else if (
    digits.length >= 8 &&
    digits.length >= text.replace(/\s/g, '').length - 4
  ) {
    form.phone = text;
  } else form.name = text;
  dialogRef.value?.open();
};

const save = async () => {
  if (!canSave.value || isSaving.value) return;
  isSaving.value = true;
  errorMessage.value = '';
  try {
    const contact = await store.dispatch('contacts/create', {
      name: form.name.trim() || phoneValue.value || form.email.trim(),
      phone_number: phoneValue.value || undefined,
      email: form.email.trim() || undefined,
      additional_attributes: form.company.trim()
        ? { company_name: form.company.trim() }
        : {},
    });
    dialogRef.value?.close();
    useAlert(t('OUTSIDER_TOOLS.NEW_CONTACT.CREATED', { name: contact.name }));
    emit('created', contact);
  } catch (error) {
    errorMessage.value =
      error instanceof DuplicateContactException
        ? t('OUTSIDER_TOOLS.NEW_CONTACT.DUPLICATE')
        : error?.message || t('OUTSIDER_TOOLS.NEW_CONTACT.ERROR');
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_TOOLS.NEW_CONTACT.TITLE')"
    :description="t('OUTSIDER_TOOLS.NEW_CONTACT.DESCRIPTION')"
    :confirm-button-label="t('OUTSIDER_TOOLS.NEW_CONTACT.SAVE')"
    :disable-confirm-button="!canSave"
    :is-loading="isSaving"
    width="md"
    @confirm="save"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('OUTSIDER_TOOLS.NEW_CONTACT.NAME')"
        :placeholder="t('OUTSIDER_TOOLS.NEW_CONTACT.NAME_PLACEHOLDER')"
        autofocus
      />
      <Input
        v-model="form.phone"
        type="tel"
        :label="t('OUTSIDER_TOOLS.NEW_CONTACT.PHONE')"
        :placeholder="t('OUTSIDER_TOOLS.NEW_CONTACT.PHONE_PLACEHOLDER')"
        :message="
          phoneInvalid
            ? t('OUTSIDER_TOOLS.NEW_CONTACT.PHONE_INVALID')
            : phoneValue
              ? t('OUTSIDER_TOOLS.NEW_CONTACT.PHONE_SAVED_AS', {
                  phone: phoneValue,
                })
              : t('OUTSIDER_TOOLS.NEW_CONTACT.PHONE_HINT')
        "
        :message-type="phoneInvalid ? 'error' : 'info'"
      />
      <Input
        v-model="form.email"
        type="email"
        :label="t('OUTSIDER_TOOLS.NEW_CONTACT.EMAIL')"
        placeholder="nome@empresa.com.br"
        :message="
          emailInvalid ? t('OUTSIDER_TOOLS.NEW_CONTACT.EMAIL_INVALID') : ''
        "
        :message-type="emailInvalid ? 'error' : 'info'"
      />
      <Input
        v-model="form.company"
        :label="t('OUTSIDER_TOOLS.NEW_CONTACT.COMPANY')"
        :placeholder="t('OUTSIDER_TOOLS.NEW_CONTACT.COMPANY_PLACEHOLDER')"
      />
      <p v-if="errorMessage" class="text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>
    </div>
  </Dialog>
</template>
