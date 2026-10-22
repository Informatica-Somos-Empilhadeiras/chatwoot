<script setup>
// OUTSIDER: um bloco do modelo desenhado na folha do editor (Entrega 17), parecido com o PDF: os textos do
// modelo como estão, os dados da proposta como campos automáticos (etiquetas azuis) e uma máquina e um item
// de exemplo. Selecionado, o texto livre, a abertura, o título e o fechamento são editados aqui mesmo.
// A prévia em PDF continua sendo a referência final (quebras de página, medidas exatas).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RichText from './RichText.vue';
import { MAX_TEXT } from './proposalSettings';
import { PT_TO_MM } from './templateDesign';

const props = defineProps({
  block: { type: Object, required: true },
  scale: { type: Number, required: true },
  imageUrls: { type: Object, default: () => ({}) },
  editing: { type: Boolean, default: false },
  isUploading: { type: Boolean, default: false },
});

const emit = defineEmits(['update:block', 'upload', 'pickImage']);

const form = defineModel('form', { type: Object, required: true });

const { t } = useI18n();

// o PDF sai sempre em português; os rótulos fixos dele ficam iguais aqui
const SAMPLE = {
  machine: 'Empilhadeira elétrica 2,5 t',
  specs: [
    ['Capacidade de carga', '2500 kg'],
    ['Altura de elevação', '4.500 mm'],
    ['Motor', 'Elétrico 48 V'],
    ['Pneus', 'Superelásticos'],
  ],
  equipment: ['Torre triplex', 'Deslocador lateral', 'Bateria 48 V / 500 Ah'],
  price: 'R$ 150.000,00',
  discount: 'R$ 0,00',
  itemsHeader: ['Item', 'Descrição', 'Qtd.', 'Valor Unit.', 'Total'],
};

const STAMP = new Intl.DateTimeFormat('pt-BR', {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
}).format(new Date());

const mm = value => `${value * props.scale}px`;
const pt = value => mm(value * PT_TO_MM);

const style = computed(() => ({
  fontSize: pt(props.block.size || 9),
  fontWeight: props.block.bold ? 700 : undefined,
  lineHeight: 1.3,
}));

const highlightClass = computed(() =>
  props.block.highlight ? 'bg-[#ffff00]' : ''
);

const itemsHeader = computed(() => {
  const header = [...SAMPLE.itemsHeader];
  if (form.value.show_discount) header.splice(4, 0, 'Desc.');
  return header;
});
const itemsRow = computed(() => [
  '1',
  SAMPLE.machine,
  '1',
  SAMPLE.price,
  ...(form.value.show_discount ? [SAMPLE.discount] : []),
  SAMPLE.price,
]);

const customerLines = [
  ['EMPRESA', '{cliente.empresa}'],
  ['CNPJ', '{cliente.documento}'],
  ['ENDEREÇO', '{cliente.endereco}'],
  ['CIDADE', '{cliente.cidade} - {cliente.estado} - {cliente.cep}'],
  ['FONE', '{cliente.telefone}'],
  ['E-MAIL', '{cliente.email}'],
];

const imageUrl = computed(() => props.imageUrls[props.block.image_id] || '');
const imageStyle = computed(() => ({
  width: `${props.block.width}%`,
  marginLeft: props.block.align === 'left' ? 0 : 'auto',
  marginRight: props.block.align === 'right' ? 0 : 'auto',
}));

const set = (key, value) => {
  emit('update:block', { ...props.block, [key]: value });
};

// caixa de texto que cresce com o conteúdo, para editar na folha
const fit = element => {
  element.style.height = 'auto';
  element.style.height = `${element.scrollHeight}px`;
};
const grow = element => {
  if (element) requestAnimationFrame(() => fit(element));
};
const onInput = (event, apply) => {
  apply(event.target.value);
  fit(event.target);
};

const isDropping = ref(false);
const onDrop = event => {
  isDropping.value = false;
  const [file] = event.dataTransfer?.files || [];
  if (file) emit('upload', file);
};

const editClass =
  'block w-full !m-0 !p-0 min-h-[1.3em] overflow-hidden !bg-transparent !border-0 !shadow-none rounded-none !outline-none resize-none reset-base !text-[#000] [font-family:inherit] [font-size:inherit] [line-height:inherit] placeholder:text-slate-400 placeholder:italic';
</script>

<template>
  <div
    class="text-[#000] text-left crm-sheet-block"
    :class="{ 'bg-[#ffff00]': block.highlight && block.type === 'text' }"
    :style="style"
  >
    <!-- Data e número -->
    <div v-if="block.type === 'date_number'" class="flex justify-between gap-4">
      <RichText :text="`{empresa.cidade}, ${STAMP}`" :class="highlightClass" />
      <span :class="highlightClass">
        <b>PROPOSTA</b>
        <RichText text=" {proposta.numero}" />
      </span>
    </div>

    <!-- Cliente -->
    <div v-else-if="block.type === 'customer'" :class="highlightClass">
      <div v-for="[label, value] in customerLines" :key="label">
        {{ `${label}: ` }}<RichText :text="`**${value}**`" />
      </div>
      <div :style="{ marginTop: pt(10) }">
        <RichText text="Atenção: {cliente.atencao}" />
      </div>
    </div>

    <!-- Abertura e fechamento -->
    <template v-else-if="['intro', 'closing'].includes(block.type)">
      <div v-if="editing" data-fields>
        <textarea
          :ref="grow"
          :value="form[block.type]"
          :maxlength="MAX_TEXT"
          rows="1"
          :class="editClass"
          class="text-justify"
          :placeholder="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.TYPE_HERE')"
          data-inline-edit
          @input="onInput($event, value => (form[block.type] = value))"
        />
      </div>
      <div v-else class="mb-0 text-justify" :class="highlightClass">
        <RichText
          :text="form[block.type]"
          :placeholder="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.EMPTY_TEXT')"
        />
      </div>
    </template>

    <!-- Título -->
    <div v-else-if="block.type === 'title'" class="font-bold">
      <div v-if="editing" data-fields class="flex items-baseline gap-1">
        <input
          :value="form.title_prefix"
          type="text"
          :maxlength="MAX_TEXT"
          :class="editClass"
          class="!w-auto flex-1 font-bold"
          :placeholder="
            t('OUTSIDER_CRM.PROPOSAL_SETTINGS.TEMPLATES.TEXTS.TITLE_PREFIX')
          "
          data-inline-edit
          @input="form.title_prefix = $event.target.value"
        />
        <RichText text="{proposta.titulo}" />
      </div>
      <span v-else :class="highlightClass">
        <RichText :text="`${form.title_prefix} {proposta.titulo}`" />
      </span>
    </div>

    <!-- Características das máquinas -->
    <div v-else-if="block.type === 'specs'" :class="highlightClass">
      <div v-if="block.heading" class="font-bold" :style="{ marginBottom: pt(4) }">
        <RichText :text="block.heading" />
      </div>
      <div
        class="flex gap-3"
        :class="{ 'flex-row-reverse': block.image_side === 'left' }"
      >
        <table class="w-[60%] border-collapse">
          <tbody>
            <tr v-for="[label, value] in SAMPLE.specs" :key="label">
              <td class="px-1 border border-slate-300 bg-slate-100">
                {{ label }}
              </td>
              <td class="px-1 border border-slate-300">{{ value }}</td>
            </tr>
          </tbody>
        </table>
        <div
          class="flex flex-col items-center justify-center flex-1 gap-1 rounded bg-slate-100 text-slate-400"
          :style="{ minHeight: pt(70) }"
        >
          <span class="i-lucide-forklift size-8" />
          <span class="text-[0.8em]">
            {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.MACHINE_IMAGE') }}
          </span>
        </div>
      </div>
      <template v-if="block.equipment">
        <div class="font-bold" :style="{ marginTop: pt(8) }">
          <RichText :text="block.equipment_heading" />
        </div>
        <div v-for="line in SAMPLE.equipment" :key="line">
          {{ `• ${line}` }}
        </div>
      </template>
    </div>

    <!-- Itens e total -->
    <table
      v-else-if="block.type === 'items'"
      class="w-full border-collapse"
      :class="highlightClass"
    >
      <thead>
        <tr>
          <th
            v-for="label in itemsHeader"
            :key="label"
            class="px-1 font-bold text-left border border-slate-300"
          >
            {{ label }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td
            v-for="(value, index) in itemsRow"
            :key="index"
            class="px-1 border border-slate-300"
            :class="{ 'text-right': index > 1, 'text-center': index === 0 }"
          >
            {{ value }}
          </td>
        </tr>
        <tr>
          <td
            :colspan="itemsHeader.length"
            class="px-1 py-0.5 text-right border border-slate-300"
          >
            <b>{{ form.total_label || 'Total:' }}</b>
            {{ ` ${SAMPLE.price}` }}
          </td>
        </tr>
      </tbody>
    </table>

    <!-- Condições -->
    <div v-else-if="block.type === 'conditions'" :class="highlightClass">
      <table
        v-if="form.conditions_style !== 'list'"
        class="w-full border-collapse"
      >
        <tbody>
          <tr v-for="row in form.conditions" :key="row.uid">
            <td class="w-[30%] px-1 align-top border border-slate-300">
              <RichText :text="row.label" />
            </td>
            <td class="px-1 border border-slate-300">
              <RichText :text="row.text" />
            </td>
          </tr>
        </tbody>
      </table>
      <template v-else>
        <div v-if="form.conditions_heading" class="font-bold">
          <RichText :text="form.conditions_heading" />
        </div>
        <div
          v-for="row in form.conditions"
          :key="row.uid"
          class="text-justify"
        >
          {{ '• ' }}<RichText
            :text="row.label ? `**${row.label}:** ${row.text}` : row.text"
          />
        </div>
      </template>
      <div
        v-if="!form.conditions.length"
        class="mb-0 italic text-slate-400"
      >
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.NO_CONDITIONS') }}
      </div>
    </div>

    <!-- Partes -->
    <div v-else-if="block.type === 'parties'" :class="highlightClass">
      <div class="font-bold">{{ 'PARTES:' }}</div>
      <div class="mb-0 text-justify"><RichText :text="form.parties_text" /></div>
      <div class="mb-0 text-justify" :style="{ marginTop: pt(6) }">
        <RichText :text="form.acceptance_text" />
      </div>
    </div>

    <!-- Pedido e dados bancários -->
    <div v-else-if="block.type === 'bank'" class="flex flex-col" :style="{ gap: pt(10) }">
      <div>
        <div v-if="form.order_heading" class="font-bold bg-[#ffff00] w-fit">
          <RichText :text="form.order_heading" />
        </div>
        <RichText
          text="**{empresa.razao_social}**&#10;{empresa.cnpj}&#10;{empresa.endereco}"
        />
      </div>
      <div>
        <div v-if="form.bank_heading" class="font-bold bg-[#ffff00] w-fit">
          <RichText :text="form.bank_heading" />
        </div>
        <span class="italic text-slate-500">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.BANK_DETAILS') }}
        </span>
      </div>
      <div>
        <div v-if="form.documents_heading" class="font-bold bg-[#ffff00] w-fit">
          <RichText :text="form.documents_heading" />
        </div>
        <RichText text="{empresa.email_documentos}" />
      </div>
    </div>

    <!-- Assinatura e aceite -->
    <div v-else-if="block.type === 'signature'" :class="highlightClass">
      <div class="text-center" :style="{ fontSize: pt((block.size || 10) - 1) }">
        <div>{{ 'Atenciosamente,' }}</div>
        <div :style="{ marginTop: pt(14) }">
          <RichText text="{vendedor.nome}&#10;{vendedor.cargo}&#10;{vendedor.telefone}" />
        </div>
      </div>
      <div
        class="p-1.5 border border-slate-400"
        :style="{ marginTop: pt(14) }"
      >
        <RichText :text="form.signature_box" />
        <div :style="{ marginTop: pt(10) }">
          {{ 'Ass: ______________________________________' }}
        </div>
        <div>{{ 'Nome / Dep.: ______________________________' }}</div>
        <div>{{ 'Data:  _______ / _______ / _______' }}</div>
      </div>
    </div>

    <!-- Observações -->
    <div v-else-if="block.type === 'notes'" :class="highlightClass">
      <div class="font-bold">{{ 'Observações' }}</div>
      <span class="italic text-slate-500">
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.NOTES_SAMPLE') }}
      </span>
    </div>

    <!-- Texto livre -->
    <div v-else-if="block.type === 'text'">
      <div v-if="editing" data-fields class="flex flex-col">
        <input
          :value="block.heading"
          type="text"
          maxlength="200"
          :class="editClass"
          class="font-bold"
          :style="{ fontSize: pt((block.size || 9) + 1), marginBottom: pt(4) }"
          :placeholder="
            t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HEADING_PLACEHOLDER')
          "
          data-inline-edit
          @input="set('heading', $event.target.value)"
        />
        <textarea
          :ref="grow"
          :value="block.text"
          :maxlength="MAX_TEXT"
          rows="1"
          :class="editClass"
          class="text-justify"
          :placeholder="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.TYPE_HERE')"
          data-inline-edit
          @input="onInput($event, value => set('text', value))"
        />
      </div>
      <template v-else>
        <div
          v-if="block.heading"
          class="font-bold"
          :style="{ fontSize: pt((block.size || 9) + 1), marginBottom: pt(4) }"
        >
          <RichText :text="block.heading" />
        </div>
        <div class="mb-0 text-justify">
          <RichText
            :text="block.text"
            :placeholder="
              block.heading
                ? ''
                : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.EMPTY_TEXT')
            "
          />
        </div>
      </template>
    </div>

    <!-- Imagem -->
    <div v-else-if="block.type === 'image'">
      <img
        v-if="imageUrl"
        :src="imageUrl"
        alt=""
        class="block"
        :style="imageStyle"
        draggable="false"
      />
      <div
        v-else
        class="flex flex-col items-center justify-center gap-2 py-6 border border-dashed rounded text-slate-600"
        :class="isDropping ? 'border-n-brand bg-blue-50' : 'border-slate-300 bg-slate-50'"
        data-image-drop
        @dragover.prevent="isDropping = true"
        @dragleave="isDropping = false"
        @drop.prevent="onDrop"
      >
        <button
          type="button"
          class="px-3 py-1.5 text-sm bg-white border rounded-lg shadow-sm border-slate-300 hover:bg-slate-50"
          :disabled="isUploading"
          @click.stop="emit('pickImage')"
        >
          {{
            isUploading
              ? t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.UPLOADING')
              : t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.PICK_IMAGE')
          }}
        </button>
        <span class="text-sm">
          {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.DROP_IMAGE') }}
        </span>
      </div>
    </div>

    <!-- Linha -->
    <div v-else-if="block.type === 'divider'" :style="{ padding: `${pt(2)} 0` }">
      <div
        :style="{
          borderTop: `${Math.max(1, block.thickness * PT_TO_MM * scale)}px solid #${block.color}`,
        }"
      />
    </div>

    <!-- Espaço -->
    <div
      v-else-if="block.type === 'spacer'"
      class="flex items-center justify-center text-[11px] text-slate-400 bg-[repeating-linear-gradient(45deg,transparent,transparent_6px,rgba(148,163,184,0.12)_6px,rgba(148,163,184,0.12)_12px)]"
      :style="{ height: mm(block.height) }"
    >
      {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.SPACER_SIZE', { mm: block.height }) }}
    </div>
  </div>
</template>

<style scoped>
/* o estilo geral do painel mexe no tamanho de tabela e parágrafo: na folha vale o do bloco */
.crm-sheet-block :is(table, th, td) {
  font-size: inherit;
  line-height: inherit;
}
</style>
