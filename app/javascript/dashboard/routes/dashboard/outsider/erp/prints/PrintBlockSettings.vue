<script setup>
// OUTSIDER: os ajustes do bloco selecionado no estúdio. O formulário sai da regra de cada opção que o servidor manda
// (Outsider::Erp::Prints::Content.block_types): escolha, número, liga/desliga, texto, lista ou imagem. Ajuste que não
// vale no momento (ex.: "Respostas em" no checklist com fotos) fica escondido.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { BLOCK_ICONS, blockSpec, optionVisible } from './printsHelpers';

const props = defineProps({
  catalog: { type: Object, required: true },
  values: { type: Object, default: null },
  images: { type: Object, default: () => ({}) },
  uploading: { type: Boolean, default: false },
});

const emit = defineEmits(['upload', 'close', 'fields']);

const block = defineModel('block', { type: Object, required: true });

const { t, te } = useI18n();
const fileRef = ref(null);

const spec = computed(() => blockSpec(props.catalog, block.value.type));
const options = computed(() =>
  Object.entries(spec.value?.options || {}).filter(([name]) =>
    optionVisible(block.value, name)
  )
);

const set = (name, value) => {
  block.value = { ...block.value, [name]: value };
};

const typeKey = computed(() => block.value.type.toUpperCase());

const label = name => {
  const specific = `OUTSIDER_ERP.PRINTS.OPTIONS.${typeKey.value}_${name.toUpperCase()}`;
  return te(specific)
    ? t(specific)
    : t(`OUTSIDER_ERP.PRINTS.OPTIONS.${name.toUpperCase()}`);
};

const help = name => {
  const key = `OUTSIDER_ERP.PRINTS.HELP.${typeKey.value}_${name.toUpperCase()}`;
  return te(key) ? t(key) : '';
};

const valueLabel = (name, value) => {
  const specific = `OUTSIDER_ERP.PRINTS.VALUES.${typeKey.value}_${name.toUpperCase()}.${String(value).toUpperCase()}`;
  if (te(specific)) return t(specific);
  const key = `OUTSIDER_ERP.PRINTS.VALUES.${name.toUpperCase()}.${String(value).toUpperCase()}`;
  return te(key) ? t(key) : String(value);
};

const catalogLabel = (kind, key) => {
  const list = { group: 'groups', table: 'tables', long_text: 'texts' }[kind];
  return (
    (props.catalog[list] || []).find(item => item.key === key)?.label || key
  );
};

const textArea = name => block.value.type === 'text' && name === 'text';
const isSegmented = rule => rule.kind === 'enum' && rule.values.length <= 4;
const isRange = (rule, name) =>
  rule.kind === 'int' && (rule.max - rule.min > 4 || name === 'height');

// marcadores do tipo ({numero}, {cliente}...) que os textos livres aceitam
const placeholders = computed(() => props.catalog.placeholders || []);
const chip = key => ['{', key, '}'].join('');
const acceptsPlaceholders = name =>
  ['title', 'subtitle', 'text'].includes(name);
const insert = (name, key) =>
  set(
    name,
    `${block.value[name] || ''}{${key}}`.slice(0, spec.value.options[name].max)
  );

// seções do checklist que aparecem nos dados da folha (para o filtro)
const sectionNames = computed(() =>
  (props.values?.checklist || []).map(section => section.nome).filter(Boolean)
);
const toggleSection = name => {
  const list = block.value.sections || [];
  set(
    'sections',
    list.includes(name) ? list.filter(item => item !== name) : [...list, name]
  );
};

// linhas de assinatura
const lines = computed(() => block.value.lines || []);
const setLine = (index, value) =>
  set(
    'lines',
    lines.value.map((line, position) => (position === index ? value : line))
  );
const addLine = () => set('lines', [...lines.value, '']);
const removeLine = index =>
  set(
    'lines',
    lines.value.filter((_, position) => position !== index)
  );

const pickImage = () => fileRef.value?.click();
const onFile = event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (file) emit('upload', file, id => set('image_id', id));
};

const INPUT =
  'w-full px-2.5 py-1.5 text-sm rounded-lg bg-n-alpha-black2 outline outline-1 outline-n-weak focus:outline-n-brand text-n-slate-12';
const SELECT =
  'w-full !mb-0 pl-2.5 !pr-8 py-1.5 text-sm rounded-lg bg-n-alpha-black2 bg-[right_-1.25rem_center] outline outline-1 outline-n-weak focus:outline-n-brand text-n-slate-12';
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex items-center justify-between gap-2">
      <div
        class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
      >
        <span :class="BLOCK_ICONS[block.type]" class="size-4 text-n-teal-10" />
        {{ t(`OUTSIDER_ERP.PRINTS.BLOCKS.${typeKey}`) }}
      </div>
      <Button
        size="xs"
        variant="ghost"
        color="slate"
        icon="i-lucide-x"
        @click="emit('close')"
      />
    </div>

    <div
      v-for="[name, rule] in options"
      :key="name"
      class="flex flex-col gap-1.5"
      :data-option="name"
    >
      <div
        v-if="rule.kind === 'bool'"
        class="flex items-center justify-between gap-3"
      >
        <span class="text-sm text-n-slate-12">{{ label(name) }}</span>
        <Switch
          :model-value="block[name]"
          @update:model-value="value => set(name, value)"
        />
      </div>
      <template v-else>
        <label class="mb-0 text-xs font-medium text-n-slate-11">
          {{ label(name) }}
        </label>

        <!-- escolha curta: botões -->
        <div
          v-if="isSegmented(rule)"
          class="flex p-0.5 rounded-lg bg-n-alpha-2"
        >
          <button
            v-for="value in rule.values"
            :key="value"
            type="button"
            class="flex-1 h-7 px-1.5 text-xs rounded-md whitespace-nowrap"
            :class="
              block[name] === value
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="set(name, value)"
          >
            {{ valueLabel(name, value) }}
          </button>
        </div>

        <!-- escolha longa, grupo, tabela, texto do ERP: lista -->
        <select
          v-else-if="rule.kind !== 'int' && rule.values"
          :class="SELECT"
          :value="block[name]"
          @change="set(name, $event.target.value)"
        >
          <option v-for="value in rule.values" :key="value" :value="value">
            {{
              rule.kind === 'enum'
                ? valueLabel(name, value)
                : catalogLabel(rule.kind, value)
            }}
          </option>
        </select>

        <!-- número -->
        <div v-else-if="isRange(rule, name)" class="flex items-center gap-2">
          <input
            type="range"
            class="flex-1 accent-[#00663B]"
            :min="rule.min"
            :max="rule.max"
            :value="block[name]"
            @input="set(name, Number($event.target.value))"
          />
          <span class="w-12 text-xs text-right tabular-nums text-n-slate-11">
            {{ block[name] }}{{ name === 'width' ? '%' : '' }}
          </span>
        </div>
        <div
          v-else-if="rule.kind === 'int'"
          class="flex p-0.5 rounded-lg bg-n-alpha-2"
        >
          <button
            v-for="value in Array.from(
              { length: rule.max - rule.min + 1 },
              (_, index) => rule.min + index
            )"
            :key="value"
            type="button"
            class="flex-1 h-7 text-xs rounded-md"
            :class="
              block[name] === value
                ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="set(name, value)"
          >
            {{ value }}
          </button>
        </div>

        <!-- texto -->
        <template v-else-if="rule.kind === 'text'">
          <textarea
            v-if="textArea(name)"
            rows="5"
            :class="INPUT"
            :maxlength="rule.max"
            :value="block[name]"
            @input="set(name, $event.target.value)"
          />
          <input
            v-else
            type="text"
            class="reset-base"
            :class="INPUT"
            :maxlength="rule.max"
            :value="block[name]"
            @input="set(name, $event.target.value)"
          />
          <div v-if="acceptsPlaceholders(name)" class="flex flex-wrap gap-1">
            <button
              v-for="item in placeholders"
              :key="item.key"
              type="button"
              class="px-1.5 py-0.5 text-[11px] rounded bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 hover:text-n-slate-12"
              :title="item.label"
              @click="insert(name, item.key)"
            >
              {{ chip(item.key) }}
            </button>
          </div>
        </template>

        <!-- seções do checklist -->
        <template v-else-if="rule.kind === 'list' && name === 'sections'">
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="section in sectionNames"
              :key="section"
              type="button"
              class="px-2 py-1 text-xs rounded-full outline outline-1"
              :class="
                (block.sections || []).includes(section)
                  ? 'bg-n-teal-3 text-n-teal-11 outline-n-teal-7'
                  : 'text-n-slate-11 outline-n-weak hover:text-n-slate-12'
              "
              @click="toggleSection(section)"
            >
              {{ section }}
            </button>
            <span
              v-for="section in (block.sections || []).filter(
                item => !sectionNames.includes(item)
              )"
              :key="`x-${section}`"
              class="flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-n-amber-3 text-n-amber-11"
            >
              {{ section }}
              <button
                type="button"
                class="p-0 i-lucide-x size-3"
                @click="toggleSection(section)"
              />
            </span>
          </div>
        </template>

        <!-- linhas de assinatura -->
        <template v-else-if="rule.kind === 'list'">
          <div
            v-for="(line, index) in lines"
            :key="index"
            class="flex items-center gap-1.5"
          >
            <input
              type="text"
              class="reset-base"
              :class="INPUT"
              :maxlength="rule.length"
              :value="line"
              @input="setLine(index, $event.target.value)"
            />
            <Button
              size="xs"
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              @click="removeLine(index)"
            />
          </div>
          <Button
            v-if="lines.length < rule.max"
            size="xs"
            variant="faded"
            color="slate"
            icon="i-lucide-plus"
            :label="t('OUTSIDER_ERP.PRINTS.STUDIO.ADD_LINE')"
            @click="addLine"
          />
        </template>

        <!-- imagem -->
        <div v-else-if="rule.kind === 'image'" class="flex items-center gap-2">
          <img
            v-if="images[block[name]]"
            :src="images[block[name]]"
            class="object-contain w-20 h-12 p-1 bg-white rounded outline outline-1 outline-n-weak"
          />
          <Button
            size="xs"
            variant="faded"
            color="slate"
            icon="i-lucide-upload"
            :is-loading="uploading"
            :label="
              images[block[name]]
                ? t('OUTSIDER_ERP.PRINTS.STUDIO.CHANGE_IMAGE')
                : t('OUTSIDER_ERP.PRINTS.STUDIO.SEND_IMAGE')
            "
            @click="pickImage"
          />
          <input
            ref="fileRef"
            type="file"
            accept="image/png,image/jpeg"
            class="hidden"
            @change="onFile"
          />
        </div>
      </template>
      <p v-if="help(name)" class="mb-0 text-[11px] text-n-slate-10">
        {{ help(name) }}
      </p>
    </div>

    <Button
      v-if="
        ['fields', 'table'].includes(block.type) ||
        (block.type === 'checklist' &&
          block.photos === 'without' &&
          block.answers === 'table')
      "
      size="sm"
      variant="faded"
      color="teal"
      icon="i-lucide-list-checks"
      :label="t('OUTSIDER_ERP.PRINTS.STUDIO.EDIT_FIELDS')"
      @click="
        emit(
          'fields',
          block.type === 'fields'
            ? block.group
            : block.type === 'table'
              ? block.table
              : 'checklist'
        )
      "
    />
  </div>
</template>
