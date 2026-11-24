<script setup>
// OUTSIDER: bloco Checklist na folha do estúdio, como no PDF (Outsider::Erp::Prints::Pdf::Checklist).
// Com fotos: um grupo por item, com o título no estilo escolhido (faixa, ao lado, cartão, compacto) e as fotos no arranjo
// (automático: 1 grande, 2 lado a lado, 3 em linha, 4 em 2x2, 5+ em 3 colunas). Sem fotos: só as respostas, em tabela,
// lista ou grade. O filtro de seções deixa cada bloco com as seções dele.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PrintTable from './PrintTable.vue';
import PrintSectionTitle from './PrintSectionTitle.vue';
import {
  checklistSections,
  chosenFields,
  columnsFor,
  contrastColor,
  countLabel,
  fillPlaceholders,
  photoHeight,
  photoSource,
  readingOf,
  themeColor,
} from './printsHelpers';

const props = defineProps({
  block: { type: Object, required: true },
  content: { type: Object, required: true },
  catalog: { type: Object, required: true },
  values: { type: Object, default: null },
  photos: { type: Object, default: () => ({}) },
  width: { type: Number, required: true },
});

const { t } = useI18n();

const GAP = 6;
const SIDE = 130;
const THUMB = 44;

const theme = computed(() => props.content.theme || {});
const base = computed(() => Number(theme.value.size) || 9);
const color = name => themeColor(theme.value, name);
const withPhotos = computed(() => props.block.photos !== 'without');
const sections = computed(() => checklistSections(props.values, props.block));

const itemPhotos = item =>
  (item.fotos || [])
    .map(photo => photoSource(photo, props.photos))
    .filter(Boolean)
    .slice(0, Number(props.block.max) || 12);

// grupos com fotos: itens com foto (ou todos, com "mostrar itens sem foto")
const photoSections = computed(() =>
  sections.value
    .map(section => ({
      nome: section.nome,
      itens: (section.itens || [])
        .map(item => ({ ...item, srcs: itemPhotos(item) }))
        .filter(item => item.srcs.length || props.block.show_empty),
    }))
    .filter(section => section.itens.length)
);

const answered = items =>
  (items || []).filter(
    item => props.block.show_empty || item.chegada || item.saida
  );

const answerSections = computed(() =>
  sections.value
    .map(section => ({ nome: section.nome, itens: answered(section.itens) }))
    .filter(section => section.itens.length)
);

const tableColumns = computed(() =>
  chosenFields(props.content, props.catalog, 'checklist').filter(
    column => props.block.show_sections || column.key !== 'secao'
  )
);
const tableRows = computed(() =>
  answerSections.value.flatMap(section =>
    section.itens.map(item => ({
      secao: section.nome,
      item: item.atributo,
      chegada: item.chegada,
      saida: item.saida,
    }))
  )
);

const gridColumns = computed(() =>
  Math.min(Math.max(Number(props.block.grid_columns) || 2, 2), 3)
);

// medidas das fotos de um grupo: colunas, largura e altura de cada célula
const layout = (count, width) => {
  const columns =
    props.block.title_style === 'side'
      ? Math.min(columnsFor(props.block, count), 3)
      : columnsFor(props.block, count);
  const cell = (width - GAP * (columns - 1)) / columns;
  return { columns, cell, height: photoHeight(props.block, columns, cell) };
};

const gridStyle = (count, width) => {
  const { columns, cell, height } = layout(count, width);
  return {
    display: 'grid',
    gridTemplateColumns: `repeat(${columns}, ${cell}px)`,
    gridAutoRows: `${height}px`,
    gap: `${GAP}px`,
  };
};

const reading = item => (props.block.show_reading ? readingOf(item) : '');
const count = item => countLabel(props.block, item.srcs);
const hasContent = computed(() =>
  withPhotos.value ? photoSections.value.length : answerSections.value.length
);
</script>

<template>
  <div>
    <PrintSectionTitle
      v-if="hasContent"
      :text="fillPlaceholders(block.title, values?.placeholders)"
      :theme="theme"
    />
    <div v-if="!hasContent" class="italic" :style="{ color: color('muted') }">
      {{ t('OUTSIDER_ERP.PRINTS.CANVAS.CHECKLIST_EMPTY') }}
    </div>

    <!-- com fotos -->
    <template v-else-if="withPhotos">
      <div
        v-for="section in photoSections"
        :key="section.nome"
        :style="{ marginBottom: '4px' }"
      >
        <div
          v-if="block.show_sections && section.nome"
          class="font-bold uppercase"
          :style="{
            fontSize: `${base - 0.5}px`,
            color: color('muted'),
            letterSpacing: '0.5px',
            margin: '2px 0 4px',
          }"
        >
          {{ section.nome }}
        </div>
        <div
          v-for="(item, index) in section.itens"
          :key="index"
          :style="{ marginTop: index ? `${GAP + 2}px` : 0 }"
        >
          <!-- faixa -->
          <template v-if="block.title_style === 'band'">
            <div
              class="flex items-center justify-between font-bold"
              :style="{
                background: color('primary'),
                color: contrastColor(theme, 'primary'),
                borderRadius: '3px',
                height: `${base + 9}px`,
                padding: '0 7px',
                marginBottom: '4px',
              }"
            >
              <span
                class="truncate"
                :style="{ fontFamily: 'var(--print-heading)' }"
              >
                {{ item.atributo }}
              </span>
              <span
                class="font-normal"
                :style="{ fontSize: `${base - 1.5}px` }"
              >
                {{ count(item) }}
              </span>
            </div>
            <div
              v-if="reading(item)"
              class="italic"
              :style="{
                fontSize: `${base - 1}px`,
                color: color('muted'),
                marginBottom: '4px',
              }"
            >
              {{ reading(item) }}
            </div>
            <div
              v-if="item.srcs.length"
              :style="gridStyle(item.srcs.length, width)"
            >
              <div
                v-for="(src, photoIndex) in item.srcs"
                :key="photoIndex"
                class="relative flex items-center justify-center overflow-hidden"
                :style="{ background: color('row'), borderRadius: '3px' }"
              >
                <img :src="src" class="object-contain max-w-full max-h-full" />
                <span
                  v-if="block.numbering"
                  class="absolute px-1 text-white rounded-sm bottom-1 right-1 bg-black/60"
                  :style="{ fontSize: `${base - 2.5}px` }"
                >
                  {{ photoIndex + 1 }}/{{ item.srcs.length }}
                </span>
              </div>
            </div>
          </template>

          <!-- título ao lado -->
          <div v-else-if="block.title_style === 'side'" class="flex gap-2.5">
            <div
              class="shrink-0"
              :style="{
                width: `${SIDE - 2}px`,
                borderLeft: `3px solid ${color('accent')}`,
                paddingLeft: '7px',
                minHeight: '36px',
              }"
            >
              <div class="font-bold" :style="{ color: color('primary') }">
                {{ item.atributo }}
              </div>
              <div
                v-if="count(item)"
                :style="{ fontSize: `${base - 1.5}px`, color: color('muted') }"
              >
                {{ count(item) }}
              </div>
              <div
                v-if="reading(item)"
                class="italic"
                :style="{ fontSize: `${base - 1}px`, color: color('muted') }"
              >
                {{ reading(item) }}
              </div>
            </div>
            <div
              v-if="item.srcs.length"
              :style="gridStyle(item.srcs.length, width - SIDE - 10)"
            >
              <div
                v-for="(src, photoIndex) in item.srcs"
                :key="photoIndex"
                class="relative flex items-center justify-center overflow-hidden"
                :style="{ background: color('row'), borderRadius: '3px' }"
              >
                <img :src="src" class="object-contain max-w-full max-h-full" />
                <span
                  v-if="block.numbering"
                  class="absolute px-1 text-white rounded-sm bottom-1 right-1 bg-black/60"
                  :style="{ fontSize: `${base - 2.5}px` }"
                >
                  {{ photoIndex + 1 }}/{{ item.srcs.length }}
                </span>
              </div>
            </div>
          </div>

          <!-- cartão -->
          <div
            v-else-if="block.title_style === 'card'"
            :style="{
              border: `1px solid ${color('line')}`,
              borderRadius: '4px',
            }"
          >
            <div
              v-if="item.srcs.length"
              :style="{
                ...gridStyle(item.srcs.length, width - 12),
                padding: '6px 6px 0',
              }"
            >
              <div
                v-for="(src, photoIndex) in item.srcs"
                :key="photoIndex"
                class="relative flex items-center justify-center overflow-hidden"
                :style="{ background: color('row'), borderRadius: '3px' }"
              >
                <img :src="src" class="object-contain max-w-full max-h-full" />
                <span
                  v-if="block.numbering"
                  class="absolute px-1 text-white rounded-sm bottom-1 right-1 bg-black/60"
                  :style="{ fontSize: `${base - 2.5}px` }"
                >
                  {{ photoIndex + 1 }}/{{ item.srcs.length }}
                </span>
              </div>
            </div>
            <div
              :style="{
                padding: '5px 8px',
                marginTop: item.srcs.length ? '6px' : 0,
                borderTop: item.srcs.length
                  ? `0.6px solid ${color('line')}`
                  : 'none',
              }"
            >
              <b>{{ item.atributo }}</b>
              <span v-if="count(item)" :style="{ color: color('muted') }">
                · {{ count(item) }}
              </span>
              <i v-if="reading(item)" :style="{ color: color('muted') }">
                &nbsp; {{ reading(item) }}
              </i>
            </div>
          </div>

          <!-- compacto -->
          <div
            v-else
            class="flex gap-2"
            :style="{
              borderBottom: `0.4px solid ${color('line')}`,
              paddingBottom: '4px',
            }"
          >
            <div class="shrink-0" :style="{ width: `${width * 0.42}px` }">
              <b>{{ item.atributo }}</b>
              <span v-if="count(item)" :style="{ color: color('muted') }">
                ({{ count(item) }})
              </span>
              <div
                v-if="reading(item)"
                class="italic"
                :style="{ fontSize: `${base - 1}px`, color: color('muted') }"
              >
                {{ reading(item) }}
              </div>
            </div>
            <div class="flex flex-wrap gap-1">
              <div
                v-for="(src, photoIndex) in item.srcs"
                :key="photoIndex"
                class="flex items-center justify-center overflow-hidden"
                :style="{
                  width: `${THUMB * 1.33}px`,
                  height: `${THUMB}px`,
                  background: color('row'),
                  borderRadius: '3px',
                }"
              >
                <img :src="src" class="object-contain max-w-full max-h-full" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>

    <!-- sem fotos: tabela -->
    <PrintTable
      v-else-if="block.answers === 'table'"
      :columns="tableColumns"
      :rows="tableRows"
      :theme="theme"
    />

    <!-- sem fotos: lista ou grade -->
    <template v-else>
      <div
        v-for="section in answerSections"
        :key="section.nome"
        :style="{ marginBottom: '6px' }"
      >
        <div
          v-if="block.show_sections && section.nome"
          class="font-bold uppercase"
          :style="{
            fontSize: `${base - 0.5}px`,
            color: color('muted'),
            letterSpacing: '0.5px',
            margin: '2px 0 4px',
          }"
        >
          {{ section.nome }}
        </div>
        <template v-if="block.answers === 'list'">
          <div
            v-for="(item, index) in section.itens"
            :key="index"
            :style="{ marginBottom: '2px' }"
          >
            <b>{{ item.atributo }}:</b> {{ readingOf(item) || '-' }}
          </div>
        </template>
        <div
          v-else
          class="grid"
          :style="{ gridTemplateColumns: `repeat(${gridColumns}, 1fr)` }"
        >
          <div
            v-for="(item, index) in section.itens"
            :key="index"
            :style="{
              border: `0.6px solid ${color('line')}`,
              padding: '4px 6px 5px',
              margin: '0 -0.3px -0.6px 0',
            }"
          >
            <div
              class="font-bold uppercase"
              :style="{ fontSize: `${base - 2}px`, color: color('muted') }"
            >
              {{ item.atributo }}
            </div>
            <div>{{ readingOf(item) || '-' }}</div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
