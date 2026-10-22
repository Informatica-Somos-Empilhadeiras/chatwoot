<script setup>
// OUTSIDER: editor de um modelo de proposta em tela cheia, no estilo da Brevo (Entrega 17; antes, Entrega
// 16 em formulário). Em cima, voltar, o nome (editável ali mesmo), a situação, "Pré-visualizar PDF" e
// "Salvar". Na esquerda: Blocos (arrastar ou clicar para pôr na folha; com um bloco selecionado, os ajustes
// dele), Papel timbrado (cabeçalho, rodapé, margens e elementos soltos) e Configurações (fonte, validade,
// ativo). No centro, as folhas A4 com o conteúdo como vai sair. Salvar manda só as chaves do conteúdo que
// mudaram (o servidor junta com o resto). Sair com alteração não salva pede confirmação.
import { ref, computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useElementSize } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import FieldChips from './FieldChips.vue';
import BlockPalette from './BlockPalette.vue';
import BlockSettings from './BlockSettings.vue';
import LetterheadSettings from './LetterheadSettings.vue';
import ProposalCanvas from './ProposalCanvas.vue';
import TemplatePreview from './TemplatePreview.vue';
import { FLAG_KEYS, TEXT_KEYS, settingsError } from './proposalSettings';
import {
  FLAG_OF_BLOCK,
  FONTS,
  MAX_BLOCKS,
  contentOf,
  duplicateBlock,
  fontCss,
} from './templateDesign';
import { useTemplateImages } from './useTemplateImages';

const props = defineProps({
  template: { type: Object, required: true },
});

const emit = defineEmits(['updated', 'close']);

const { t } = useI18n();

const CONTENT_KEYS = [
  ...TEXT_KEYS,
  ...FLAG_KEYS,
  'validity_days',
  'conditions_style',
  'conditions',
  'blocks',
  'layout',
];
const IMAGE_TYPES = ['image/png', 'image/jpeg'];

const name = ref('');
const active = ref(true);
const form = ref({});
const tab = ref('blocks');
const selectedKey = ref(null);
// último bloco clicado: o bloco novo da lista entra depois dele, mesmo depois de voltar para a lista
const lastKey = ref(null);
const selectedElement = ref(null);
const showPreview = ref(false);
const isSaving = ref(false);
const uploadingKey = ref(null);
const fileRef = ref(null);
const leaveRef = ref(null);
const canvasArea = ref(null);
let imageTarget = null;

// reactive: os endereços e proporções chegam aos filhos sem .value
const images = reactive(useTemplateImages(computed(() => props.template)));

const reset = () => {
  name.value = props.template.name;
  active.value = props.template.active;
  form.value = contentOf(props.template);
  selectedKey.value = null;
  selectedElement.value = null;
};
reset();

const original = computed(() => contentOf(props.template));

// condições sem o uid; números como número
const plain = (key, value) => {
  if (key === 'conditions') {
    return value.map(row => ({ label: row.label, text: row.text }));
  }
  if (key === 'validity_days') return Number(value);
  return value;
};

const changedKeys = computed(() =>
  CONTENT_KEYS.filter(
    key =>
      JSON.stringify(plain(key, form.value[key])) !==
      JSON.stringify(plain(key, original.value[key]))
  )
);

const isDirty = computed(
  () =>
    name.value.trim() !== props.template.name ||
    active.value !== props.template.active ||
    changedKeys.value.length > 0
);


const validityValid = computed(() => {
  const days = form.value.validity_days;
  return (
    days !== '' && Number.isInteger(Number(days)) && days >= 0 && days <= 365
  );
});
const hasVisibleBlock = computed(() =>
  form.value.blocks.some(block => block.visible)
);
const isValid = computed(
  () => !!name.value.trim() && validityValid.value && hasVisibleBlock.value
);
const invalidReason = computed(() => {
  if (!name.value.trim()) {
    return t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.NAME_REQUIRED');
  }
  if (!validityValid.value) {
    return t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.VALIDITY_HELP');
  }
  if (!hasVisibleBlock.value) {
    return t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.NONE_VISIBLE');
  }
  return '';
});

const fontOptions = computed(() =>
  FONTS.map(font => ({
    value: font.value,
    label: t(
      `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.FONTS.${font.value.toUpperCase().replace('-', '_')}`
    ),
  }))
);

const font = computed({
  get: () => form.value.layout.font,
  set: value => {
    form.value.layout = { ...form.value.layout, font: value };
  },
});

const kindLabel = computed(() =>
  t(
    `OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.KINDS.${props.template.kind.toUpperCase()}`
  )
);

// ---------- blocos ----------

const blocks = computed({
  get: () => form.value.blocks,
  set: value => {
    form.value.blocks = value;
  },
});

watch(selectedKey, key => {
  if (key) lastKey.value = key;
});

const selectedBlock = computed(() =>
  blocks.value.find(block => block.key === selectedKey.value)
);

const updateBlock = block => {
  blocks.value = blocks.value.map(item =>
    item.key === block.key ? block : item
  );
};

const visibleBlocks = () => blocks.value.filter(block => block.visible);
const hiddenBlocks = () => blocks.value.filter(block => !block.visible);

// bloco novo depois do último bloco clicado (sem nenhum, no fim); bloco da proposta que estava escondido
// volta para o lugar dele quando não há outro bloco clicado na folha
const addBlock = block => {
  const rest = blocks.value.filter(item => item.key !== block.key);
  if (rest.length >= MAX_BLOCKS) return;
  const visible = rest.filter(item => item.visible);
  const after = visible.findIndex(item => item.key === lastKey.value);
  if (after === -1 && rest.length < blocks.value.length) {
    blocks.value = blocks.value.map(item =>
      item.key === block.key ? { ...item, visible: true } : item
    );
  } else {
    const position = after === -1 ? visible.length : after + 1;
    visible.splice(position, 0, { ...block, visible: true, new_page: false });
    blocks.value = [...visible, ...rest.filter(item => !item.visible)];
  }
  selectedKey.value = block.key;
  tab.value = 'blocks';
};

// troca de lugar com o vizinho; as quebras de página ficam onde estavam
const moveBlock = (key, direction) => {
  const visible = visibleBlocks();
  const index = visible.findIndex(block => block.key === key);
  const other = index + direction;
  if (index === -1 || other < 0 || other >= visible.length) return;
  const [current, neighbor] = [visible[index], visible[other]];
  visible[index] = { ...neighbor, new_page: current.new_page };
  visible[other] = { ...current, new_page: neighbor.new_page };
  blocks.value = [...visible, ...hiddenBlocks()];
};

const duplicate = key => {
  const index = blocks.value.findIndex(block => block.key === key);
  if (index === -1 || blocks.value.length >= MAX_BLOCKS) return;
  const copy = { ...duplicateBlock(blocks.value[index]), new_page: false };
  const list = [...blocks.value];
  list.splice(index + 1, 0, copy);
  blocks.value = list;
  selectedKey.value = copy.key;
};

const hide = key => {
  blocks.value = blocks.value.map(block =>
    block.key === key ? { ...block, visible: false } : block
  );
  if (selectedKey.value === key) selectedKey.value = null;
};

const remove = key => {
  blocks.value = blocks.value.filter(block => block.key !== key);
  if (selectedKey.value === key) selectedKey.value = null;
};

// imagem de um bloco: sobe na hora para as imagens do modelo e o bloco passa a usar quando salvar
const uploadBlockImage = async (key, file) => {
  if (!IMAGE_TYPES.includes(file?.type)) {
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.IMAGE_INVALID'));
    return;
  }
  uploadingKey.value = key;
  try {
    const { data } = await CrmAPI.uploadProposalTemplateLayoutImage(
      props.template.id,
      file
    );
    images.remember(data.id, data.url);
    const block = blocks.value.find(item => item.key === key);
    if (block) updateBlock({ ...block, image_id: data.id });
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    uploadingKey.value = null;
  }
};

const pickImage = key => {
  imageTarget = key;
  fileRef.value?.click();
};

const onFile = event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (file && imageTarget) uploadBlockImage(imageTarget, file);
};

// trocar de aba solta o que estava selecionado na outra
watch(tab, value => {
  if (value !== 'blocks') selectedKey.value = null;
  if (value !== 'letterhead') selectedElement.value = null;
});

// ---------- campos automáticos ----------

// campo automático vai para o texto em edição; sem nenhum em edição, é copiado
let lastField = null;
const onFocusIn = event => {
  const field = event.target;
  if (
    ['INPUT', 'TEXTAREA'].includes(field.tagName) &&
    field.closest('[data-fields]')
  ) {
    lastField = field;
  }
};

const insertField = async token => {
  if (lastField?.isConnected && !lastField.disabled) {
    const start = lastField.selectionStart ?? lastField.value.length;
    const end = lastField.selectionEnd ?? start;
    lastField.setRangeText(token, start, end, 'end');
    lastField.dispatchEvent(new Event('input', { bubbles: true }));
    lastField.focus();
    return;
  }
  try {
    await copyTextToClipboard(token);
    useAlert(
      t('OUTSIDER_CRM.PROPOSAL_SETTINGS.FIELDS.COPIED', { field: token })
    );
  } catch {
    useAlert(token);
  }
};

// ---------- salvar ----------

// blocos que eram ligados pelas chaves antigas levam a chave junto, para o modelo ficar coerente
const flagsFromBlocks = () =>
  Object.fromEntries(
    Object.entries(FLAG_OF_BLOCK).map(([type, flag]) => [
      flag,
      form.value.blocks.some(block => block.type === type && block.visible),
    ])
  );

const contentPayload = keys => {
  const content = Object.fromEntries(
    keys.map(key => [key, plain(key, form.value[key])])
  );
  return keys.includes('blocks')
    ? { ...content, ...flagsFromBlocks() }
    : content;
};

const previewPayload = computed(() => ({
  name: name.value.trim() || props.template.name,
  active: true,
  content: contentPayload(CONTENT_KEYS),
}));

// imagem enviada (cabeçalho, rodapé) volta com o modelo salvo; o que está em edição continua na tela
const onImageUpdated = data => emit('updated', data);

const save = async () => {
  if (!isValid.value || !isDirty.value) return;
  const payload = { name: name.value.trim(), active: active.value };
  if (changedKeys.value.length) {
    payload.content = contentPayload(changedKeys.value);
  }
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.updateProposalTemplate(
      props.template.id,
      payload
    );
    emit('updated', data);
    // a resposta já vem normalizada (linhas vazias de condição saem, números dentro dos limites)
    const keep = selectedKey.value;
    name.value = data.name;
    active.value = data.active;
    form.value = contentOf(data);
    if (form.value.blocks.some(block => block.key === keep)) {
      selectedKey.value = keep;
    }
    useAlert(t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.SAVED'));
  } catch (error) {
    useAlert(settingsError(t, error));
  } finally {
    isSaving.value = false;
  }
};

const requestClose = () => {
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

// ---------- tela ----------

const { width: areaWidth } = useElementSize(canvasArea);
const sheetWidth = computed(() =>
  Math.round(Math.min(760, Math.max(420, areaWidth.value - 96)))
);

const TABS = [
  { key: 'blocks', icon: 'i-lucide-layout-grid' },
  { key: 'letterhead', icon: 'i-lucide-layout-template' },
  { key: 'settings', icon: 'i-lucide-settings-2' },
];

const fieldClass =
  '!mb-0 w-full px-3 py-2 text-sm rounded-lg reset-base bg-n-alpha-black2 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak focus:outline-n-brand';
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-50 flex flex-col bg-n-background text-n-slate-12"
      data-template-studio
      @focusin="onFocusIn"
    >
      <!-- Barra de cima -->
      <header
        class="flex flex-wrap items-center gap-3 px-4 py-2.5 border-b border-n-weak bg-n-solid-1"
      >
        <button
          v-tooltip.bottom="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.BACK')"
          type="button"
          class="grid rounded-lg size-9 place-content-center text-n-blue-11 hover:bg-n-alpha-2"
          :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.BACK')"
          data-studio-back
          @click="requestClose"
        >
          <span class="i-lucide-arrow-left size-5" />
        </button>
        <div class="flex flex-col flex-1 min-w-[12rem]">
          <label class="flex items-center gap-2 group/name">
            <input
              v-model="name"
              type="text"
              maxlength="255"
              class="!mb-0 min-w-[6rem] max-w-xl [field-sizing:content] px-1 -mx-1 text-xl font-semibold bg-transparent border-0 rounded-md outline-none reset-base text-n-slate-12 hover:bg-n-alpha-1 focus:bg-n-alpha-1"
              :class="{ '!bg-n-ruby-2': !name.trim() }"
              :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.NAME')"
              data-studio-name
            />
            <span
              class="i-lucide-pencil size-4 shrink-0 text-n-blue-11 opacity-70 group-hover/name:opacity-100"
            />
          </label>
          <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
            <span
              class="rounded-full size-2"
              :class="active ? 'bg-n-teal-9' : 'bg-n-slate-8'"
            />
            {{
              active
                ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.ACTIVE')
                : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.INACTIVE')
            }}
            {{ ` · ${kindLabel}` }}
            <template v-if="isDirty">
              <span class="text-n-slate-9">{{ '·' }}</span>
              <span class="text-n-amber-11">
                {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.UNSAVED') }}
              </span>
            </template>
          </span>
        </div>
        <span
          v-if="isDirty && !isValid"
          class="max-w-xs text-xs text-n-ruby-11"
        >
          {{ invalidReason }}
        </span>
        <Button
          v-if="isDirty"
          type="button"
          size="sm"
          variant="ghost"
          color="slate"
          :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.DISCARD')"
          @click="reset"
        />
        <Button
          type="button"
          size="sm"
          variant="outline"
          color="slate"
          :icon="showPreview ? 'i-lucide-eye-off' : 'i-lucide-eye'"
          :label="
            showPreview
              ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.CLOSE_PREVIEW')
              : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.PREVIEW')
          "
          data-studio-preview
          @click="showPreview = !showPreview"
        />
        <Button
          type="button"
          size="sm"
          :label="t('OUTSIDER_CRM.SAVE')"
          :is-loading="isSaving"
          :disabled="!isDirty || !isValid"
          data-studio-save
          @click="save"
        />
      </header>

      <div class="flex flex-1 min-h-0">
        <!-- Esquerda -->
        <aside
          class="flex flex-col border-r w-[22rem] shrink-0 border-n-weak bg-n-solid-1"
        >
          <nav class="flex gap-1 px-3 pt-2 border-b border-n-weak">
            <button
              v-for="item in TABS"
              :key="item.key"
              type="button"
              class="flex items-center gap-1 px-1.5 py-2.5 -mb-px text-[13px] whitespace-nowrap border-b-2"
              :class="
                tab === item.key
                  ? 'border-n-brand text-n-blue-11 font-medium'
                  : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
              "
              :data-studio-tab="item.key"
              @click="tab = item.key"
            >
              <span :class="item.icon" class="size-4" />
              {{
                t(
                  `OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.TABS.${item.key.toUpperCase()}`
                )
              }}
            </button>
          </nav>
          <div class="flex flex-col flex-1 gap-4 p-4 overflow-y-auto">
            <template v-if="tab === 'blocks'">
              <template v-if="selectedBlock">
                <BlockSettings
                  :key="selectedBlock.key"
                  v-model:form="form"
                  :block="selectedBlock"
                  :image-url="images.imageUrls[selectedBlock.image_id] || ''"
                  :is-uploading="uploadingKey === selectedBlock.key"
                  @update:block="updateBlock"
                  @back="selectedKey = null"
                  @hide="hide(selectedBlock.key)"
                  @remove="remove(selectedBlock.key)"
                  @pick-image="pickImage(selectedBlock.key)"
                />
                <FieldChips @insert="insertField" />
              </template>
              <BlockPalette v-else :blocks="blocks" @add="addBlock" />
            </template>
            <template v-else-if="tab === 'letterhead'">
              <LetterheadSettings
                v-model:layout="form.layout"
                v-model:selected="selectedElement"
                :template="template"
                :images="images"
                @updated="onImageUpdated"
              />
              <FieldChips @insert="insertField" />
            </template>
            <div v-else class="flex flex-col gap-4">
              <Input
                v-model="name"
                maxlength="255"
                :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.NAME')"
                :message-type="name.trim() ? 'info' : 'error'"
              />
              <label class="flex flex-col gap-1 text-sm">
                <span class="font-medium text-n-slate-12">
                  {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.FONT') }}
                </span>
                <Select v-model="font" :options="fontOptions" />
              </label>
              <label class="flex flex-col gap-1 text-sm">
                <span class="font-medium text-n-slate-12">
                  {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.VALIDITY') }}
                </span>
                <input
                  v-model="form.validity_days"
                  type="number"
                  min="0"
                  max="365"
                  :class="[fieldClass, { '!outline-n-ruby-8': !validityValid }]"
                />
                <span class="text-xs text-n-slate-11">
                  {{
                    t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.VALIDITY_HELP')
                  }}
                </span>
              </label>
              <label class="flex items-start gap-3 text-sm text-n-slate-12">
                <Switch v-model="active" class="mt-0.5" />
                <span class="flex flex-col gap-0.5">
                  {{ t('OUTSIDER_CRM.SETTINGS.ACTIVE') }}
                  <span class="text-xs text-n-slate-11">
                    {{
                      t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.INACTIVE_HELP')
                    }}
                  </span>
                </span>
              </label>
              <div class="flex flex-col gap-1 text-sm">
                <span class="font-medium text-n-slate-12">
                  {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.NEW_TEMPLATE.KIND') }}
                </span>
                <span class="text-n-slate-11">{{ kindLabel }}</span>
              </div>
            </div>
          </div>
        </aside>

        <!-- Folhas -->
        <main
          ref="canvasArea"
          class="relative flex-1 min-w-0 px-6 py-8 overflow-auto bg-n-alpha-1 bg-[radial-gradient(circle,rgb(var(--slate-7))_1px,transparent_1px)] [background-size:18px_18px]"
          @click.self="selectedKey = null"
        >
          <ProposalCanvas
            v-model:blocks="blocks"
            v-model:form="form"
            v-model:layout="form.layout"
            v-model:selected-key="selectedKey"
            v-model:selected-element="selectedElement"
            :images="images"
            :mode="tab === 'letterhead' ? 'letterhead' : 'blocks'"
            :width="sheetWidth"
            :uploading-key="uploadingKey"
            :font-css="fontCss(form.layout.font)"
            @move="moveBlock"
            @duplicate="duplicate"
            @hide="hide"
            @remove="remove"
            @pick-image="pickImage"
            @upload="uploadBlockImage"
            @added="key => (selectedKey = key)"
          />
        </main>

        <!-- Prévia em PDF -->
        <aside
          v-if="showPreview"
          class="flex flex-col w-[30rem] shrink-0 p-3 border-l border-n-weak bg-n-solid-1"
        >
          <TemplatePreview
            :template-id="template.id"
            :payload="previewPayload"
            class="flex-1 min-h-0"
            @hide="showPreview = false"
          />
        </aside>
      </div>

      <input
        ref="fileRef"
        type="file"
        accept="image/png,image/jpeg"
        class="hidden"
        @change="onFile"
      />
      <Dialog
        ref="leaveRef"
        type="alert"
        :title="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.LEAVE_TITLE')"
        :description="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.LEAVE_TEXT')"
        :confirm-button-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.LEAVE')"
        @confirm="leave"
      />
    </div>
  </Teleport>
</template>
