<script setup>
// OUTSIDER: papel timbrado do modelo: cabeçalho e rodapé (imagens na largura da folha, enviadas na hora),
// em quais páginas cada um entra, margens do conteúdo e os elementos soltos (texto ou imagem) que o
// administrador arrasta para qualquer lugar da folha. A imagem de um elemento sobe na hora e fica guardada
// uma vez só; o elemento passa a valer quando o modelo é salvo.
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TemplateImageSlot from './TemplateImageSlot.vue';
import LetterheadCanvas from './LetterheadCanvas.vue';
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
});

const emit = defineEmits(['updated']);

const layout = defineModel('layout', { type: Object, required: true });

const { t } = useI18n();

const TYPES = ['image/png', 'image/jpeg'];
const selectedId = ref(null);
const page = ref('first');
const fileRef = ref(null);
const replacing = ref(false);
const isUploading = ref(false);
const uploaded = ref({});
const defaults = ref({ header: '', footer: '' });
const ratios = ref({ header: 0, footer: 0 });

const usesDefault = computed(
  () => !!props.template.content?.default_letterhead
);

// imagem do modelo; sem ela, o modelo padrão usa a que vem com o CRM
const slotUrl = slot =>
  props.template[`${slot}_image_url`] ||
  (usesDefault.value ? defaults.value[slot] : '');
const headerUrl = computed(() => slotUrl('header'));
const footerUrl = computed(() => slotUrl('footer'));

const loadDefault = async slot => {
  if (defaults.value[slot]) return;
  try {
    const { data } = await CrmAPI.getProposalTemplateDefaultImage(slot);
    defaults.value = { ...defaults.value, [slot]: URL.createObjectURL(data) };
  } catch {
    // sem a imagem padrão, a folha mostra só as margens; a prévia em PDF continua certa
  }
};

watch(
  () => [
    usesDefault.value,
    props.template.header_image_url,
    props.template.footer_image_url,
  ],
  () => {
    ['header', 'footer'].forEach(slot => {
      if (usesDefault.value && !props.template[`${slot}_image_url`]) {
        loadDefault(slot);
      }
    });
  },
  { immediate: true }
);

// altura do cabeçalho e do rodapé na folha, pela proporção da imagem
watch(
  () => [headerUrl.value, footerUrl.value],
  ([header, footer]) => {
    [
      ['header', header],
      ['footer', footer],
    ].forEach(([slot, url]) => {
      if (!url) {
        ratios.value = { ...ratios.value, [slot]: 0 };
        return;
      }
      const image = new Image();
      image.onload = () => {
        if (image.naturalWidth) {
          ratios.value = {
            ...ratios.value,
            [slot]: image.naturalHeight / image.naturalWidth,
          };
        }
      };
      image.src = url;
    });
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  Object.values(defaults.value).forEach(url => url && URL.revokeObjectURL(url));
});

const imageUrls = computed(() => ({
  ...Object.fromEntries(
    (props.template.layout_images || []).map(image => [image.id, image.url])
  ),
  ...uploaded.value,
}));

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
  page.value = 'first';
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
    uploaded.value = { ...uploaded.value, [data.id]: data.url };
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
    <div class="grid gap-4 sm:grid-cols-2">
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
      <div class="flex flex-wrap items-start gap-4">
        <div class="flex flex-col items-center gap-2">
          <div
            class="flex p-0.5 text-xs rounded-lg bg-n-alpha-1"
            role="tablist"
          >
            <button
              v-for="value in ['first', 'next']"
              :key="value"
              type="button"
              class="px-2.5 py-1 rounded-md"
              :class="
                page === value
                  ? 'bg-n-solid-3 text-n-slate-12 font-medium shadow-sm'
                  : 'text-n-slate-11'
              "
              @click="page = value"
            >
              {{
                t(
                  `OUTSIDER_CRM.PROPOSAL_SETTINGS.LETTERHEAD.PAGE_VIEW.${value.toUpperCase()}`
                )
              }}
            </button>
          </div>
          <LetterheadCanvas
            v-model:layout="layout"
            v-model:selected="selectedId"
            :header-url="headerUrl"
            :footer-url="footerUrl"
            :header-ratio="ratios.header"
            :footer-ratio="ratios.footer"
            :image-urls="imageUrls"
            :page="page"
          />
        </div>
        <div class="flex-1 min-w-[14rem]">
          <LetterheadElementPanel
            v-if="selected"
            :key="selected.id"
            :element="selected"
            :image-url="imageUrls[selected.image_id] || ''"
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
