<script setup>
// OUTSIDER: estúdio de um modelo de relatório (OS ou orçamento) em tela cheia. Em cima: voltar, o nome, de onde vêm os
// dados da folha (exemplo ou uma OS/orçamento de verdade, só leitura), "Pré-visualizar PDF" e "Salvar". Na esquerda:
// Blocos (arrastar ou clicar), Campos (quais e em que ordem) e Identidade (cores, fontes, margens). No centro, a folha A4
// como vai sair; clicar num bloco abre os ajustes dele na direita. Sair com alteração não salva pede confirmação.
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import ErpPdfDialog from '../budgets/ErpPdfDialog.vue';
import PrintSheet from './PrintSheet.vue';
import PrintPalette from './PrintPalette.vue';
import PrintBlockSettings from './PrintBlockSettings.vue';
import PrintFields from './PrintFields.vue';
import PrintTheme from './PrintTheme.vue';
import {
  MAX_BLOCKS,
  duplicateBlock,
  editableContent,
  sameContent,
} from './printsHelpers';
import { erpState, companyName, erpErrorMessage } from '../erpStore';

const props = defineProps({
  template: { type: Object, required: true },
  catalog: { type: Object, required: true },
});

const emit = defineEmits(['saved', 'close']);

const { t } = useI18n();

const name = ref(props.template.name);
const content = ref(editableContent(props.template));
const original = ref(editableContent(props.template));
const images = ref({ ...(props.template.images || {}) });
const selectedId = ref(null);
const lastId = ref(null);
const tab = ref('blocks');
const fieldsFocus = ref('');
const zoom = ref(1);
const isSaving = ref(false);
const isUploading = ref(false);
const leaveRef = ref(null);
const pdfRef = ref(null);

const kind = computed(() => props.template.kind);
const isDirty = computed(
  () =>
    name.value.trim() !== props.template.name ||
    !sameContent(content.value, original.value)
);

// ---------- dados da folha ----------

const source = ref('sample');
const realCompany = ref(erpState.companies[0] || '');
const realNumber = ref('');
const values = ref(null);
const isLoadingValues = ref(false);
const photos = ref({});

const releasePhotos = () => {
  Object.values(photos.value).forEach(url => URL.revokeObjectURL(url));
  photos.value = {};
};

const real = computed(() =>
  source.value === 'real' && realNumber.value
    ? { company: realCompany.value, number: realNumber.value }
    : {}
);

// fotos de uma OS de verdade: uma a uma (poucas por vez), só as desta OS
const loadPhotos = async (data, target) => {
  const refs = (data.checklist || []).flatMap(section =>
    (section.itens || []).flatMap(item =>
      (item.fotos || []).map(photo => photo?.ref).filter(Boolean)
    )
  );
  const queue = [...new Set(refs)];
  const worker = async () => {
    while (queue.length) {
      const photoRef = queue.shift();
      try {
        // eslint-disable-next-line no-await-in-loop
        const { data: blob } = await ErpAPI.printPhoto(
          target.company,
          target.number,
          photoRef
        );
        if (values.value !== data) return;
        photos.value = {
          ...photos.value,
          [photoRef]: URL.createObjectURL(blob),
        };
      } catch {
        // foto que não veio fica de fora, como no PDF
      }
    }
  };
  await Promise.all([worker(), worker(), worker()]);
};

const loadValues = async () => {
  isLoadingValues.value = true;
  releasePhotos();
  const target = { ...real.value };
  try {
    const { data } = await ErpAPI.printSample(kind.value, target);
    values.value = data.values;
    if (target.number) loadPhotos(data.values, target);
  } catch (error) {
    useAlert(
      error?.response?.status === 404
        ? t(`OUTSIDER_ERP.PRINTS.STUDIO.NOT_FOUND_${kind.value.toUpperCase()}`)
        : erpErrorMessage(t, error)
    );
    if (target.number) {
      source.value = 'sample';
      realNumber.value = '';
      loadValues();
    }
  } finally {
    isLoadingValues.value = false;
  }
};
loadValues();

const useSample = () => {
  source.value = 'sample';
  realNumber.value = '';
  loadValues();
};

const useReal = () => {
  if (!realNumber.value) return;
  source.value = 'real';
  loadValues();
};

onBeforeUnmount(releasePhotos);

// ---------- blocos ----------

const blocks = computed({
  get: () => content.value.blocks || [],
  set: list => {
    content.value = { ...content.value, blocks: list };
  },
});

watch(selectedId, id => {
  if (id) lastId.value = id;
});

const selectedBlock = computed({
  get: () => blocks.value.find(block => block.id === selectedId.value),
  set: block => {
    blocks.value = blocks.value.map(item =>
      item.id === block.id ? block : item
    );
  },
});

const addBlock = block => {
  if (blocks.value.length >= MAX_BLOCKS) return;
  const list = [...blocks.value];
  const after = list.findIndex(item => item.id === lastId.value);
  list.splice(after === -1 ? list.length : after + 1, 0, block);
  blocks.value = list;
  selectedId.value = block.id;
};

const moveBlock = (id, step) => {
  const list = [...blocks.value];
  const index = list.findIndex(item => item.id === id);
  const target = index + step;
  if (index === -1 || target < 0 || target >= list.length) return;
  [list[index], list[target]] = [list[target], list[index]];
  blocks.value = list;
};

const duplicate = id => {
  const block = blocks.value.find(item => item.id === id);
  if (!block || blocks.value.length >= MAX_BLOCKS) return;
  const copy = duplicateBlock(block);
  const list = [...blocks.value];
  list.splice(list.indexOf(block) + 1, 0, copy);
  blocks.value = list;
  selectedId.value = copy.id;
};

const remove = id => {
  blocks.value = blocks.value.filter(item => item.id !== id);
  if (selectedId.value === id) selectedId.value = null;
};

const openFields = list => {
  fieldsFocus.value = '';
  tab.value = 'fields';
  setTimeout(() => {
    fieldsFocus.value = list;
  });
};

const fields = computed({
  get: () => content.value.fields || {},
  set: value => {
    content.value = { ...content.value, fields: value };
  },
});

const theme = computed({
  get: () => content.value.theme || {},
  set: value => {
    content.value = { ...content.value, theme: value };
  },
});

// imagem do modelo (logo próprio, imagem solta): sobe na hora e o bloco guarda o id
const upload = async (file, done) => {
  isUploading.value = true;
  try {
    const { data } = await ErpAPI.uploadPrintImage(props.template.id, file);
    images.value = { ...images.value, [data.id]: data.url };
    done(data.id);
  } catch (error) {
    useAlert(
      error?.response?.data?.error === 'invalid_image'
        ? t('OUTSIDER_ERP.PRINTS.STUDIO.INVALID_IMAGE')
        : erpErrorMessage(t, error)
    );
  } finally {
    isUploading.value = false;
  }
};

// ---------- salvar, pré-visualizar, sair ----------

const save = async () => {
  if (!name.value.trim()) {
    useAlert(t('OUTSIDER_ERP.PRINTS.STUDIO.NAME_REQUIRED'));
    return;
  }
  isSaving.value = true;
  try {
    const { data } = await ErpAPI.savePrintTemplate(props.template.id, {
      name: name.value.trim(),
      content: content.value,
    });
    original.value = editableContent(data.template);
    content.value = editableContent(data.template);
    images.value = { ...(data.template.images || {}) };
    emit('saved', data.template);
    useAlert(t('OUTSIDER_ERP.PRINTS.STUDIO.SAVED'));
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

const preview = () =>
  pdfRef.value?.open(() =>
    ErpAPI.printPreview(props.template.id, content.value, real.value)
  );

const close = () => {
  if (isDirty.value) {
    leaveRef.value?.open();
    return;
  }
  emit('close');
};

const leave = () => {
  leaveRef.value?.close();
  emit('close');
};

const ZOOMS = [0.6, 0.75, 0.9, 1, 1.15, 1.3, 1.5];
const changeZoom = step => {
  const next = ZOOMS[ZOOMS.indexOf(zoom.value) + step];
  if (next) zoom.value = next;
};

const TABS = [
  { key: 'blocks', icon: 'i-lucide-blocks' },
  { key: 'fields', icon: 'i-lucide-list-checks' },
  { key: 'theme', icon: 'i-lucide-palette' },
];
const INPUT =
  'px-2.5 py-1.5 text-sm rounded-lg bg-n-alpha-black2 outline outline-1 outline-n-weak focus:outline-n-brand text-n-slate-12';
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      class="fixed inset-0 z-50 flex flex-col bg-n-surface-1"
      data-print-studio
    >
      <header
        class="flex flex-wrap items-center gap-3 px-4 py-2.5 border-b border-n-weak shrink-0"
      >
        <Button
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-arrow-left"
          :label="t('OUTSIDER_ERP.PRINTS.STUDIO.BACK')"
          @click="close"
        />
        <input
          v-model="name"
          type="text"
          maxlength="120"
          class="reset-base min-w-0 px-2 py-1 text-base font-semibold bg-transparent rounded-md w-72 text-n-slate-12 hover:bg-n-alpha-2 focus:bg-n-alpha-2 focus:outline-none"
        />
        <span
          class="px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
        >
          {{ t(`OUTSIDER_ERP.PRINTS.KINDS.${kind.toUpperCase()}`) }}
        </span>
        <span
          v-if="isDirty"
          class="px-2 py-0.5 text-xs rounded-full bg-n-amber-3 text-n-amber-11"
        >
          {{ t('OUTSIDER_ERP.PRINTS.STUDIO.UNSAVED') }}
        </span>
        <div class="flex flex-wrap items-center gap-2 ml-auto">
          <div class="flex items-center p-0.5 rounded-lg bg-n-alpha-2">
            <button
              type="button"
              class="h-7 px-2.5 text-xs rounded-md"
              :class="
                source === 'sample'
                  ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                  : 'text-n-slate-11'
              "
              @click="useSample"
            >
              {{ t('OUTSIDER_ERP.PRINTS.STUDIO.SAMPLE') }}
            </button>
            <button
              type="button"
              class="h-7 px-2.5 text-xs rounded-md"
              :class="
                source === 'real'
                  ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                  : 'text-n-slate-11'
              "
              @click="source = 'real'"
            >
              {{ t(`OUTSIDER_ERP.PRINTS.STUDIO.REAL_${kind.toUpperCase()}`) }}
            </button>
          </div>
          <form
            v-if="source === 'real'"
            class="flex items-center gap-1.5"
            @submit.prevent="useReal"
          >
            <select
              v-model="realCompany"
              :class="INPUT"
              class="max-w-[11rem] !mb-0 !pr-8 bg-[right_-1.25rem_center]"
            >
              <option
                v-for="company in erpState.companies"
                :key="company"
                :value="company"
              >
                {{ companyName(company) }}
              </option>
            </select>
            <input
              v-model.trim="realNumber"
              type="text"
              inputmode="numeric"
              :placeholder="t('OUTSIDER_ERP.PRINTS.STUDIO.NUMBER')"
              :class="INPUT"
              class="w-24 reset-base"
            />
            <Button
              size="sm"
              variant="faded"
              color="slate"
              type="submit"
              :is-loading="isLoadingValues"
              :label="t('OUTSIDER_ERP.PRINTS.STUDIO.LOAD')"
            />
          </form>
          <Button
            size="sm"
            variant="faded"
            color="slate"
            icon="i-lucide-file-search"
            :label="t('OUTSIDER_ERP.PRINTS.STUDIO.PREVIEW')"
            @click="preview"
          />
          <Button
            size="sm"
            color="teal"
            icon="i-lucide-save"
            :is-loading="isSaving"
            :disabled="!isDirty"
            :label="t('OUTSIDER_ERP.PRINTS.STUDIO.SAVE')"
            @click="save"
          />
        </div>
      </header>

      <div class="flex flex-1 min-h-0">
        <aside class="flex flex-col border-r w-80 shrink-0 border-n-weak">
          <nav class="flex gap-0.5 p-2 border-b border-n-weak">
            <button
              v-for="item in TABS"
              :key="item.key"
              type="button"
              class="flex items-center justify-center flex-1 gap-1.5 h-8 text-[13px] rounded-md"
              :class="
                tab === item.key
                  ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="tab = item.key"
            >
              <span :class="item.icon" class="size-4" />
              {{
                t(`OUTSIDER_ERP.PRINTS.STUDIO.TABS.${item.key.toUpperCase()}`)
              }}
            </button>
          </nav>
          <div class="flex-1 p-3 overflow-y-auto">
            <PrintPalette
              v-if="tab === 'blocks'"
              :catalog="catalog"
              :blocks="blocks"
              @add="addBlock"
            />
            <PrintFields
              v-else-if="tab === 'fields'"
              v-model:fields="fields"
              :catalog="catalog"
              :focus="fieldsFocus"
            />
            <PrintTheme v-else v-model:theme="theme" />
          </div>
        </aside>

        <main class="relative flex-1 min-w-0 overflow-auto bg-n-alpha-2">
          <div
            v-if="isLoadingValues && !values"
            class="flex items-center justify-center h-full"
          >
            <Spinner />
          </div>
          <div v-else class="px-8 pt-10 pb-24">
            <PrintSheet
              v-model:blocks="blocks"
              v-model:selected-id="selectedId"
              :content="content"
              :catalog="catalog"
              :values="values"
              :images="images"
              :photos="photos"
              :zoom="zoom"
              @move="moveBlock"
              @duplicate="duplicate"
              @remove="remove"
              @added="id => (selectedId = id)"
            />
          </div>
          <div
            class="sticky flex items-center gap-1 p-1 ml-auto mr-4 rounded-lg shadow bottom-4 w-fit bg-n-solid-1"
          >
            <Button
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-zoom-out"
              @click="changeZoom(-1)"
            />
            <span class="w-10 text-xs text-center tabular-nums text-n-slate-11">
              {{ Math.round(zoom * 100) }}%
            </span>
            <Button
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-zoom-in"
              @click="changeZoom(1)"
            />
          </div>
        </main>

        <aside class="p-4 overflow-y-auto border-l w-80 shrink-0 border-n-weak">
          <PrintBlockSettings
            v-if="selectedBlock"
            v-model:block="selectedBlock"
            :catalog="catalog"
            :values="values"
            :images="images"
            :uploading="isUploading"
            @upload="upload"
            @fields="openFields"
            @close="selectedId = null"
          />
          <div
            v-else
            class="flex flex-col items-center gap-2 p-6 mt-10 text-sm text-center text-n-slate-10"
          >
            <span class="i-lucide-mouse-pointer-click size-7" />
            {{ t('OUTSIDER_ERP.PRINTS.STUDIO.SELECT_HINT') }}
          </div>
        </aside>
      </div>

      <ErpPdfDialog ref="pdfRef" />
      <Dialog
        ref="leaveRef"
        type="alert"
        :title="t('OUTSIDER_ERP.PRINTS.STUDIO.LEAVE_TITLE')"
        :description="t('OUTSIDER_ERP.PRINTS.STUDIO.LEAVE_TEXT')"
        :confirm-button-label="t('OUTSIDER_ERP.PRINTS.STUDIO.LEAVE')"
        @confirm="leave"
      />
    </div>
  </TeleportWithDirection>
</template>
