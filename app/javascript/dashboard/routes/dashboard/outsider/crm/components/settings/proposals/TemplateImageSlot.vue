<script setup>
// OUTSIDER: cabeçalho ou rodapé (papel timbrado) de um modelo. Envia na hora; sem imagem própria, o
// modelo padrão usa o papel timbrado que vem com o CRM.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { settingsError } from './proposalSettings';

const props = defineProps({
  template: { type: Object, required: true },
  position: {
    type: String,
    required: true,
    validator: value => ['header', 'footer'].includes(value),
  },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();

const TYPES = ['image/png', 'image/jpeg'];
const fileRef = ref(null);
const isBusy = ref(false);

const imageUrl = computed(() => props.template[`${props.position}_image_url`]);
const usesDefault = computed(
  () => !!props.template.content?.default_letterhead
);

const run = async request => {
  isBusy.value = true;
  try {
    const { data } = await request();
    emit('updated', data);
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isBusy.value = false;
  }
};

const choose = () => fileRef.value?.click();

const onFile = event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (!file) return;
  if (!TYPES.includes(file.type)) {
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE_INVALID'));
    return;
  }
  run(() =>
    CrmAPI.uploadProposalTemplateImage(props.template.id, props.position, file)
  );
};

const remove = () =>
  run(() =>
    CrmAPI.removeProposalTemplateImage(props.template.id, props.position)
  );
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{
        t(
          `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE.${position.toUpperCase()}`
        )
      }}
    </span>
    <div
      class="flex items-center justify-center p-2 overflow-hidden rounded-lg min-h-[5rem] bg-n-alpha-black2 outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <img
        v-if="imageUrl"
        :src="imageUrl"
        :alt="
          t(
            `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE.${position.toUpperCase()}`
          )
        "
        class="object-contain w-full max-h-32"
      />
      <span
        v-else
        class="flex items-center gap-1.5 text-xs text-center text-n-slate-11"
      >
        <Icon icon="i-lucide-image" class="size-4 shrink-0" />
        {{
          usesDefault
            ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE.DEFAULT')
            : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE.NONE')
        }}
      </span>
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <Button
        size="xs"
        variant="faded"
        color="slate"
        icon="i-lucide-upload"
        :label="
          imageUrl
            ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE.REPLACE')
            : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE.UPLOAD')
        "
        :is-loading="isBusy"
        @click="choose"
      />
      <Button
        v-if="imageUrl"
        size="xs"
        variant="ghost"
        color="ruby"
        icon="i-lucide-trash-2"
        :label="
          usesDefault
            ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE.RESTORE')
            : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE.REMOVE')
        "
        :disabled="isBusy"
        @click="remove"
      />
      <input
        ref="fileRef"
        type="file"
        accept="image/png,image/jpeg"
        class="hidden"
        @change="onFile"
      />
    </div>
  </div>
</template>
