<script setup>
// OUTSIDER: conteúdo do modelo em blocos, na ordem do PDF. Arrastar muda a ordem; o olho esconde o bloco
// sem perder os textos; "Bloco de texto" acrescenta um texto livre com título (garantia, prazo...).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import Button from 'dashboard/components-next/button/Button.vue';
import TemplateBlockItem from './TemplateBlockItem.vue';
import { MAX_BLOCKS, textBlock } from './templateDesign';

const blocks = defineModel('blocks', { type: Array, required: true });
const form = defineModel('form', { type: Object, required: true });

const { t } = useI18n();

const openKey = ref(null);

const toggle = key => {
  openKey.value = openKey.value === key ? null : key;
};

const replace = (index, block) => {
  blocks.value = blocks.value.map((item, position) =>
    position === index ? block : item
  );
};

const add = () => {
  if (blocks.value.length >= MAX_BLOCKS) return;
  const block = textBlock();
  blocks.value = [...blocks.value, block];
  openKey.value = block.key;
};

const remove = index => {
  blocks.value = blocks.value.filter((_, position) => position !== index);
};

// vuedraggable muda a lista no lugar; a cópia avisa o editor de que mudou
const onSort = list => {
  blocks.value = [...list];
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <Draggable
      :model-value="blocks"
      item-key="key"
      handle=".crm-block-handle"
      :animation="150"
      class="flex flex-col gap-2"
      @update:model-value="onSort"
    >
      <template #item="{ element, index }">
        <TemplateBlockItem
          v-model:form="form"
          :block="element"
          :expanded="openKey === element.key"
          @update:block="block => replace(index, block)"
          @toggle="toggle(element.key)"
          @remove="remove(index)"
        />
      </template>
    </Draggable>
    <div>
      <Button
        type="button"
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-plus"
        :label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.ADD_TEXT')"
        :disabled="blocks.length >= MAX_BLOCKS"
        @click="add"
      />
    </div>
  </div>
</template>
