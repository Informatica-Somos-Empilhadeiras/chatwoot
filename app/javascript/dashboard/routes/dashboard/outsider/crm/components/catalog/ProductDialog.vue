<script setup>
// OUTSIDER: cadastro de máquina ou acessório do catálogo (para quem gerencia o catálogo) ou ficha só
// de consulta (os demais). A imagem escolhida fica guardada e sobe depois de salvar o item; item que
// já está em proposta não se apaga, então o diálogo oferece desativar.
// Quantidade disponível e reservada são opcionais. "Criar proposta" (Entrega 19) abre uma proposta nova
// já com o item: no cadastro é uma opção que vale ao salvar; na ficha de consulta, um botão.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ConfirmDelete from '../ConfirmDelete.vue';
import SpecsEditor from './SpecsEditor.vue';
import FeaturesEditor from './FeaturesEditor.vue';
import ProductDetails from './ProductDetails.vue';
import { centsToInput, errorMessage, parseMoney } from '../../helpers';
import {
  IMAGE_TYPES,
  PRODUCT_KINDS,
  kindLabel,
  newRowId,
  parseStock,
} from './catalog';

const props = defineProps({
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['saved', 'deleted', 'createProposal']);

const { t } = useI18n();

const dialogRef = ref(null);
const confirmRef = ref(null);
const fileInput = ref(null);
const isSaving = ref(false);
// o item como está no servidor (null = novo)
const product = ref(null);
const form = ref({});
const specs = ref([]);
const features = ref([]);
const imageFile = ref(null);
const imagePreview = ref('');
const removeImage = ref(false);
// apagar recusado porque o item está em propostas
const blockedMessage = ref('');
// abrir uma proposta nova com o item depois de salvar
const proposeAfterSave = ref(false);

const emptyForm = kind => ({
  kind: PRODUCT_KINDS.includes(kind) ? kind : 'machine',
  name: '',
  code: '',
  brand: '',
  description: '',
  sale: '',
  rental: '',
  available: '',
  reserved: '',
  active: true,
});

const salePrice = computed(() => parseMoney(form.value.sale));
const rentalPrice = computed(() => parseMoney(form.value.rental));
const validPrice = value => Number.isFinite(value) && value >= 0;
const available = computed(() => parseStock(form.value.available));
const reserved = computed(() => parseStock(form.value.reserved));
const validStock = value => !Number.isNaN(value);

const isValid = computed(
  () =>
    Boolean(form.value.name?.trim()) &&
    validPrice(salePrice.value) &&
    validPrice(rentalPrice.value) &&
    validStock(available.value) &&
    validStock(reserved.value)
);

const canPropose = computed(() =>
  props.canManage ? form.value.active : Boolean(product.value?.active)
);

const shownImage = computed(
  () =>
    imagePreview.value || (removeImage.value ? '' : product.value?.image_url)
);

const title = computed(() => {
  if (!props.canManage) return product.value?.name || '';
  return form.value.id
    ? t('OUTSIDER_CRM.CATALOG.EDIT')
    : t('OUTSIDER_CRM.CATALOG.NEW');
});

const setImageFile = file => {
  if (imagePreview.value) URL.revokeObjectURL(imagePreview.value);
  imageFile.value = file || null;
  imagePreview.value = file ? URL.createObjectURL(file) : '';
};

const pickImage = file => {
  if (!file) return;
  if (!IMAGE_TYPES.includes(file.type)) {
    useAlert(t('OUTSIDER_CRM.CATALOG.IMAGE.INVALID_TYPE'));
    return;
  }
  setImageFile(file);
  removeImage.value = false;
};

const onFileChange = event => {
  pickImage(event.target.files[0]);
  event.target.value = '';
};

const chooseImage = () => fileInput.value?.click();

const clearImage = () => {
  setImageFile(null);
  removeImage.value = Boolean(product.value?.image_url);
};

const formFrom = item => ({
  id: item.id,
  kind: item.kind,
  name: item.name || '',
  code: item.code || '',
  brand: item.brand || '',
  description: item.description || '',
  sale: centsToInput(item.sale_price_cents),
  rental: centsToInput(item.rental_price_cents),
  available: item.available_quantity ?? '',
  reserved: item.reserved_quantity ?? '',
  active: item.active,
});

// item = produto para editar ou consultar; sem item, cadastro novo do tipo kind
const open = (item = null, kind = 'machine') => {
  product.value = item;
  form.value = item ? formFrom(item) : emptyForm(kind);
  specs.value = (item?.specs || []).map(spec => ({
    uid: newRowId(),
    label: spec.label || '',
    value: spec.value || '',
    bold: Boolean(spec.bold),
  }));
  features.value = (item?.features || []).map(text => ({
    uid: newRowId(),
    text,
  }));
  blockedMessage.value = '';
  proposeAfterSave.value = false;
  removeImage.value = false;
  setImageFile(null);
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const onClose = () => setImageFile(null);

const payload = () => ({
  kind: form.value.kind,
  name: form.value.name.trim(),
  code: form.value.code.trim(),
  brand: form.value.brand.trim(),
  description: form.value.description.trim(),
  sale_price_cents: Math.round(salePrice.value * 100),
  rental_price_cents: Math.round(rentalPrice.value * 100),
  available_quantity: available.value,
  reserved_quantity: reserved.value,
  active: form.value.active,
  specs: specs.value
    .filter(spec => spec.label.trim())
    .map(spec => ({
      label: spec.label.trim(),
      value: spec.value.trim(),
      bold: spec.bold,
    })),
  features: features.value.map(feature => feature.text.trim()).filter(Boolean),
});

// a imagem vai depois do item salvo (item novo ainda não tem id)
const saveImage = async saved => {
  if (imageFile.value) {
    const { data } = await CrmAPI.uploadProductImage(saved.id, imageFile.value);
    return data;
  }
  if (removeImage.value && saved.image_url) {
    const { data } = await CrmAPI.removeProductImage(saved.id);
    return data;
  }
  return saved;
};

const save = async () => {
  if (!props.canManage || !isValid.value || isSaving.value) return;
  isSaving.value = true;
  let saved;
  try {
    const { data } = form.value.id
      ? await CrmAPI.updateProduct(form.value.id, payload())
      : await CrmAPI.createProduct(payload());
    saved = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
    isSaving.value = false;
    return;
  }
  try {
    saved = await saveImage(saved);
  } catch (error) {
    // o item ficou salvo; o diálogo continua aberto, já como edição, para escolher outra imagem
    form.value.id = saved.id;
    product.value = saved;
    removeImage.value = false;
    setImageFile(null);
    emit('saved', saved);
    useAlert(
      t('OUTSIDER_CRM.CATALOG.IMAGE.FAILED', {
        message: errorMessage(t, error),
      })
    );
    isSaving.value = false;
    return;
  }
  isSaving.value = false;
  useAlert(t('OUTSIDER_CRM.CATALOG.SAVED', { name: saved.name }));
  emit('saved', saved);
  close();
  if (proposeAfterSave.value && saved.active) emit('createProposal', saved);
};

const propose = () => {
  close();
  emit('createProposal', product.value);
};

const askDelete = () => {
  const item = product.value;
  if (!item) return;
  confirmRef.value?.open(
    t('OUTSIDER_CRM.CATALOG.DELETE_TITLE'),
    t('OUTSIDER_CRM.CATALOG.DELETE_TEXT', { name: item.name }),
    async () => {
      try {
        await CrmAPI.deleteProduct(item.id);
      } catch (error) {
        if (error?.response?.data?.error !== 'in_use') throw error;
        blockedMessage.value = errorMessage(t, error);
        return;
      }
      useAlert(t('OUTSIDER_CRM.CATALOG.DELETED', { name: item.name }));
      emit('deleted', item);
      close();
    }
  );
};

const deactivate = () => {
  form.value.active = false;
  blockedMessage.value = '';
  save();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    width="2xl"
    overflow-y-auto
    @confirm="save"
    @close="onClose"
  >
    <ProductDetails v-if="!canManage && product" :product="product" />

    <div v-else class="flex flex-col gap-5">
      <div
        v-if="blockedMessage"
        class="flex flex-col gap-2 p-3 text-sm rounded-xl bg-n-amber-2 text-n-amber-11"
      >
        <p class="mb-0">{{ blockedMessage }}</p>
        <p class="mb-0">{{ t('OUTSIDER_CRM.CATALOG.DEACTIVATE_HINT') }}</p>
        <div v-if="form.active">
          <Button
            type="button"
            size="sm"
            color="amber"
            icon="i-lucide-eye-off"
            :label="t('OUTSIDER_CRM.CATALOG.DEACTIVATE')"
            :disabled="!isValid || isSaving"
            @click="deactivate"
          />
        </div>
      </div>

      <div class="flex flex-col gap-4 sm:flex-row">
        <div class="flex flex-col gap-2 sm:w-44 shrink-0">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('OUTSIDER_CRM.CATALOG.IMAGE.TITLE') }}
          </span>
          <button
            type="button"
            class="flex items-center justify-center w-full overflow-hidden aspect-square rounded-xl bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-slate-6"
            @click="chooseImage"
            @dragover.prevent
            @drop.prevent="pickImage($event.dataTransfer.files[0])"
          >
            <img
              v-if="shownImage"
              :src="shownImage"
              :alt="form.name"
              class="object-contain w-full h-full p-2"
            />
            <span
              v-else
              class="flex flex-col items-center gap-1 p-3 text-center"
            >
              <Icon icon="i-lucide-image-plus" class="size-8 text-n-slate-9" />
              <span class="text-xs text-n-slate-11">
                {{ t('OUTSIDER_CRM.CATALOG.IMAGE.DROP') }}
              </span>
            </span>
          </button>
          <input
            ref="fileInput"
            type="file"
            class="hidden"
            :accept="IMAGE_TYPES.join(',')"
            @change="onFileChange"
          />
          <div class="flex flex-wrap items-center gap-1">
            <Button
              type="button"
              size="xs"
              variant="faded"
              color="slate"
              icon="i-lucide-upload"
              :label="
                shownImage
                  ? t('OUTSIDER_CRM.CATALOG.IMAGE.REPLACE')
                  : t('OUTSIDER_CRM.CATALOG.IMAGE.CHOOSE')
              "
              @click="chooseImage"
            />
            <Button
              v-if="shownImage"
              v-tooltip.top="t('OUTSIDER_CRM.CATALOG.IMAGE.REMOVE')"
              type="button"
              size="xs"
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              @click="clearImage"
            />
          </div>
          <p class="mb-0 text-xs text-n-slate-11">
            {{
              imageFile || removeImage
                ? t('OUTSIDER_CRM.CATALOG.IMAGE.PENDING')
                : t('OUTSIDER_CRM.CATALOG.IMAGE.HELP')
            }}
          </p>
        </div>

        <div class="flex flex-col flex-1 min-w-0 gap-4">
          <div class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_CRM.CATALOG.FORM.KIND') }}
            </span>
            <div
              class="flex self-start p-0.5 rounded-lg bg-n-alpha-2 outline outline-1 -outline-offset-1 outline-n-weak"
            >
              <Button
                v-for="kind in PRODUCT_KINDS"
                :key="kind"
                type="button"
                size="sm"
                :icon="
                  kind === 'machine' ? 'i-lucide-forklift' : 'i-lucide-wrench'
                "
                :variant="form.kind === kind ? 'solid' : 'ghost'"
                :color="form.kind === kind ? 'blue' : 'slate'"
                :label="kindLabel(t, kind)"
                @click="form.kind = kind"
              />
            </div>
          </div>
          <Input
            v-model="form.name"
            :label="t('OUTSIDER_CRM.CATALOG.FORM.NAME')"
            :placeholder="t('OUTSIDER_CRM.CATALOG.FORM.NAME_PLACEHOLDER')"
            maxlength="255"
          />
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Input
              v-model="form.code"
              :label="t('OUTSIDER_CRM.CATALOG.FORM.CODE')"
              :placeholder="t('OUTSIDER_CRM.CATALOG.FORM.CODE_PLACEHOLDER')"
              maxlength="120"
            />
            <Input
              v-model="form.brand"
              :label="t('OUTSIDER_CRM.CATALOG.FORM.BRAND')"
              :placeholder="t('OUTSIDER_CRM.CATALOG.FORM.BRAND_PLACEHOLDER')"
              maxlength="120"
            />
          </div>
        </div>
      </div>

      <label class="flex flex-col gap-1 text-sm">
        <span class="font-medium text-n-slate-12">
          {{ t('OUTSIDER_CRM.CATALOG.FORM.DESCRIPTION') }}
        </span>
        <textarea
          v-model="form.description"
          rows="3"
          maxlength="5000"
          class="!mb-0 rounded-lg"
          :placeholder="t('OUTSIDER_CRM.CATALOG.FORM.DESCRIPTION_PLACEHOLDER')"
        />
      </label>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          v-model="form.sale"
          inputmode="decimal"
          :label="t('OUTSIDER_CRM.CATALOG.FORM.SALE_PRICE')"
          :placeholder="t('OUTSIDER_CRM.CATALOG.FORM.PRICE_PLACEHOLDER')"
          :message="
            validPrice(salePrice)
              ? ''
              : t('OUTSIDER_CRM.CATALOG.FORM.PRICE_INVALID')
          "
          :message-type="validPrice(salePrice) ? 'info' : 'error'"
        />
        <Input
          v-model="form.rental"
          inputmode="decimal"
          :label="t('OUTSIDER_CRM.CATALOG.FORM.RENTAL_PRICE')"
          :placeholder="t('OUTSIDER_CRM.CATALOG.FORM.PRICE_PLACEHOLDER')"
          :message="
            validPrice(rentalPrice)
              ? ''
              : t('OUTSIDER_CRM.CATALOG.FORM.PRICE_INVALID')
          "
          :message-type="validPrice(rentalPrice) ? 'info' : 'error'"
        />
        <Input
          v-model="form.available"
          type="number"
          min="0"
          step="1"
          inputmode="numeric"
          :label="t('OUTSIDER_CRM.CATALOG.FORM.AVAILABLE')"
          :placeholder="t('OUTSIDER_CRM.CATALOG.FORM.QUANTITY_PLACEHOLDER')"
          :message="
            validStock(available)
              ? t('OUTSIDER_CRM.CATALOG.FORM.QUANTITY_HELP')
              : t('OUTSIDER_CRM.CATALOG.FORM.QUANTITY_INVALID')
          "
          :message-type="validStock(available) ? 'info' : 'error'"
        />
        <Input
          v-model="form.reserved"
          type="number"
          min="0"
          step="1"
          inputmode="numeric"
          :label="t('OUTSIDER_CRM.CATALOG.FORM.RESERVED')"
          :placeholder="t('OUTSIDER_CRM.CATALOG.FORM.QUANTITY_PLACEHOLDER')"
          :message="
            validStock(reserved)
              ? ''
              : t('OUTSIDER_CRM.CATALOG.FORM.QUANTITY_INVALID')
          "
          :message-type="validStock(reserved) ? 'info' : 'error'"
        />
      </div>

      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <Switch v-model="form.active" class="mt-0.5" />
        <span class="flex flex-col">
          {{ t('OUTSIDER_CRM.CATALOG.FORM.ACTIVE') }}
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.CATALOG.FORM.ACTIVE_HELP') }}
          </span>
        </span>
      </label>

      <label
        v-if="canPropose"
        class="flex items-start gap-2 text-sm text-n-slate-12"
      >
        <Switch v-model="proposeAfterSave" class="mt-0.5" />
        <span class="flex flex-col">
          {{ t('OUTSIDER_CRM.CATALOG.PROPOSE.AFTER_SAVE') }}
          <span class="text-xs text-n-slate-11">
            {{ t('OUTSIDER_CRM.CATALOG.PROPOSE.AFTER_SAVE_HELP') }}
          </span>
        </span>
      </label>

      <SpecsEditor v-model="specs" />
      <FeaturesEditor v-model="features" />
    </div>

    <template #footer>
      <div class="flex flex-wrap items-center w-full gap-3">
        <Button
          v-if="canManage && product"
          type="button"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          :label="t('OUTSIDER_CRM.DELETE.CONFIRM')"
          :disabled="isSaving"
          @click="askDelete"
        />
        <div class="flex-1" />
        <Button
          type="button"
          variant="faded"
          color="slate"
          :label="
            canManage
              ? t('OUTSIDER_CRM.CANCEL')
              : t('OUTSIDER_CRM.CATALOG.CLOSE')
          "
          @click="close"
        />
        <Button
          v-if="canManage"
          type="submit"
          color="blue"
          :label="
            proposeAfterSave && canPropose
              ? t('OUTSIDER_CRM.CATALOG.PROPOSE.SAVE_AND_CREATE')
              : t('OUTSIDER_CRM.SAVE')
          "
          :is-loading="isSaving"
          :disabled="!isValid || isSaving"
        />
        <Button
          v-else-if="canPropose"
          type="button"
          color="blue"
          icon="i-lucide-file-plus"
          :label="t('OUTSIDER_CRM.CATALOG.PROPOSE.CREATE')"
          @click="propose"
        />
      </div>
    </template>
  </Dialog>
  <ConfirmDelete ref="confirmRef" />
</template>
