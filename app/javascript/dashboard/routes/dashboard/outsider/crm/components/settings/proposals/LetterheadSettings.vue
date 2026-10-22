<script setup>
// OUTSIDER: papel timbrado do modelo, na esquerda do editor (Entregas 16 e 17): cabeçalho e rodapé
// (imagens na largura da folha, enviadas na hora), em quais páginas cada um entra, margens do conteúdo e os
// elementos soltos (texto ou imagem), que se arrastam direto na folha do centro. A imagem de um elemento
// sobe na hora e fica guardada uma vez só; o elemento passa a valer quando o modelo é salvo.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TemplateImageSlot from './TemplateImageSlot.vue';
import LetterheadElementPanel from './LetterheadElementPanel.vue';
import { settingsError } from './proposalSettings';
import {
  MARGIN_RANGE,
  MAX_ELEMENTS,
  clamp,
  newElement,
  round1,
} from './templateDesign';

const props = defineProps({
  template: { type: Object, required: true },
  images: { type: Object, required: true },
});

const emit = defineEmits(['updated']);

const layout = defineModel('layout', { type: Object, required: true });
const selectedId = defineModel('selected', { type: String, default: null });

const { t } = useI18n();

const TYPES = ['image/png', 'image/jpeg'];
const fileRef = ref(null);
const replacing = ref(false);
const isUploading = ref(false);

const selected = computed(() =>
  layout.value.elements.find(element => element.id === selectedId.value)
);

const pageOptions = computed(() =>
  ['all', 'first'].map(value => ({
    value,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.PAGES.${value.toUpperCase()}`
    ),
  }))
);

const canAdd = computed(() => layout.value.elements.length < MAX_ELEMENTS);

const addElement = element => {
  layout.value.elements = [...layout.value.elements, element];
  selectedId.value = element.id;
};

const addText = () => {
  if (!canAdd.value) return;
  addElement(
    newElement('text', {
      text: t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.NEW_TEXT'),
    })
  );
};

const chooseImage = replace => {
  replacing.value = replace;
  fileRef.value?.click();
};

const onFile = async event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (!file) return;
  if (!TYPES.includes(file.type)) {
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE_INVALID'));
    return;
  }
  isUploading.value = true;
  try {
    const { data } = await CrmAPI.uploadProposalTemplateLayoutImage(
      props.template.id,
      file
    );
    props.images.remember(data.id, data.url);
    if (replacing.value && selected.value) {
      selected.value.image_id = data.id;
    } else if (canAdd.value) {
      addElement(newElement('image', { image_id: data.id }));
    }
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isUploading.value = false;
  }
};

const removeSelected = () => {
  layout.value.elements = layout.value.elements.filter(
    element => element.id !== selectedId.value
  );
  selectedId.value = null;
};

const setMargin = (key, value) => {
  if (value === '' || Number.isNaN(Number(value))) return;
  layout.value.margins = {
    ...layout.value.margins,
    [key]: round1(clamp(value, MARGIN_RANGE.min, MARGIN_RANGE.max)),
  };
};

const fieldClass =
  '!mb-0 w-full px-2.5 py-1.5 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand';
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.ELEMENTS') }}
        </span>
        <div class="flex flex-wrap items-center gap-2">
          <Button
            type="button"
            size="xs"
            variant="faded"
            color="slate"
            icon="i-lucide-type"
            :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.ADD_TEXT')"
            :disabled="!canAdd"
            @click="addText"
          />
          <Button
            type="button"
            size="xs"
            variant="faded"
            color="slate"
            icon="i-lucide-image-plus"
            :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.ADD_IMAGE')"
            :disabled="!canAdd"
            :is-loading="isUploading && !replacing"
            @click="chooseImage(false)"
          />
        </div>
      </div>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.ELEMENTS_HELP') }}
      </p>
      <div>
          <LetterheadElementPanel
            v-if="selected"
            :key="selected.id"
            :element="selected"
            :image-url="images.imageUrls[selected.image_id] || ''"
            :is-uploading="isUploading && replacing"
            @remove="removeSelected"
            @replace-image="chooseImage(true)"
          />
          <p
            v-else
            class="p-3 mb-0 text-xs rounded-lg text-n-slate-11 bg-n-alpha-1"
          >
            {{
              layout.elements.length
                ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.PICK')
                : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.NONE')
            }}
          </p>
      </div>
    </div>
    <div class="grid gap-4 pt-4 border-t border-n-weak">
      <div class="flex flex-col gap-2">
        <TemplateImageSlot
          :template="template"
          position="header"
          @updated="data => emit('updated', data)"
        />
        <label
          class="flex items-center gap-2 text-xs text-n-slate-11 whitespace-nowrap"
        >
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.SHOW_ON') }}
          <Select v-model="layout.header_pages" :options="pageOptions" />
        </label>
      </div>
      <div class="flex flex-col gap-2">
        <TemplateImageSlot
          :template="template"
          position="footer"
          @updated="data => emit('updated', data)"
        />
        <label
          class="flex items-center gap-2 text-xs text-n-slate-11 whitespace-nowrap"
        >
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.SHOW_ON') }}
          <Select v-model="layout.footer_pages" :options="pageOptions" />
        </label>
      </div>
    </div>
    <p class="mb-0 -mt-2 text-xs text-n-slate-11">
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.LETTERHEAD_HELP') }}
    </p>

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.MARGINS') }}
      </span>
      <div class="grid grid-cols-3 gap-2 max-w-md">
        <label
          v-for="key in ['side', 'top', 'bottom']"
          :key="key"
          class="flex flex-col gap-1 text-xs text-n-slate-11"
        >
          {{
            t(
              `OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.MARGIN.${key.toUpperCase()}`
            )
          }}
          <input
            :value="layout.margins[key]"
            type="number"
            step="any"
            :min="MARGIN_RANGE.min"
            :max="MARGIN_RANGE.max"
            :class="fieldClass"
            @change="setMargin(key, $event.target.value)"
          />
        </label>
      </div>
      <span class="text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.MARGINS_HELP') }}
      </span>
    </div>

      <input
        ref="fileRef"
        type="file"
        accept="image/png,image/jpeg"
        class="hidden"
        @change="onFile"
      />
  </div>
</template>
