<script setup>
// OUTSIDER: um bloco do modelo de relatório desenhado na folha do estúdio, imitando o PDF do servidor
// (Outsider::Erp::Prints::Pdf): 1 px = 1 pt. O checklist fica no PrintChecklist.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PrintChecklist from './PrintChecklist.vue';
import PrintTable from './PrintTable.vue';
import PrintSectionTitle from './PrintSectionTitle.vue';
import {
  chosenFields,
  contrastColor,
  fillPlaceholders,
  themeColor,
} from './printsHelpers';

const props = defineProps({
  block: { type: Object, required: true },
  content: { type: Object, required: true },
  catalog: { type: Object, required: true },
  values: { type: Object, default: null },
  images: { type: Object, default: () => ({}) },
  photos: { type: Object, default: () => ({}) },
  width: { type: Number, required: true },
});

const { t } = useI18n();

const theme = computed(() => props.content.theme || {});
const base = computed(() => Number(theme.value.size) || 9);
const color = name => themeColor(theme.value, name);
const contrast = name => contrastColor(theme.value, name);
const fill = text => fillPlaceholders(text, props.values?.placeholders);
const headingFont = computed(() => `var(--print-heading)`);

// ---- cabeçalho ----
const logo = computed(() => {
  if (props.block.logo === 'erp') return props.values?.emitter?.logo_url;
  if (props.block.logo === 'upload')
    return props.images[props.block.image_id] || '';
  return '';
});
const emitterLines = computed(() => props.values?.emitter?.lines || []);
const title = computed(() => fill(props.block.title).trim());
const subtitle = computed(() => fill(props.block.subtitle).trim());

// ---- campos ----
const fieldPairs = computed(() => {
  const data = props.values?.groups?.[props.block.group] || {};
  const pairs = chosenFields(
    props.content,
    props.catalog,
    props.block.group
  ).map(field => ({
    label: field.label,
    value: String(data[field.key] ?? ''),
  }));
  return props.block.hide_empty ? pairs.filter(pair => pair.value) : pairs;
});
const fieldColumns = computed(() =>
  Math.min(Math.max(Number(props.block.columns) || 2, 1), 4)
);
const fieldRows = computed(() => {
  const rows = [];
  for (let i = 0; i < fieldPairs.value.length; i += fieldColumns.value) {
    const row = fieldPairs.value.slice(i, i + fieldColumns.value);
    while (row.length < fieldColumns.value) row.push(null);
    rows.push(row);
  }
  return rows;
});

// ---- tabela ----
const tableRows = computed(
  () => props.values?.tables?.[props.block.table] || []
);
const tableColumns = computed(() =>
  chosenFields(props.content, props.catalog, props.block.table)
);

// ---- texto longo ----
const longText = computed(() =>
  String(props.values?.texts?.[props.block.field] || '').trim()
);

// ---- totais ----
const totalRows = computed(() => {
  const data = props.values?.groups?.totais || {};
  let rows = chosenFields(props.content, props.catalog, 'totais').map(
    field => ({
      key: field.key,
      label: field.label,
      value: data[field.key] || '',
    })
  );
  if (props.block.hide_zero)
    rows = rows.filter(row => row.value || row.key === 'total');
  return rows;
});

// ---- assinaturas ----
const PEOPLE = [
  ['tecn', 'tecnico'],
  ['client', 'cliente'],
  ['vend', 'vendedor'],
];
const personFor = label => {
  const text = String(label || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();
  const people = props.values?.people || {};
  const match = PEOPLE.find(([part]) => text.includes(part));
  if (match) return people[match[1]] || '';
  if (text.includes('respons')) return people.tecnico || people.vendedor || '';
  return '';
};

const sizes = {
  heading: { lg: 8, md: 5, sm: 2 },
  text: { sm: -1, md: 0, lg: 2 },
};
</script>

<template>
  <div :style="{ fontSize: `${base}px`, color: color('text') }">
    <!-- cabeçalho -->
    <div v-if="block.type === 'header'">
      <div
        v-if="block.style === 'band'"
        class="flex items-start gap-4"
        :style="{
          background: color('primary'),
          borderRadius: '6px',
          height: '74px',
          padding: '10px 14px 10px 10px',
        }"
      >
        <div
          v-if="logo"
          class="flex items-center justify-center bg-white shrink-0"
          :style="{ width: '138px', height: '54px', borderRadius: '4px' }"
        >
          <img :src="logo" class="object-contain max-w-[130px] max-h-[50px]" />
        </div>
        <div
          v-if="block.company"
          class="flex-1 min-w-0 text-right"
          :style="{ color: contrast('primary'), lineHeight: 1.25 }"
        >
          <div class="font-bold" :style="{ fontSize: `${base + 1}px` }">
            {{ values?.emitter?.nome }}
          </div>
          <div
            v-for="line in emitterLines"
            :key="line"
            :style="{ fontSize: `${base - 1}px` }"
          >
            {{ line }}
          </div>
        </div>
      </div>
      <div v-else class="flex items-start gap-3">
        <div
          v-if="logo"
          class="shrink-0"
          :style="{ width: '130px', height: '54px' }"
        >
          <img
            :src="logo"
            class="object-contain object-left-top w-full h-full"
          />
        </div>
        <div
          v-if="block.company"
          class="flex-1 min-w-0"
          :class="logo ? 'text-right' : 'text-left'"
          :style="{ lineHeight: 1.25 }"
        >
          <div class="font-bold" :style="{ fontSize: `${base + 1}px` }">
            {{ values?.emitter?.nome }}
          </div>
          <div
            v-for="line in emitterLines"
            :key="line"
            :style="{ fontSize: `${base - 1}px` }"
          >
            {{ line }}
          </div>
        </div>
      </div>
      <div
        v-if="title || subtitle"
        class="flex items-center justify-between gap-2"
        :style="{ marginTop: '12px' }"
      >
        <div
          class="font-bold truncate"
          :style="{
            fontFamily: headingFont,
            fontSize: `${base + 7}px`,
            color: color('primary'),
          }"
        >
          {{ title }}
        </div>
        <span
          v-if="subtitle"
          class="px-2.5 font-bold rounded-full whitespace-nowrap shrink-0 max-w-[50%] truncate"
          :style="{
            fontFamily: headingFont,
            fontSize: `${base - 1}px`,
            background: color('primary'),
            color: contrast('primary'),
            lineHeight: `${base + 9}px`,
          }"
        >
          {{ subtitle }}
        </span>
      </div>
      <div
        v-if="block.style === 'line'"
        :style="{
          height: '2px',
          background: color('primary'),
          marginTop: '5px',
        }"
      />
    </div>

    <!-- título -->
    <div
      v-else-if="block.type === 'heading'"
      class="font-bold"
      :style="{
        fontFamily: headingFont,
        fontSize: `${base + (sizes.heading[block.size] ?? 5)}px`,
        color: color(block.color),
        textAlign: block.align,
        lineHeight: 1.25,
      }"
    >
      {{ fill(block.text) }}
    </div>

    <!-- texto -->
    <div
      v-else-if="block.type === 'text'"
      class="whitespace-pre-wrap"
      :style="{
        fontSize: `${base + (sizes.text[block.size] ?? 0)}px`,
        color: color(block.color),
        textAlign: block.align,
        lineHeight: 1.4,
      }"
    >
      {{ fill(block.text) || t('OUTSIDER_ERP.PRINTS.CANVAS.EMPTY_TEXT') }}
    </div>

    <!-- campos -->
    <div v-else-if="block.type === 'fields'">
      <template v-if="fieldPairs.length">
        <PrintSectionTitle :text="fill(block.title)" :theme="theme" />
        <table
          class="w-full border-collapse table-fixed"
          :style="{ fontSize: `${base}px`, lineHeight: 1.3 }"
        >
          <tr v-for="(row, index) in fieldRows" :key="index">
            <td
              v-for="(pair, column) in row"
              :key="column"
              class="align-top"
              :style="
                block.style === 'boxes'
                  ? {
                      fontSize: `${base}px`,
                      border: `0.6px solid ${color('line')}`,
                      padding: '4px 6px 5px',
                    }
                  : { fontSize: `${base}px`, padding: '2px 8px 4px 0' }
              "
            >
              <template v-if="pair && block.style === 'inline'">
                <b>{{ pair.label }}:</b> {{ pair.value }}
              </template>
              <template v-else-if="pair">
                <div
                  class="font-bold uppercase"
                  :style="{ fontSize: `${base - 2}px`, color: color('muted') }"
                >
                  {{ pair.label }}
                </div>
                <div>{{ pair.value || '-' }}</div>
              </template>
            </td>
          </tr>
        </table>
      </template>
      <div v-else class="italic" :style="{ color: color('muted') }">
        {{ t('OUTSIDER_ERP.PRINTS.CANVAS.HIDDEN_EMPTY') }}
      </div>
    </div>

    <!-- tabela -->
    <div v-else-if="block.type === 'table'">
      <template
        v-if="tableColumns.length && (tableRows.length || !block.hide_empty)"
      >
        <PrintSectionTitle :text="fill(block.title)" :theme="theme" />
        <PrintTable
          :columns="tableColumns"
          :rows="tableRows"
          :theme="theme"
          :striped="block.striped"
        />
      </template>
      <div v-else class="italic" :style="{ color: color('muted') }">
        {{ t('OUTSIDER_ERP.PRINTS.CANVAS.HIDDEN_EMPTY') }}
      </div>
    </div>

    <!-- texto longo -->
    <div v-else-if="block.type === 'long_text'">
      <PrintSectionTitle :text="fill(block.title)" :theme="theme" />
      <div
        class="whitespace-pre-wrap"
        :style="{
          lineHeight: 1.45,
          background: block.boxed ? color('box') : 'transparent',
          padding: block.boxed ? '8px 10px' : '1px 0',
        }"
      >
        {{ longText || '-' }}
      </div>
    </div>

    <!-- totais -->
    <div
      v-else-if="block.type === 'totals'"
      :style="{ marginLeft: block.width === 'full' ? 0 : '55%' }"
    >
      <PrintSectionTitle :text="fill(block.title)" :theme="theme" />
      <div
        v-for="row in totalRows"
        :key="row.key"
        class="flex justify-between"
        :style="{
          padding: '4px 8px',
          borderBottom: `0.5px solid ${color('line')}`,
          ...(row.key === 'total'
            ? {
                background: color('box'),
                fontWeight: 700,
                color: color('primary'),
                fontSize: `${base + 2}px`,
              }
            : {}),
        }"
      >
        <span>{{ row.label }}</span>
        <span>{{ row.value || '-' }}</span>
      </div>
    </div>

    <!-- assinaturas -->
    <div
      v-else-if="block.type === 'signatures'"
      class="flex"
      :style="{ gap: '18px', paddingTop: '24px' }"
    >
      <div
        v-for="label in (block.lines || []).slice(0, 4)"
        :key="label"
        class="flex-1 min-w-0 text-center"
        :style="{ fontSize: `${base - 1}px` }"
      >
        <div class="truncate" :style="{ minHeight: `${base + 2}px` }">
          {{ block.names ? personFor(label) : '' }}
        </div>
        <div
          :style="{
            borderTop: `0.6px solid ${color('text')}`,
            marginTop: '2px',
          }"
        />
        <div :style="{ color: color('muted'), paddingTop: '3px' }">
          {{ label }}
        </div>
        <div
          v-if="block.date"
          :style="{ color: color('muted'), fontSize: `${base - 2}px` }"
        >
          {{ t('OUTSIDER_ERP.PRINTS.CANVAS.SIGN_DATE') }}
        </div>
      </div>
    </div>

    <!-- imagem -->
    <div
      v-else-if="block.type === 'image'"
      class="flex"
      :class="{
        'justify-start': block.align === 'left',
        'justify-center': block.align === 'center',
        'justify-end': block.align === 'right',
      }"
    >
      <img
        v-if="images[block.image_id]"
        :src="images[block.image_id]"
        class="object-contain max-h-[320px]"
        :style="{ width: `${block.width}%` }"
      />
      <div
        v-else
        class="flex flex-col items-center justify-center gap-1 rounded-md outline-dashed outline-1 outline-n-slate-7 text-n-slate-10"
        :style="{ width: `${block.width}%`, height: '90px' }"
      >
        <span class="i-lucide-image-plus size-5" />
        <span class="text-xs">{{
          t('OUTSIDER_ERP.PRINTS.CANVAS.PICK_IMAGE')
        }}</span>
      </div>
    </div>

    <!-- linha -->
    <div
      v-else-if="block.type === 'divider'"
      :style="{
        borderTop: `${block.thickness}px solid ${color(block.color)}`,
        margin: '2px 0',
      }"
    />

    <!-- espaço -->
    <div
      v-else-if="block.type === 'spacer'"
      class="flex items-center justify-center text-[10px] text-n-slate-9 outline-dashed outline-1 outline-n-slate-6 -outline-offset-1"
      :style="{ height: `${block.height}px` }"
    >
      {{ t('OUTSIDER_ERP.PRINTS.CANVAS.SPACE', { size: block.height }) }}
    </div>

    <!-- nova página -->
    <div
      v-else-if="block.type === 'page_break'"
      class="flex items-center gap-2 text-[10px] uppercase tracking-wide text-n-slate-10"
    >
      <span class="flex-1 border-t border-dashed border-n-slate-7" />
      {{ t('OUTSIDER_ERP.PRINTS.CANVAS.PAGE_BREAK') }}
      <span class="flex-1 border-t border-dashed border-n-slate-7" />
    </div>

    <PrintChecklist
      v-else-if="block.type === 'checklist'"
      :block="block"
      :content="content"
      :catalog="catalog"
      :values="values"
      :photos="photos"
      :width="width"
    />
  </div>
</template>
