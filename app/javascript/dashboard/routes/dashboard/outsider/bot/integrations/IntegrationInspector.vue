<script setup>
// OUTSIDER: o painel de cada bloco de integração, dentro do BotInspector.
import ApiBlock from './ApiBlock.vue';
import DbQueryBlock from './DbQueryBlock.vue';
import SheetBlock from './SheetBlock.vue';
import DocSearchBlock from './DocSearchBlock.vue';
import DocSendBlock from './DocSendBlock.vue';
import DecisionBlock from './DecisionBlock.vue';
import FileSendBlock from './FileSendBlock.vue';

defineProps({
  node: { type: Object, required: true },
});

const PANELS = {
  api: ApiBlock,
  db_query: DbQueryBlock,
  sheet: SheetBlock,
  doc_search: DocSearchBlock,
  doc_send: DocSendBlock,
  decision: DecisionBlock,
  file_send: FileSendBlock,
};
</script>

<template>
  <component :is="PANELS[node.type]" v-if="PANELS[node.type]" :node="node" />
</template>
