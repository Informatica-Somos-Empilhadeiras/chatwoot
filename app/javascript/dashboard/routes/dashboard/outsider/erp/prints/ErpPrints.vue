<script setup>
// OUTSIDER: aba "Modelos de relatório" da seção ERP (só administradores). Em cima, qual modelo sai em cada caso: a OS
// pelo Tipo de Atendimento dela (tipo sem escolha usa o padrão) e o orçamento num só padrão; "Original do Mais Prático"
// é o relatório de hoje, que continua valendo até alguém escolher outro. Embaixo, os modelos de OS e de orçamento (os
// padrões já vêm prontos): editar no estúdio, copiar, restaurar o padrão ou apagar.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PrintStudio from './PrintStudio.vue';
import PrintThumb from './PrintThumb.vue';
import { erpErrorMessage } from '../erpStore';

const { t } = useI18n();

const ORIGINAL = 'original';
const DEFAULT = 'default';

const isLoading = ref(true);
const templates = ref([]);
const catalog = ref({});
const attendanceTypes = ref([]);
const bindings = ref({});
const savedBindings = ref('');
const isSavingBindings = ref(false);
const editing = ref(null);
const busyId = ref(null);
const removeRef = ref(null);
const removing = ref(null);

const remember = data => {
  bindings.value = JSON.parse(JSON.stringify(data));
  savedBindings.value = JSON.stringify(data);
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await ErpAPI.printTemplates();
    templates.value = data.templates;
    catalog.value = data.catalog;
    attendanceTypes.value = data.attendance_types || [];
    remember(data.bindings);
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};
load();

const ofKind = kind => templates.value.filter(item => item.kind === kind);
const KINDS = ['os', 'quote'];

// ---------- qual modelo em cada caso ----------

const optionsFor = (kind, withDefault = false) => [
  ...(withDefault
    ? [{ value: DEFAULT, label: t('OUTSIDER_ERP.PRINTS.LIST.USE_DEFAULT') }]
    : []),
  { value: ORIGINAL, label: t('OUTSIDER_ERP.PRINTS.LIST.ORIGINAL') },
  ...ofKind(kind).map(item => ({ value: String(item.id), label: item.name })),
];

const typeChoice = type => String(bindings.value.os?.types?.[type] ?? DEFAULT);

const setTypeChoice = (type, value) => {
  const types = { ...(bindings.value.os?.types || {}) };
  if (value === DEFAULT) delete types[type];
  else types[type] = value === ORIGINAL ? ORIGINAL : Number(value);
  bindings.value = { ...bindings.value, os: { ...bindings.value.os, types } };
};

const setDefault = (kind, value) => {
  bindings.value = {
    ...bindings.value,
    [kind]: {
      ...bindings.value[kind],
      default: value === ORIGINAL ? ORIGINAL : Number(value),
    },
  };
};

const bindingsDirty = computed(
  () => JSON.stringify(bindings.value) !== savedBindings.value
);

const saveBindings = async () => {
  isSavingBindings.value = true;
  try {
    let latest = bindings.value;
    // eslint-disable-next-line no-restricted-syntax
    for (const kind of KINDS) {
      const entry = bindings.value[kind] || {};
      // eslint-disable-next-line no-await-in-loop
      const { data } = await ErpAPI.savePrintBindings(kind, {
        default: entry.default,
        types: kind === 'os' ? entry.types || {} : undefined,
      });
      latest = data.bindings;
    }
    remember(latest);
    useAlert(t('OUTSIDER_ERP.PRINTS.LIST.BINDINGS_SAVED'));
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    isSavingBindings.value = false;
  }
};

// quantos casos usam o modelo (para o selo da lista)
const usage = template => {
  const entry = bindings.value[template.kind] || {};
  const types = Object.values(entry.types || {}).filter(
    id => id === template.id
  ).length;
  return types + (entry.default === template.id ? 1 : 0);
};

// ---------- modelos ----------

const openStudio = async id => {
  busyId.value = id;
  try {
    const { data } = await ErpAPI.printTemplate(id);
    editing.value = data.template;
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    busyId.value = null;
  }
};

const create = async (kind, sourceId = null) => {
  busyId.value = sourceId || `new-${kind}`;
  try {
    const { data } = await ErpAPI.createPrintTemplate(
      sourceId ? { source_id: sourceId } : { kind }
    );
    templates.value = [...templates.value, data.template];
    editing.value = data.template;
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    busyId.value = null;
  }
};

const restore = async template => {
  busyId.value = template.id;
  try {
    const { data } = await ErpAPI.restorePrintTemplate(template.id);
    templates.value = templates.value.map(item =>
      item.id === template.id ? data.template : item
    );
    useAlert(t('OUTSIDER_ERP.PRINTS.LIST.RESTORED'));
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  } finally {
    busyId.value = null;
  }
};

const askRemove = template => {
  removing.value = template;
  removeRef.value?.open();
};

const remove = async () => {
  const template = removing.value;
  removeRef.value?.close();
  if (!template) return;
  try {
    const { data } = await ErpAPI.deletePrintTemplate(template.id);
    templates.value = templates.value.filter(item => item.id !== template.id);
    remember(data.bindings);
  } catch (error) {
    useAlert(erpErrorMessage(t, error));
  }
};

const onSaved = template => {
  templates.value = templates.value.map(item =>
    item.id === template.id ? { ...item, ...template } : item
  );
};

const SELECT =
  'w-full !mb-0 pl-2.5 !pr-8 py-1.5 text-sm rounded-lg bg-n-alpha-black2 bg-[right_-1.25rem_center] outline outline-1 outline-n-weak focus:outline-n-brand text-n-slate-12';
</script>

<template>
  <div class="flex flex-col gap-6" data-erp-prints>
    <div v-if="isLoading" class="flex justify-center p-10">
      <Spinner />
    </div>
    <template v-else>
      <section
        class="p-4 rounded-xl bg-n-solid-1 outline outline-1 outline-n-weak"
      >
        <div class="flex flex-wrap items-start justify-between gap-3 mb-3">
          <div>
            <h3 class="mb-0.5 text-base font-semibold text-n-slate-12">
              {{ t('OUTSIDER_ERP.PRINTS.LIST.BINDINGS_TITLE') }}
            </h3>
            <p class="max-w-3xl mb-0 text-sm text-n-slate-11">
              {{ t('OUTSIDER_ERP.PRINTS.LIST.BINDINGS_HELP') }}
            </p>
          </div>
          <Button
            size="sm"
            color="teal"
            icon="i-lucide-save"
            :disabled="!bindingsDirty"
            :is-loading="isSavingBindings"
            :label="t('OUTSIDER_ERP.PRINTS.LIST.SAVE_BINDINGS')"
            @click="saveBindings"
          />
        </div>
        <div class="grid gap-4 lg:grid-cols-[2fr_1fr]">
          <div
            class="overflow-hidden rounded-lg outline outline-1 outline-n-weak"
          >
            <table class="w-full text-sm">
              <thead class="bg-n-alpha-1 text-n-slate-11">
                <tr>
                  <th class="px-3 py-2 font-medium text-left">
                    {{ t('OUTSIDER_ERP.PRINTS.LIST.ATTENDANCE_TYPE') }}
                  </th>
                  <th class="px-3 py-2 font-medium text-left w-1/2">
                    {{ t('OUTSIDER_ERP.PRINTS.LIST.OS_TEMPLATE') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr class="border-t border-n-weak bg-n-teal-2/40">
                  <td class="px-3 py-1 font-medium text-n-slate-12">
                    {{ t('OUTSIDER_ERP.PRINTS.LIST.OS_DEFAULT') }}
                  </td>
                  <td class="px-3 py-1">
                    <select
                      :class="SELECT"
                      :value="String(bindings.os?.default ?? ORIGINAL)"
                      @change="setDefault('os', $event.target.value)"
                    >
                      <option
                        v-for="option in optionsFor('os')"
                        :key="option.value"
                        :value="option.value"
                      >
                        {{ option.label }}
                      </option>
                    </select>
                  </td>
                </tr>
                <tr
                  v-for="type in attendanceTypes"
                  :key="type"
                  class="border-t border-n-weak"
                  :data-attendance-type="type"
                >
                  <td class="px-3 py-1 text-n-slate-12">{{ type }}</td>
                  <td class="px-3 py-1">
                    <select
                      :class="SELECT"
                      :value="typeChoice(type)"
                      @change="setTypeChoice(type, $event.target.value)"
                    >
                      <option
                        v-for="option in optionsFor('os', true)"
                        :key="option.value"
                        :value="option.value"
                      >
                        {{ option.label }}
                      </option>
                    </select>
                  </td>
                </tr>
                <tr
                  v-if="!attendanceTypes.length"
                  class="border-t border-n-weak"
                >
                  <td colspan="2" class="px-3 py-3 text-n-slate-10">
                    {{ t('OUTSIDER_ERP.PRINTS.LIST.NO_TYPES') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div
            class="flex flex-col gap-2 p-3 rounded-lg outline outline-1 outline-n-weak h-fit"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('OUTSIDER_ERP.PRINTS.LIST.QUOTE_DEFAULT') }}
            </span>
            <select
              :class="SELECT"
              :value="String(bindings.quote?.default ?? ORIGINAL)"
              @change="setDefault('quote', $event.target.value)"
            >
              <option
                v-for="option in optionsFor('quote')"
                :key="option.value"
                :value="option.value"
              >
                {{ option.label }}
              </option>
            </select>
            <p class="mb-0 text-xs text-n-slate-10">
              {{ t('OUTSIDER_ERP.PRINTS.LIST.QUOTE_HELP') }}
            </p>
          </div>
        </div>
      </section>

      <section v-for="kind in KINDS" :key="kind" class="flex flex-col gap-3">
        <div class="flex items-center justify-between gap-3">
          <h3 class="mb-0 text-base font-semibold text-n-slate-12">
            {{ t(`OUTSIDER_ERP.PRINTS.LIST.TEMPLATES_${kind.toUpperCase()}`) }}
          </h3>
          <Button
            size="sm"
            variant="faded"
            color="teal"
            icon="i-lucide-plus"
            :is-loading="busyId === `new-${kind}`"
            :label="t('OUTSIDER_ERP.PRINTS.LIST.NEW')"
            @click="create(kind)"
          />
        </div>
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
          <article
            v-for="template in ofKind(kind)"
            :key="template.id"
            class="flex gap-3 p-3 rounded-xl bg-n-solid-1 outline outline-1 outline-n-weak hover:outline-n-slate-7"
            :data-print-template="template.builtin || template.id"
          >
            <button
              type="button"
              class="p-0 shrink-0"
              @click="openStudio(template.id)"
            >
              <PrintThumb :template="template" />
            </button>
            <div class="flex flex-col flex-1 min-w-0 gap-1.5">
              <button
                type="button"
                class="text-sm font-semibold text-left text-n-slate-12 hover:underline line-clamp-2"
                @click="openStudio(template.id)"
              >
                {{ template.name }}
              </button>
              <div class="flex flex-wrap gap-1">
                <span
                  v-if="template.builtin"
                  class="px-1.5 py-0.5 text-[11px] rounded bg-n-alpha-2 text-n-slate-11"
                >
                  {{ t('OUTSIDER_ERP.PRINTS.LIST.BUILTIN') }}
                </span>
                <span
                  v-if="kind === 'os'"
                  class="px-1.5 py-0.5 text-[11px] rounded"
                  :class="
                    template.photos
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-blue-3 text-n-blue-11'
                  "
                >
                  {{
                    template.photos
                      ? t('OUTSIDER_ERP.PRINTS.LIST.WITH_PHOTOS')
                      : t('OUTSIDER_ERP.PRINTS.LIST.WITHOUT_PHOTOS')
                  }}
                </span>
                <span
                  v-if="usage(template)"
                  class="px-1.5 py-0.5 text-[11px] rounded bg-n-amber-3 text-n-amber-11"
                >
                  {{
                    t('OUTSIDER_ERP.PRINTS.LIST.IN_USE', {
                      count: usage(template),
                    })
                  }}
                </span>
              </div>
              <div class="flex flex-wrap gap-1 mt-auto">
                <Button
                  size="xs"
                  variant="faded"
                  color="slate"
                  icon="i-lucide-pencil"
                  :is-loading="busyId === template.id"
                  :label="t('OUTSIDER_ERP.PRINTS.LIST.EDIT')"
                  @click="openStudio(template.id)"
                />
                <Button
                  v-tooltip.top="t('OUTSIDER_ERP.PRINTS.LIST.COPY')"
                  size="xs"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-copy"
                  @click="create(kind, template.id)"
                />
                <Button
                  v-if="template.builtin"
                  v-tooltip.top="t('OUTSIDER_ERP.PRINTS.LIST.RESTORE')"
                  size="xs"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-rotate-ccw"
                  @click="restore(template)"
                />
                <Button
                  v-tooltip.top="t('OUTSIDER_ERP.PRINTS.LIST.DELETE')"
                  size="xs"
                  variant="ghost"
                  color="ruby"
                  icon="i-lucide-trash-2"
                  @click="askRemove(template)"
                />
              </div>
            </div>
          </article>
        </div>
      </section>
    </template>

    <PrintStudio
      v-if="editing"
      :key="editing.id"
      :template="editing"
      :catalog="catalog[editing.kind]"
      @saved="onSaved"
      @close="editing = null"
    />
    <Dialog
      ref="removeRef"
      type="alert"
      :title="
        t('OUTSIDER_ERP.PRINTS.LIST.DELETE_TITLE', { name: removing?.name })
      "
      :description="t('OUTSIDER_ERP.PRINTS.LIST.DELETE_TEXT')"
      :confirm-button-label="t('OUTSIDER_ERP.PRINTS.LIST.DELETE')"
      @confirm="remove"
    />
  </div>
</template>
